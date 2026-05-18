#!/usr/bin/env bash
set -euo pipefail

# diagnose_dummy_reflection.sh
#
# Purpose:
#   Diagnose why 6-month dummy data is not reflected in the app.
#
# Usage:
#   cd /workspaces/kakeibo
#   bash diagnose_dummy_reflection.sh
#
# Optional:
#   BASE_YM=2026-05 API_BASE=http://localhost:8000 bash diagnose_dummy_reflection.sh
#
# This script does not modify data.

BASE_YM="${BASE_YM:-2026-05}"
API_BASE="${API_BASE:-http://localhost:8000}"

echo "==> pwd"
pwd
echo

echo "==> candidate sqlite DB files"
mapfile -t DBS < <(
  find . -maxdepth 4 -type f \( -name "*.db" -o -name "*.sqlite" -o -name "*.sqlite3" \) \
    | sed 's#^\./##' \
    | sort
)

if [ "${#DBS[@]}" -eq 0 ]; then
  echo "NO DB FILES FOUND under current directory."
else
  printf '  %s\n' "${DBS[@]}"
fi
echo

echo "==> database references in source"
grep -RIn --exclude-dir=node_modules --exclude-dir=.git --exclude='*.pyc' \
  -E 'sqlite|DATABASE_URL|create_engine|SessionLocal|data\.db' \
  backend 2>/dev/null | head -80 || true
echo

python3 - "$BASE_YM" "${DBS[@]}" <<'PY'
import sqlite3
import sys
from pathlib import Path

base_ym = sys.argv[1]
dbs = sys.argv[2:]

def q(x):
    return '"' + x.replace('"', '""') + '"'

def has_table(conn, name):
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (name,),
    ).fetchone() is not None

def cols(conn, table):
    return [r[1] for r in conn.execute(f"PRAGMA table_info({q(table)})").fetchall()]

def first(cols, names):
    for n in names:
        if n in cols:
            return n
    return None

print("==> DB content check")
if not dbs:
    print("  No DBs to inspect.")
    sys.exit(0)

for db in dbs:
    print(f"\n--- {db}")
    try:
        conn = sqlite3.connect(db)
        conn.row_factory = sqlite3.Row
    except Exception as e:
        print(f"  ERROR opening DB: {e}")
        continue

    try:
        if not has_table(conn, "transactions"):
            print("  transactions table: NOT FOUND")
            conn.close()
            continue

        c = cols(conn, "transactions")
        print("  transactions columns:", ", ".join(c))

        date_col = first(c, ["purchased_at", "transaction_date", "date", "occurred_at", "created_at"])
        amount_col = first(c, ["amount", "price", "total_amount"])
        tx_type_col = first(c, ["tx_type", "transaction_type", "type", "kind"])
        cat_col = first(c, ["screening_category", "category", "category_name"])
        merchant_raw_col = first(c, ["merchant_raw", "raw_merchant", "store_raw"])
        memo_col = first(c, ["memo", "note", "description", "comment"])
        source_col = first(c, ["source"])

        total = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
        print(f"  total rows: {total}")

        dummy_clauses = []
        params = []
        if merchant_raw_col:
            dummy_clauses.append(f"{q(merchant_raw_col)} LIKE ?")
            params.append("[dummy-6m]%")
        if memo_col:
            dummy_clauses.append(f"{q(memo_col)} LIKE ?")
            params.append("[dummy-6m]%")
        if source_col:
            dummy_clauses.append(f"{q(source_col)} = ?")
            params.append("dummy_6months")

        if dummy_clauses:
            dummy = conn.execute(
                "SELECT COUNT(*) FROM transactions WHERE " + " OR ".join(dummy_clauses),
                params,
            ).fetchone()[0]
            print(f"  dummy rows: {dummy}")
        else:
            print("  dummy rows: cannot detect marker columns")

        if not (date_col and amount_col):
            print("  monthly summary: skipped; date/amount column not found")
            conn.close()
            continue

        where_month = f"substr({q(date_col)}, 1, 7)=?"
        if tx_type_col:
            sql = (
                f"SELECT "
                f"COALESCE(SUM(CASE WHEN {q(tx_type_col)}='income' THEN {q(amount_col)} ELSE 0 END),0) AS income, "
                f"COALESCE(SUM(CASE WHEN {q(tx_type_col)}='expense' OR {q(tx_type_col)} IS NULL THEN {q(amount_col)} ELSE 0 END),0) AS expense, "
                f"COUNT(*) AS n "
                f"FROM transactions WHERE {where_month}"
            )
            r = conn.execute(sql, (base_ym,)).fetchone()
            print(f"  {base_ym}: rows={r['n']} income={int(r['income'])} expense={int(r['expense'])} balance={int(r['income']-r['expense'])}")
        else:
            r = conn.execute(
                f"SELECT COUNT(*) AS n, COALESCE(SUM({q(amount_col)}),0) AS amount FROM transactions WHERE {where_month}",
                (base_ym,),
            ).fetchone()
            print(f"  {base_ym}: rows={r['n']} amount={int(r['amount'])} tx_type_col=NONE")

        if date_col and amount_col and tx_type_col:
            rows = conn.execute(
                f"SELECT substr({q(date_col)},1,7) AS ym, {q(tx_type_col)} AS tx_type, COUNT(*) AS n, SUM({q(amount_col)}) AS amount "
                f"FROM transactions "
                f"GROUP BY ym, tx_type "
                f"ORDER BY ym, tx_type"
            ).fetchall()
            print("  all-month summary:")
            for r in rows[-20:]:
                print(f"    {r['ym']} [{r['tx_type']}]: rows={r['n']} amount={int(r['amount'] or 0)}")

        if cat_col and date_col and amount_col and tx_type_col:
            rows = conn.execute(
                f"SELECT {q(cat_col)} AS category, {q(tx_type_col)} AS tx_type, COUNT(*) AS n, SUM({q(amount_col)}) AS amount "
                f"FROM transactions "
                f"WHERE {where_month} "
                f"GROUP BY {q(cat_col)}, {q(tx_type_col)} "
                f"ORDER BY {q(tx_type_col)}, amount DESC",
                (base_ym,),
            ).fetchall()
            print(f"  {base_ym} categories:")
            for r in rows[:20]:
                print(f"    [{r['tx_type']}] {r['category']}: rows={r['n']} amount={int(r['amount'] or 0)}")

    except Exception as e:
        print(f"  ERROR inspecting DB: {e}")
    finally:
        conn.close()
PY

echo
echo "==> API check"
if command -v curl >/dev/null 2>&1; then
  echo "-- ${API_BASE}/api/summary/cashflow?ym=${BASE_YM}"
  curl -fsS "${API_BASE}/api/summary/cashflow?ym=${BASE_YM}" 2>/tmp/diag_api_error \
    | python3 -m json.tool || { echo "  API unavailable or endpoint failed"; cat /tmp/diag_api_error 2>/dev/null || true; }
  echo
  echo "-- ${API_BASE}/api/summary/month_compare?ym=${BASE_YM}"
  curl -fsS "${API_BASE}/api/summary/month_compare?ym=${BASE_YM}" 2>/tmp/diag_api_error \
    | python3 -m json.tool || { echo "  API unavailable or endpoint failed"; cat /tmp/diag_api_error 2>/dev/null || true; }
else
  echo "curl not found; skipped."
fi

echo
echo "==> interpretation"
echo "1) dummy rows = 0 in every DB: seed script did not run, or ran outside this project."
echo "2) dummy rows exist in one DB, but API returns old values: backend is using a different DB path."
echo "3) API returns dummy values, but UI does not: frontend cache/state issue or GraphView is not calling the new API."
echo "4) API endpoint failed: backend not restarted, router not mounted, or summary API patch not applied."
