#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   cd /workspaces/kakeibo
#   BASE_YM=2026-05 BASE_DAY=18 bash seed_dummy_6months.sh
#
# Env:
#   DB_PATH      SQLite DB path. default: backend/data.db
#   BASE_YM      Last month to seed, format YYYY-MM. default: current month
#   BASE_DAY     Day cap for BASE_YM. default: today
#   CLEAR_DUMMY  1 = remove previous dummy rows first. default: 1
#   SEED         random seed. default: 20260518

DB_PATH="${DB_PATH:-backend/data.db}"
BASE_YM="${BASE_YM:-$(date +%Y-%m)}"
BASE_DAY="${BASE_DAY:-$(date +%d)}"
CLEAR_DUMMY="${CLEAR_DUMMY:-1}"
SEED="${SEED:-20260518}"

if [ ! -f "$DB_PATH" ]; then
  echo "ERROR: DB not found: $DB_PATH" >&2
  echo "Run this from the project root, e.g. /workspaces/kakeibo" >&2
  exit 1
fi

BACKUP_PATH="${DB_PATH}.bak_before_dummy6m_$(date +%Y%m%d_%H%M%S)"
cp "$DB_PATH" "$BACKUP_PATH"
echo "==> backup: $BACKUP_PATH"

python3 - "$DB_PATH" "$BASE_YM" "$BASE_DAY" "$CLEAR_DUMMY" "$SEED" <<'PY'
import calendar
import random
import sqlite3
import sys
from datetime import datetime

DB_PATH, BASE_YM, BASE_DAY, CLEAR_DUMMY, SEED = sys.argv[1], sys.argv[2], int(sys.argv[3]), sys.argv[4], int(sys.argv[5])
MARKER = "[dummy-6m]"

def q(name: str) -> str:
    return '"' + name.replace('"', '""') + '"'

def parse_ym(ym: str):
    try:
        y, m = ym.split("-")
        y, m = int(y), int(m)
        if not (1 <= m <= 12):
            raise ValueError
        return y, m
    except Exception:
        raise SystemExit(f"ERROR: invalid BASE_YM: {ym}. expected YYYY-MM")

def add_months(y: int, m: int, delta: int):
    x = (y * 12 + (m - 1)) + delta
    return x // 12, x % 12 + 1

def table_exists(conn, table: str) -> bool:
    return conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?",
        (table,),
    ).fetchone() is not None

def columns(conn, table: str):
    # cid, name, type, notnull, dflt_value, pk
    return {row[1]: row for row in conn.execute(f"PRAGMA table_info({q(table)})").fetchall()}

def first_existing(cols, names):
    for name in names:
        if name in cols:
            return name
    return None

def try_add_column(conn, table, col_sql):
    try:
        conn.execute(f"ALTER TABLE {q(table)} ADD COLUMN {col_sql}")
    except sqlite3.OperationalError as e:
        if "duplicate column" not in str(e).lower():
            raise

def insert_dynamic(conn, table: str, table_cols: dict, payload: dict):
    clean = {k: v for k, v in payload.items() if k in table_cols}
    if not clean:
        raise RuntimeError(f"no insertable columns for {table}")
    col_sql = ", ".join(q(k) for k in clean.keys())
    val_sql = ", ".join("?" for _ in clean)
    conn.execute(
        f"INSERT INTO {q(table)} ({col_sql}) VALUES ({val_sql})",
        list(clean.values()),
    )

base_y, base_m = parse_ym(BASE_YM)
months = [add_months(base_y, base_m, -i) for i in range(5, -1, -1)]

conn = sqlite3.connect(DB_PATH)
conn.row_factory = sqlite3.Row

if not table_exists(conn, "transactions"):
    raise SystemExit("ERROR: transactions table not found")

# Ensure minimal columns required by the income feature exist.
tx_cols = columns(conn, "transactions")
if "tx_type" not in tx_cols:
    print("==> transactions.tx_type missing; adding it as TEXT DEFAULT 'expense'")
    try_add_column(conn, "transactions", "tx_type TEXT NOT NULL DEFAULT 'expense'")
    tx_cols = columns(conn, "transactions")

if table_exists(conn, "category_master"):
    cat_cols = columns(conn, "category_master")
    if "is_income" not in cat_cols:
        print("==> category_master.is_income missing; adding it as INTEGER DEFAULT 0")
        try_add_column(conn, "category_master", "is_income INTEGER NOT NULL DEFAULT 0")
        cat_cols = columns(conn, "category_master")
else:
    cat_cols = {}

# Column aliases. The current app should use the left-side names, but this keeps the seed script tolerant.
date_col = first_existing(tx_cols, ["purchased_at", "transaction_date", "date", "occurred_at", "created_at"])
amount_col = first_existing(tx_cols, ["amount", "price", "total_amount"])
category_col = first_existing(tx_cols, ["screening_category", "category", "category_name"])
merchant_raw_col = first_existing(tx_cols, ["merchant_raw", "raw_merchant", "store_raw"])
merchant_norm_col = first_existing(tx_cols, ["merchant_normalized", "merchant", "merchant_name", "store_name"])
tx_type_col = first_existing(tx_cols, ["tx_type", "transaction_type", "type", "kind"])
status_col = first_existing(tx_cols, ["status"])
memo_col = first_existing(tx_cols, ["memo", "note", "description", "comment"])
source_col = first_existing(tx_cols, ["source"])

missing = []
for label, col in [
    ("date", date_col),
    ("amount", amount_col),
    ("category", category_col),
    ("merchant", merchant_norm_col or merchant_raw_col),
    ("tx_type", tx_type_col),
]:
    if not col:
        missing.append(label)
if missing:
    raise SystemExit(f"ERROR: cannot find required transaction columns: {', '.join(missing)}")

# Category master seeding, if possible.
income_categories = ["給与", "副収入", "その他収入"]
default_expense_categories = ["食費", "日用品", "交通費", "娯楽", "医療", "衣服", "通信費", "光熱費", "家賃", "その他"]

def ensure_category_master():
    if not table_exists(conn, "category_master"):
        return default_expense_categories

    cols = columns(conn, "category_master")
    name_col = first_existing(cols, ["name", "category", "category_name", "label"])
    if not name_col:
        return default_expense_categories

    is_income_col = first_existing(cols, ["is_income"])
    tax_col = first_existing(cols, ["tax_rate", "tax_percent", "rate"])
    created_col = first_existing(cols, ["created_at"])
    updated_col = first_existing(cols, ["updated_at"])

    def exists(name):
        return conn.execute(
            f"SELECT 1 FROM {q('category_master')} WHERE {q(name_col)}=? LIMIT 1",
            (name,),
        ).fetchone() is not None

    def safe_insert(name, is_income):
        if exists(name):
            if is_income_col:
                conn.execute(
                    f"UPDATE {q('category_master')} SET {q(is_income_col)}=? WHERE {q(name_col)}=?",
                    (1 if is_income else 0, name),
                )
            return
        payload = {name_col: name}
        if is_income_col:
            payload[is_income_col] = 1 if is_income else 0
        if tax_col:
            payload[tax_col] = 0 if is_income else (0.08 if name == "食費" else 0.10)
        now = datetime.now().isoformat(timespec="seconds")
        if created_col:
            payload[created_col] = now
        if updated_col:
            payload[updated_col] = now

        # Fill simple required columns when the table has extra NOT NULL fields.
        for col, info in cols.items():
            _, cname, ctype, notnull, dflt, pk = info
            if pk or cname in payload or dflt is not None or not notnull:
                continue
            low = cname.lower()
            if low.startswith("is_") or low.startswith("has_"):
                payload[cname] = 0
            elif "sort" in low or "order" in low or "priority" in low:
                payload[cname] = 0
            elif "color" in low:
                payload[cname] = ""
            elif "created" in low or "updated" in low:
                payload[cname] = now
            else:
                # Unknown required field: skip inserting new categories rather than corrupting assumptions.
                return

        insert_dynamic(conn, "category_master", cols, payload)

    for c in default_expense_categories:
        safe_insert(c, False)
    for c in income_categories:
        safe_insert(c, True)

    rows = conn.execute(
        f"SELECT {q(name_col)} AS name"
        + (f", {q(is_income_col)} AS is_income " if is_income_col else ", 0 AS is_income ")
        + f"FROM {q('category_master')}"
    ).fetchall()
    expense_names = [r["name"] for r in rows if not int(r["is_income"] or 0)]
    return expense_names or default_expense_categories

expense_categories = ensure_category_master()
conn.commit()

def has_expense_cat(name):
    return name in expense_categories

def cat(name):
    if name in expense_categories:
        return name
    if "その他" in expense_categories:
        return "その他"
    return expense_categories[0]

merchant_by_category = {
    "食費": ["スーパーA", "コンビニB", "カフェC", "レストランD", "ベーカリーE"],
    "日用品": ["ドラッグストアA", "ホームセンターB", "100円ショップC"],
    "交通費": ["JR", "地下鉄", "バス", "タクシー"],
    "娯楽": ["映画館A", "書店B", "サブスクC", "ゲームストアD"],
    "医療": ["クリニックA", "薬局B"],
    "衣服": ["ユニクロ", "セレクトショップA"],
    "通信費": ["携帯キャリア", "インターネット回線"],
    "光熱費": ["電力会社", "ガス会社", "水道局"],
    "家賃": ["管理会社"],
    "その他": ["Amazon", "楽天", "雑費"],
}

amount_ranges = {
    "食費": (480, 5200),
    "日用品": (500, 7000),
    "交通費": (180, 3800),
    "娯楽": (900, 12000),
    "医療": (800, 9000),
    "衣服": (1800, 18000),
    "通信費": (3000, 11000),
    "光熱費": (3500, 18000),
    "家賃": (88000, 98000),
    "その他": (700, 15000),
}

def choose_merchant(category, rng):
    names = merchant_by_category.get(category) or merchant_by_category.get("その他")
    return rng.choice(names)

def tax_rate_for(category, tx_type):
    if tx_type == "income":
        return 0.0
    if category == "食費":
        return 0.08
    if category in ("家賃", "交通費"):
        return 0.0
    return 0.10

def build_payload(date_iso, tx_type, category, merchant, amount, memo):
    now = datetime.now().isoformat(timespec="seconds")
    rate = tax_rate_for(category, tx_type)
    tax_excluded = int(round(amount / (1 + rate))) if rate else amount
    tax_amount = int(amount - tax_excluded)

    payload = {}
    if date_col:
        payload[date_col] = date_iso
    if amount_col:
        payload[amount_col] = int(amount)
    if category_col:
        payload[category_col] = category
    if merchant_raw_col:
        payload[merchant_raw_col] = f"{MARKER}{merchant}"
    if merchant_norm_col:
        payload[merchant_norm_col] = merchant
    if tx_type_col:
        payload[tx_type_col] = tx_type
    if status_col:
        payload[status_col] = "user_confirmed"
    if memo_col:
        payload[memo_col] = f"{MARKER} {memo}"
    if source_col:
        payload[source_col] = "dummy_6months"

    for c in ["created_at", "updated_at"]:
        if c in tx_cols:
            payload[c] = now

    for c in ["tax_rate", "tax_percent", "rate"]:
        if c in tx_cols:
            payload[c] = rate
    for c in ["tax_amount", "tax"]:
        if c in tx_cols:
            payload[c] = tax_amount
    for c in ["tax_excluded_amount", "amount_without_tax", "subtotal"]:
        if c in tx_cols:
            payload[c] = tax_excluded
    for c in ["amount_with_tax", "total", "total_amount"]:
        if c in tx_cols:
            payload[c] = int(amount)

    # Fill required columns with conservative defaults if the schema has extra NOT NULL columns.
    for col, info in tx_cols.items():
        _, cname, ctype, notnull, dflt, pk = info
        if pk or cname in payload or dflt is not None or not notnull:
            continue
        low = cname.lower()
        if "created" in low or "updated" in low:
            payload[cname] = now
        elif "amount" in low or "price" in low or "tax" in low:
            payload[cname] = 0
        elif "date" in low or "time" in low or low.endswith("_at"):
            payload[cname] = date_iso
        elif "status" in low:
            payload[cname] = "user_confirmed"
        elif "type" in low or "kind" in low:
            payload[cname] = tx_type
        elif "category" in low:
            payload[cname] = category
        elif "merchant" in low or "store" in low:
            payload[cname] = merchant
        elif "memo" in low or "note" in low or "desc" in low or "comment" in low:
            payload[cname] = f"{MARKER} {memo}"
        elif "source" in low:
            payload[cname] = "dummy_6months"
        elif low.startswith("is_") or low.startswith("has_"):
            payload[cname] = 0
        elif "confidence" in low or "score" in low:
            payload[cname] = 1.0
        elif "currency" in low:
            payload[cname] = "JPY"
        else:
            raise RuntimeError(f"Required column cannot be inferred: transactions.{cname}")

    return payload

def add_tx(rows, y, m, d, tx_type, category, merchant, amount, memo):
    last = calendar.monthrange(y, m)[1]
    d = max(1, min(d, last))
    date_iso = f"{y:04d}-{m:02d}-{d:02d}"
    rows.append(build_payload(date_iso, tx_type, category, merchant, int(amount), memo))

rng = random.Random(SEED)
rows = []

for y, m in months:
    ym = f"{y:04d}-{m:02d}"
    is_base_month = (y == base_y and m == base_m)
    month_last = calendar.monthrange(y, m)[1]
    day_cap = max(1, min(BASE_DAY, month_last)) if is_base_month else month_last

    # Income.
    salary_amount = 285000 + ((m % 3) * 5000) + rng.randint(-3000, 3000)
    add_tx(rows, y, m, min(25, day_cap), "income", "給与", "勤務先", salary_amount, f"{ym} salary")

    if m == 12 and day_cap >= 10:
        add_tx(rows, y, m, 10, "income", "副収入", "勤務先", 120000, f"{ym} winter bonus")

    if day_cap >= 15 and rng.random() < 0.55:
        add_tx(rows, y, m, rng.randint(8, day_cap), "income", "副収入", "副業先", rng.randint(12000, 42000), f"{ym} side income")

    # Fixed expenses.
    if has_expense_cat("家賃") and day_cap >= 27:
        add_tx(rows, y, m, 27, "expense", "家賃", "管理会社", 92000, f"{ym} rent")
    elif has_expense_cat("家賃"):
        add_tx(rows, y, m, day_cap, "expense", "家賃", "管理会社", 92000, f"{ym} rent")

    if day_cap >= 10:
        c = cat("通信費")
        add_tx(rows, y, m, 10, "expense", c, choose_merchant(c, rng), rng.randint(7600, 10500), f"{ym} communication")
    if day_cap >= 15:
        c = cat("光熱費")
        add_tx(rows, y, m, 15, "expense", c, "電力会社", rng.randint(6500, 14500), f"{ym} electricity")
    if day_cap >= 18:
        c = cat("光熱費")
        add_tx(rows, y, m, 18, "expense", c, "ガス会社", rng.randint(3200, 7200), f"{ym} gas")
    if day_cap >= 20:
        c = cat("娯楽")
        add_tx(rows, y, m, 20, "expense", c, "サブスクC", rng.choice([980, 1280, 1980, 2980]), f"{ym} subscription")

    # Variable expenses.
    weighted = (
        ["食費"] * 9
        + ["日用品"] * 3
        + ["交通費"] * 2
        + ["娯楽"] * 3
        + ["医療"] * 1
        + ["衣服"] * 1
        + ["その他"] * 2
    )
    variable_count = rng.randint(20, 28)
    if is_base_month:
        # Current month is partial. Keep the data density realistic up to BASE_DAY.
        variable_count = max(8, int(variable_count * day_cap / month_last))

    for _ in range(variable_count):
        requested = rng.choice(weighted)
        c = cat(requested)
        low, high = amount_ranges.get(c, amount_ranges["その他"])
        amount = rng.randint(low, high)
        # Round some amounts to make the data look less synthetic.
        if amount >= 1000 and rng.random() < 0.65:
            amount = int(round(amount / 10) * 10)
        merchant = choose_merchant(c, rng)
        day = rng.randint(1, day_cap)
        add_tx(rows, y, m, day, "expense", c, merchant, amount, f"{ym} variable")

# Remove previous dummy rows, then insert fresh rows.
if CLEAR_DUMMY == "1":
    clauses = []
    params = []
    if merchant_raw_col:
        clauses.append(f"{q(merchant_raw_col)} LIKE ?")
        params.append(f"{MARKER}%")
    if memo_col:
        clauses.append(f"{q(memo_col)} LIKE ?")
        params.append(f"{MARKER}%")
    if source_col:
        clauses.append(f"{q(source_col)} = ?")
        params.append("dummy_6months")

    if clauses:
        deleted = conn.execute(
            f"DELETE FROM {q('transactions')} WHERE " + " OR ".join(clauses),
            params,
        ).rowcount
        print(f"==> deleted previous dummy rows: {deleted}")
    else:
        print("==> no marker column found; previous dummy rows were not deleted")

for payload in rows:
    insert_dynamic(conn, "transactions", tx_cols, payload)

conn.commit()

print(f"==> inserted dummy rows: {len(rows)}")
print("==> months:", ", ".join(f"{y:04d}-{m:02d}" for y, m in months))

# Output monthly cashflow summary for verification.
print("==> monthly cashflow")
for y, m in months:
    ym = f"{y:04d}-{m:02d}"
    where = f"substr({q(date_col)}, 1, 7)=?"
    total_income = conn.execute(
        f"SELECT COALESCE(SUM({q(amount_col)}),0) FROM {q('transactions')} WHERE {where} AND {q(tx_type_col)}='income'",
        (ym,),
    ).fetchone()[0]
    total_expense = conn.execute(
        f"SELECT COALESCE(SUM({q(amount_col)}),0) FROM {q('transactions')} WHERE {where} AND ({q(tx_type_col)}='expense' OR {q(tx_type_col)} IS NULL)",
        (ym,),
    ).fetchone()[0]
    print(f"  {ym}: income={int(total_income):>7} expense={int(total_expense):>7} balance={int(total_income-total_expense):>8}")

print("==> sample categories")
cat_rows = conn.execute(
    f"SELECT {q(category_col)} AS category, {q(tx_type_col)} AS tx_type, COUNT(*) AS n, SUM({q(amount_col)}) AS amount "
    f"FROM {q('transactions')} "
    f"WHERE substr({q(date_col)}, 1, 7)=? "
    f"GROUP BY {q(category_col)}, {q(tx_type_col)} "
    f"ORDER BY {q(tx_type_col)}, amount DESC",
    (BASE_YM,),
).fetchall()
for r in cat_rows[:20]:
    print(f"  [{r['tx_type']}] {r['category']}: count={r['n']} amount={int(r['amount'] or 0)}")

conn.close()
PY
