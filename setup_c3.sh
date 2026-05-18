#!/usr/bin/env bash
# kakeibo C3: CSV取込 + 集計API + グラフ + 同時画面化.
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_c3.sh

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "C3 setup: CSV取込 + 集計 + グラフ + 同時画面"
echo "============================================================"

# ===========================================================================
# 1. backend/app/csv_import.py (旧inputAutomation.ts の Python 移植)
# ===========================================================================
echo "==> backend/app/csv_import.py"
cat > backend/app/csv_import.py <<'EOF'
"""CSV import logic — Python port of legacy inputAutomation.ts.

CSV input header (固定):
    receipt_id,merchantRaw,items,totalAmount,purchasedAt

items は `|` 区切り (例: "おにぎり|牛乳").
バリデーション3種:
    - missing_merchant: 店舗名空
    - invalid_total_amount: 金額が数値でない / 0以下
    - invalid_purchased_at: YYYY-MM-DD 形式でない

エラー行は needs_review=True で取込まれ, reason にエラーコード.
"""
from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass, field
from datetime import date
from typing import Literal

ValidationErrorCode = Literal[
    "missing_merchant", "invalid_total_amount", "invalid_purchased_at",
]

VALIDATION_MESSAGES: dict[ValidationErrorCode, str] = {
    "missing_merchant": "店舗名を入力してください",
    "invalid_total_amount": "金額は0より大きい値を入力してください",
    "invalid_purchased_at": "日付はYYYY-MM-DD形式で入力してください",
}

EXPECTED_HEADER = "receipt_id,merchantRaw,items,totalAmount,purchasedAt"

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


@dataclass
class CsvRow:
    """1行のCSV取込データ."""
    receipt_id: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None  # parse失敗時 None
    purchased_at: str
    validation_error: ValidationErrorCode | None = None
    validation_message: str | None = None


@dataclass
class CsvParseResult:
    rows: list[CsvRow]
    header_error: str | None = None  # ヘッダ不一致時のメッセージ
    parse_errors: list[str] = field(default_factory=list)


def parse_csv(csv_text: str) -> CsvParseResult:
    """CSVテキストをパースして CsvRow リストを返す.

    ヘッダ不一致は header_error に格納し, rows は空で返す.
    各行のバリデーションは validate_row で別途実施.
    """
    lines = [ln for ln in csv_text.splitlines() if ln.strip()]
    if not lines:
        return CsvParseResult(rows=[])

    header = lines[0].strip()
    if header != EXPECTED_HEADER:
        return CsvParseResult(
            rows=[],
            header_error=f"invalid CSV header. expected: {EXPECTED_HEADER}, got: {header}",
        )

    rows: list[CsvRow] = []
    reader = csv.reader(io.StringIO("\n".join(lines[1:])))
    for raw in reader:
        # 5列必須, 不足分は空文字で埋める
        padded = (raw + [""] * 5)[:5]
        receipt_id, merchant_raw, items_raw, total_raw, purchased_at = padded
        items = [i.strip() for i in items_raw.split("|") if i.strip()] if items_raw else []
        try:
            total = int(total_raw) if total_raw.strip() else None
        except ValueError:
            total = None
        rows.append(CsvRow(
            receipt_id=receipt_id.strip(),
            merchant_raw=merchant_raw.strip(),
            items=items,
            total_amount=total,
            purchased_at=purchased_at.strip(),
        ))

    return CsvParseResult(rows=rows)


def validate_row(row: CsvRow) -> ValidationErrorCode | None:
    """1行のバリデーション. エラー無ければ None."""
    if not row.merchant_raw:
        return "missing_merchant"
    if row.total_amount is None or row.total_amount <= 0:
        return "invalid_total_amount"
    if not _DATE_RE.match(row.purchased_at):
        return "invalid_purchased_at"
    # 日付の有効性を厳密確認 (2026-02-30 等)
    try:
        y, m, d = row.purchased_at.split("-")
        date(int(y), int(m), int(d))
    except ValueError:
        return "invalid_purchased_at"
    return None


def validate_all(rows: list[CsvRow]) -> list[CsvRow]:
    """全行にバリデーション結果を付与."""
    for row in rows:
        err = validate_row(row)
        if err:
            row.validation_error = err
            row.validation_message = VALIDATION_MESSAGES[err]
    return rows
EOF

# ===========================================================================
# 2. backend/app/routers/csv_import.py (API)
# ===========================================================================
echo "==> backend/app/routers/csv_import.py"
cat > backend/app/routers/csv_import.py <<'EOF'
"""CSV import API.

POST /api/csv/preview : CSV をパース + バリデーション結果プレビュー (DB変更なし)
POST /api/csv/commit  : バリデーション通過行をDB保存 (バリデーションエラー行も needs_review=True で保存可)
"""
from __future__ import annotations

from datetime import date as date_type, datetime
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from app.classifier import ReceiptInput, classify_receipt
from app.csv_import import (
    CsvRow, ValidationErrorCode, parse_csv, validate_all, VALIDATION_MESSAGES,
)
from app.database import get_session
from app.models import (
    CategoryMaster, Transaction, UserCategoryOverride, calc_tax_amount,
)

router = APIRouter(prefix="/api/csv", tags=["csv"])

_MAX_BYTES = 5 * 1024 * 1024  # 5MB


class CsvPreviewRow(BaseModel):
    receipt_id: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None
    purchased_at: str
    validation_error: ValidationErrorCode | None = None
    validation_message: str | None = None
    predicted_category: str | None = None
    predicted_needs_review: bool = False


class CsvPreviewResponse(BaseModel):
    total: int
    error_count: int
    rows: list[CsvPreviewRow]
    header_error: str | None = None


class CsvCommitResponse(BaseModel):
    inserted: int
    skipped: int
    error_count: int


def _load_overrides(session: Session) -> dict:
    rows = session.exec(select(UserCategoryOverride)).all()
    return {r.merchant_pattern: r.category for r in rows}


def _tax_rate_for(category: str | None, session: Session) -> int:
    if category is None:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


async def _read_csv(file: UploadFile) -> str:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"too large: {len(data)} bytes")
    try:
        return data.decode("utf-8-sig")  # BOM対応
    except UnicodeDecodeError:
        try:
            return data.decode("cp932")  # Excel保存のCSVはShift-JISが多い
        except UnicodeDecodeError as e:
            raise HTTPException(status_code=400, detail=f"decode failed: {e}") from e


def _classify_csv_row(row: CsvRow, session: Session, overrides: dict):
    """CSV行を分類エンジンに通す. バリデーションエラー時は分類スキップ."""
    if row.validation_error:
        return None
    return classify_receipt(ReceiptInput(
        merchantRaw=row.merchant_raw,
        items=row.items,
        totalAmount=row.total_amount,
        userCategoryOverrides=overrides if overrides else None,
    ))


@router.post("/preview", response_model=CsvPreviewResponse)
async def preview_csv(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    text = await _read_csv(file)
    parsed = parse_csv(text)
    if parsed.header_error:
        return CsvPreviewResponse(
            total=0, error_count=0, rows=[], header_error=parsed.header_error,
        )

    rows = validate_all(parsed.rows)
    overrides = _load_overrides(session)
    out: list[CsvPreviewRow] = []
    err_count = 0
    for row in rows:
        if row.validation_error:
            err_count += 1
            out.append(CsvPreviewRow(
                receipt_id=row.receipt_id, merchant_raw=row.merchant_raw,
                items=row.items, total_amount=row.total_amount,
                purchased_at=row.purchased_at,
                validation_error=row.validation_error,
                validation_message=row.validation_message,
            ))
            continue
        cls = _classify_csv_row(row, session, overrides)
        out.append(CsvPreviewRow(
            receipt_id=row.receipt_id, merchant_raw=row.merchant_raw,
            items=row.items, total_amount=row.total_amount,
            purchased_at=row.purchased_at,
            predicted_category=cls.category if cls else None,
            predicted_needs_review=cls.needsReview if cls else True,
        ))

    return CsvPreviewResponse(total=len(rows), error_count=err_count, rows=out)


@router.post("/commit", response_model=CsvCommitResponse)
async def commit_csv(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    """CSVをパースしてDBに保存. バリデーションエラー行も needs_review=True で保存."""
    text = await _read_csv(file)
    parsed = parse_csv(text)
    if parsed.header_error:
        raise HTTPException(status_code=400, detail=parsed.header_error)

    rows = validate_all(parsed.rows)
    overrides = _load_overrides(session)

    inserted = 0
    err_count = 0
    for row in rows:
        if row.validation_error:
            err_count += 1
            # バリデーションエラー行も needs_review=True で記録
            tx = Transaction(
                receipt_id=row.receipt_id or None,
                merchant_raw=row.merchant_raw or "(空)",
                merchant_normalized=row.merchant_raw or "",
                items_text="|".join(row.items),
                screening_category=None,
                needs_review=True,
                reason=row.validation_error,
                confidence=0.0,
                amount=row.total_amount if (row.total_amount and row.total_amount > 0) else 0,
                tax_amount=0,
                purchased_at=_parse_date_safe(row.purchased_at),
                status="manually_added",
                memo=f"CSV取込エラー: {row.validation_message}",
            )
            session.add(tx)
            inserted += 1
            continue

        cls = classify_receipt(ReceiptInput(
            merchantRaw=row.merchant_raw, items=row.items,
            totalAmount=row.total_amount,
            userCategoryOverrides=overrides if overrides else None,
        ))
        rate = _tax_rate_for(cls.category, session)
        tx = Transaction(
            receipt_id=row.receipt_id or None,
            merchant_raw=row.merchant_raw,
            merchant_normalized=cls.merchantNormalized,
            items_text="|".join(row.items),
            screening_category=cls.category,
            needs_review=cls.needsReview,
            reason=cls.reason,
            confidence=cls.confidence,
            amount=row.total_amount or 0,
            tax_amount=calc_tax_amount(row.total_amount or 0, rate),
            purchased_at=_parse_date_safe(row.purchased_at),
            status="manually_added",
        )
        session.add(tx)
        inserted += 1

    session.commit()
    return CsvCommitResponse(inserted=inserted, skipped=0, error_count=err_count)


def _parse_date_safe(s: str) -> date_type:
    """文字列が無効なら今日の日付."""
    try:
        return date_type.fromisoformat(s)
    except (ValueError, TypeError):
        return date_type.today()
EOF

# ===========================================================================
# 3. backend/app/routers/summary.py (集計API)
# ===========================================================================
echo "==> backend/app/routers/summary.py"
cat > backend/app/routers/summary.py <<'EOF'
"""Summary API for charts.

集計単位:
  - 明細を使っている取引: transaction_items を集計
  - 明細を使っていない取引: transactions.amount / screening_category をそのまま使う

GET /api/summary/category?ym=YYYY-MM
    指定月のカテゴリ別合計 (円グラフ用)

GET /api/summary/monthly?months=6
    過去N月の月次合計 (棒グラフ用)
"""
from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlmodel import Session, select

from app.database import get_session
from app.models import Transaction, TransactionItem

router = APIRouter(prefix="/api/summary", tags=["summary"])


class CategorySliceItem(BaseModel):
    category: str
    amount: int


class CategorySummary(BaseModel):
    ym: str  # YYYY-MM
    total: int
    slices: list[CategorySliceItem]


class MonthlySliceItem(BaseModel):
    ym: str
    total: int


class MonthlySummary(BaseModel):
    months: int
    slices: list[MonthlySliceItem]


def _month_range(ym: str) -> tuple[date, date]:
    """'YYYY-MM' から (月初, 翌月初) を返す."""
    y, m = ym.split("-")
    y_i, m_i = int(y), int(m)
    start = date(y_i, m_i, 1)
    if m_i == 12:
        end = date(y_i + 1, 1, 1)
    else:
        end = date(y_i, m_i + 1, 1)
    return start, end


def _aggregate_by_category(
    session: Session, start: date, end: date,
) -> dict[str, int]:
    """期間内の取引・明細を集計してカテゴリ別合計を返す.

    優先ロジック:
      - transactions.items が空 → transactions.screening_category, transactions.amount を使う
      - transactions.items がある → 明細ごと集計 (未分類明細は除外)
    """
    by_cat: dict[str, int] = defaultdict(int)

    # transactions を期間で絞る
    stmt = select(Transaction).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
    )
    txns = list(session.exec(stmt).all())
    for tx in txns:
        items = tx.items
        if items:
            for item in items:
                if item.category:
                    by_cat[item.category] += item.amount
            # 未分類明細の金額は集計から外れる
        else:
            if tx.screening_category:
                by_cat[tx.screening_category] += tx.amount
            # 未分類取引は集計外
    return dict(by_cat)


@router.get("/category", response_model=CategorySummary)
def category_summary(
    ym: str = Query(..., regex=r"^\d{4}-\d{2}$", description="YYYY-MM"),
    session: Session = Depends(get_session),
) -> CategorySummary:
    start, end = _month_range(ym)
    by_cat = _aggregate_by_category(session, start, end)
    slices = sorted(
        [CategorySliceItem(category=c, amount=a) for c, a in by_cat.items()],
        key=lambda x: -x.amount,
    )
    total = sum(s.amount for s in slices)
    return CategorySummary(ym=ym, total=total, slices=slices)


@router.get("/monthly", response_model=MonthlySummary)
def monthly_summary(
    months: int = Query(6, ge=1, le=24),
    session: Session = Depends(get_session),
) -> MonthlySummary:
    today = date.today()
    slices: list[MonthlySliceItem] = []
    # 古い月から新しい月へ
    y, m = today.year, today.month
    yms: list[str] = []
    for _ in range(months):
        yms.append(f"{y:04d}-{m:02d}")
        m -= 1
        if m == 0:
            m = 12
            y -= 1
    yms.reverse()

    for ym in yms:
        start, end = _month_range(ym)
        by_cat = _aggregate_by_category(session, start, end)
        slices.append(MonthlySliceItem(ym=ym, total=sum(by_cat.values())))

    return MonthlySummary(months=months, slices=slices)
EOF

# ===========================================================================
# 4. backend/app/main.py (router 追加登録)
# ===========================================================================
echo "==> backend/app/main.py"
cat > backend/app/main.py <<'EOF'
"""FastAPI entry point — C3 (CSV + summary)."""
from __future__ import annotations
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .database import create_db_and_tables
from .routers import categories, csv_import, overrides, receipts, summary, transactions


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(title="kakeibo API", version="0.4.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(receipts.router)
app.include_router(transactions.router)
app.include_router(overrides.router)
app.include_router(categories.router)
app.include_router(csv_import.router)
app.include_router(summary.router)

_STATIC_DIR = Path(__file__).resolve().parent / "static"
if _STATIC_DIR.exists():
    app.mount("/", StaticFiles(directory=str(_STATIC_DIR), html=True), name="static")
EOF

# ===========================================================================
# 5. backend/tests/test_csv_import.py
# ===========================================================================
echo "==> backend/tests/test_csv_import.py"
cat > backend/tests/test_csv_import.py <<'EOF'
"""CSV取込ロジックのテスト."""
from __future__ import annotations

from app.csv_import import (
    EXPECTED_HEADER, parse_csv, validate_all, validate_row,
)


def _make_csv(*rows: str) -> str:
    return EXPECTED_HEADER + "\n" + "\n".join(rows)


def test_parse_valid_csv():
    csv = _make_csv(
        "001,セブンイレブン渋谷,おにぎり|牛乳,620,2026-05-17",
        "002,マツモトキヨシ新宿,洗剤,480,2026-05-18",
    )
    result = parse_csv(csv)
    assert result.header_error is None
    assert len(result.rows) == 2
    assert result.rows[0].merchant_raw == "セブンイレブン渋谷"
    assert result.rows[0].items == ["おにぎり", "牛乳"]
    assert result.rows[0].total_amount == 620


def test_invalid_header():
    result = parse_csv("foo,bar,baz\n1,2,3")
    assert result.header_error is not None
    assert "invalid CSV header" in result.header_error


def test_validate_missing_merchant():
    csv = _make_csv(",店舗なし,商品,500,2026-05-17")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "missing_merchant"


def test_validate_invalid_amount():
    csv = _make_csv("001,店,商品,0,2026-05-17")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_total_amount"

    csv = _make_csv("001,店,商品,-100,2026-05-17")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_total_amount"

    csv = _make_csv("001,店,商品,abc,2026-05-17")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_total_amount"


def test_validate_invalid_date():
    csv = _make_csv("001,店,商品,500,2026/05/17")  # スラッシュ区切り
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_purchased_at"

    csv = _make_csv("001,店,商品,500,2026-02-30")  # 2/30 は存在しない
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_purchased_at"


def test_validate_pass():
    csv = _make_csv("001,セブンイレブン,おにぎり,620,2026-05-17")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None


def test_empty_items():
    csv = _make_csv("001,店,,500,2026-05-17")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].items == []
    assert rows[0].validation_error is None
EOF

# ===========================================================================
# 6. backend/tests/test_summary.py
# ===========================================================================
echo "==> backend/tests/test_summary.py"
cat > backend/tests/test_summary.py <<'EOF'
"""Summary API のテスト."""
from __future__ import annotations

import pytest
from fastapi.testclient import TestClient


@pytest.fixture
def client(monkeypatch, tmp_path):
    db_file = tmp_path / "test.db"
    monkeypatch.setenv("KAKEIBO_DB_PATH", str(db_file))
    import importlib
    from app import database, main
    importlib.reload(database)
    importlib.reload(main)
    database.create_db_and_tables()
    with TestClient(main.app) as c:
        yield c


def _create_tx(client, **kw):
    base = {
        "merchant_raw": "T", "merchant_normalized": "T", "items_text": "",
        "screening_category": None, "needs_review": False, "reason": "",
        "confidence": 0, "amount": 0, "purchased_at": "2026-05-17",
        "status": "manually_added",
    }
    base.update(kw)
    return client.post("/api/transactions", json=base).json()


def test_category_summary_uses_header_when_no_items(client):
    _create_tx(client, amount=1000, screening_category="食費", purchased_at="2026-05-10")
    _create_tx(client, amount=500, screening_category="酒類", purchased_at="2026-05-12")
    _create_tx(client, amount=300, screening_category="食費", purchased_at="2026-05-20")

    r = client.get("/api/summary/category?ym=2026-05")
    data = r.json()
    by = {s["category"]: s["amount"] for s in data["slices"]}
    assert by["食費"] == 1300
    assert by["酒類"] == 500
    assert data["total"] == 1800


def test_category_summary_uses_items_when_present(client):
    tx = _create_tx(client, amount=0)
    tx_id = tx["id"]
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "A", "amount": 100, "category": "食費"})
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "B", "amount": 200, "category": "酒類"})

    r = client.get("/api/summary/category?ym=2026-05")
    by = {s["category"]: s["amount"] for s in r.json()["slices"]}
    assert by["食費"] == 100
    assert by["酒類"] == 200


def test_category_summary_excludes_other_months(client):
    _create_tx(client, amount=500, screening_category="食費", purchased_at="2026-04-15")
    _create_tx(client, amount=1000, screening_category="食費", purchased_at="2026-05-15")

    r = client.get("/api/summary/category?ym=2026-05")
    by = {s["category"]: s["amount"] for s in r.json()["slices"]}
    assert by["食費"] == 1000  # 4月分は除外


def test_monthly_summary(client):
    _create_tx(client, amount=1000, screening_category="食費", purchased_at="2026-05-10")
    _create_tx(client, amount=2000, screening_category="食費", purchased_at="2026-04-10")

    r = client.get("/api/summary/monthly?months=6")
    data = r.json()
    assert data["months"] == 6
    assert len(data["slices"]) == 6
    by_ym = {s["ym"]: s["total"] for s in data["slices"]}
    assert by_ym.get("2026-05") == 1000
    assert by_ym.get("2026-04") == 2000
EOF

# ===========================================================================
# 7. frontend/package.json (recharts 追加)
# ===========================================================================
echo "==> frontend/package.json (recharts 追加)"
cd frontend
if ! grep -q '"recharts"' package.json; then
  # node_modulesがなければ install
  if [ ! -d node_modules ]; then
    npm install 2>&1 | tail -3
  fi
  npm install recharts@^2.13.0 2>&1 | tail -3
fi
cd "$REPO"

# ===========================================================================
# 8. frontend/src/api.ts (CSV + summary 追加)
# ===========================================================================
echo "==> frontend/src/api.ts"
cat > frontend/src/api.ts <<'EOF'
import type {
  CategoryMaster, ReceiptUploadResponse, Transaction, TransactionItem,
  UserCategoryOverride,
} from "./types";

const BASE = "/api";

async function handle<T>(r: Response): Promise<T> {
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
  return r.json() as Promise<T>;
}

// ===== Receipts =====
export async function uploadReceipt(file: File): Promise<ReceiptUploadResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/receipts/upload`, { method: "POST", body: fd });
  return handle<ReceiptUploadResponse>(r);
}

// ===== Transactions =====
export interface ListParams {
  status?: string;
  needs_review?: boolean;
  merchant?: string;
  start_date?: string;
  end_date?: string;
  limit?: number;
  offset?: number;
}

export async function listTransactions(p: ListParams = {}): Promise<Transaction[]> {
  const sp = new URLSearchParams();
  Object.entries(p).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== "") sp.set(k, String(v));
  });
  const q = sp.toString() ? `?${sp.toString()}` : "";
  const r = await fetch(`${BASE}/transactions${q}`);
  return handle<Transaction[]>(r);
}

export async function getTransaction(id: number): Promise<Transaction> {
  return handle<Transaction>(await fetch(`${BASE}/transactions/${id}`));
}

export async function updateTransaction(id: number, patch: Partial<Transaction>): Promise<Transaction> {
  const r = await fetch(`${BASE}/transactions/${id}`, {
    method: "PATCH", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  return handle<Transaction>(r);
}

export async function deleteTransaction(id: number): Promise<void> {
  const r = await fetch(`${BASE}/transactions/${id}`, { method: "DELETE" });
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
}

// ===== Overrides =====
export async function listOverrides(): Promise<UserCategoryOverride[]> {
  return handle<UserCategoryOverride[]>(await fetch(`${BASE}/overrides`));
}

export async function createOverride(merchant_pattern: string, category: string): Promise<UserCategoryOverride> {
  const r = await fetch(`${BASE}/overrides`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ merchant_pattern, category }),
  });
  return handle<UserCategoryOverride>(r);
}

// ===== Categories =====
export async function listCategories(): Promise<CategoryMaster[]> {
  return handle<CategoryMaster[]>(await fetch(`${BASE}/categories`));
}

// ===== Items =====
export async function createItem(
  txId: number, item: { name: string; amount: number; category: string | null; sort_order?: number }
): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...item, sort_order: item.sort_order ?? 0 }),
  });
  return handle<TransactionItem>(r);
}

export async function updateItem(txId: number, itemId: number, patch: Partial<TransactionItem>): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, {
    method: "PATCH", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  return handle<TransactionItem>(r);
}

export async function deleteItem(txId: number, itemId: number): Promise<void> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, { method: "DELETE" });
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
}

// ===== CSV import =====
export interface CsvPreviewRow {
  receipt_id: string;
  merchant_raw: string;
  items: string[];
  total_amount: number | null;
  purchased_at: string;
  validation_error: string | null;
  validation_message: string | null;
  predicted_category: string | null;
  predicted_needs_review: boolean;
}

export interface CsvPreviewResponse {
  total: number;
  error_count: number;
  rows: CsvPreviewRow[];
  header_error: string | null;
}

export interface CsvCommitResponse {
  inserted: number;
  skipped: number;
  error_count: number;
}

export async function previewCsv(file: File): Promise<CsvPreviewResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/csv/preview`, { method: "POST", body: fd });
  return handle<CsvPreviewResponse>(r);
}

export async function commitCsv(file: File): Promise<CsvCommitResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/csv/commit`, { method: "POST", body: fd });
  return handle<CsvCommitResponse>(r);
}

// ===== Summary =====
export interface CategorySummary {
  ym: string;
  total: number;
  slices: { category: string; amount: number }[];
}

export interface MonthlySummary {
  months: number;
  slices: { ym: string; total: number }[];
}

export async function categorySummary(ym: string): Promise<CategorySummary> {
  return handle<CategorySummary>(await fetch(`${BASE}/summary/category?ym=${ym}`));
}

export async function monthlySummary(months = 6): Promise<MonthlySummary> {
  return handle<MonthlySummary>(await fetch(`${BASE}/summary/monthly?months=${months}`));
}
EOF

# ===========================================================================
# 9. frontend/src/components/CsvImportCard.tsx
# ===========================================================================
echo "==> frontend/src/components/CsvImportCard.tsx"
cat > frontend/src/components/CsvImportCard.tsx <<'EOF'
import { useState } from "react";
import { previewCsv, commitCsv } from "../api";
import type { CsvPreviewResponse } from "../api";

interface Props {
  onImported: () => void;
}

export function CsvImportCard({ onImported }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<CsvPreviewResponse | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [importResult, setImportResult] = useState<string | null>(null);

  async function handlePreview() {
    if (!file) { setError("CSV未選択"); return; }
    setError(null); setImportResult(null); setBusy(true);
    try {
      const r = await previewCsv(file);
      setPreview(r);
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  async function handleCommit() {
    if (!file) return;
    if (!confirm(`${preview?.total ?? 0}件を取り込みますか?`)) return;
    setBusy(true);
    try {
      const r = await commitCsv(file);
      setImportResult(`取込完了: ${r.inserted}件 (うちエラー${r.error_count}件)`);
      setPreview(null);
      setFile(null);
      onImported();
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>CSV 一括取込</h2>
      <p className="hint">
        ヘッダ固定: <code>receipt_id,merchantRaw,items,totalAmount,purchasedAt</code><br />
        items は <code>|</code> 区切り (例: <code>おにぎり|牛乳</code>)
      </p>
      <input type="file" accept=".csv,text/csv" onChange={(e) => {
        setFile(e.target.files?.[0] || null);
        setPreview(null);
        setImportResult(null);
      }} />
      <button onClick={handlePreview} disabled={busy || !file}>
        プレビュー
      </button>
      {error && <p className="err">{error}</p>}
      {importResult && <p style={{ color: "#1a7f37" }}>{importResult}</p>}

      {preview?.header_error && (
        <p className="err">ヘッダエラー: {preview.header_error}</p>
      )}

      {preview && !preview.header_error && (
        <div className="csv-preview">
          <p>
            総件数: <b>{preview.total}</b> /
            エラー: <b className={preview.error_count > 0 ? "err" : ""}>{preview.error_count}</b>
          </p>
          <div style={{ maxHeight: 300, overflowY: "auto" }}>
            <table className="tx-table" style={{ fontSize: "0.82em" }}>
              <thead>
                <tr>
                  <th>店舗</th>
                  <th>明細</th>
                  <th style={{ textAlign: "right" }}>金額</th>
                  <th>日付</th>
                  <th>予測カテゴリ</th>
                  <th>状態</th>
                </tr>
              </thead>
              <tbody>
                {preview.rows.map((row, i) => (
                  <tr key={i} className={row.validation_error ? "needs-review" : ""}>
                    <td>{row.merchant_raw || "(空)"}</td>
                    <td>{row.items.join("|")}</td>
                    <td style={{ textAlign: "right" }}>
                      {row.total_amount?.toLocaleString() ?? "-"}
                    </td>
                    <td>{row.purchased_at}</td>
                    <td>{row.predicted_category || "(未分類)"}</td>
                    <td>
                      {row.validation_error
                        ? <span className="badge review">{row.validation_message}</span>
                        : row.predicted_needs_review
                        ? <span className="badge review">要確認</span>
                        : <span className="badge ok">OK</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="actions" style={{ marginTop: 12 }}>
            <button onClick={handleCommit} disabled={busy}>
              {preview.error_count > 0
                ? `取込実行 (エラー行も needs_review で取込)`
                : "取込実行"}
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
EOF

# ===========================================================================
# 10. frontend/src/components/UploadView.tsx (左右2カラム化)
# ===========================================================================
echo "==> frontend/src/components/UploadView.tsx (画像+CSV 同時画面)"
cat > frontend/src/components/UploadView.tsx <<'EOF'
import { useState } from "react";
import { uploadReceipt } from "../api";
import type { ReceiptUploadResponse } from "../types";
import { CsvImportCard } from "./CsvImportCard";

interface Props { onUploaded: () => void; }

export function UploadView({ onUploaded }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<ReceiptUploadResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    if (!file) { setError("ファイル未選択"); return; }
    setError(null); setBusy(true);
    try {
      const r = await uploadReceipt(file);
      setResult(r);
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="two-col">
      {/* 左カラム: 画像アップロード */}
      <div className="card">
        <h2>レシート画像アップロード</h2>
        <p className="hint">OCR + 分類 + DB保存まで自動.</p>
        <input type="file" accept="image/*" onChange={(e) => {
          setFile(e.target.files?.[0] || null); setResult(null);
        }} />
        <button onClick={handleSubmit} disabled={busy || !file}>
          {busy ? "処理中..." : "送信"}
        </button>
        {error && <p className="err">{error}</p>}
        {result && (
          <div className="result">
            <h3>保存完了 (ID: {result.transaction_id})</h3>
            <table>
              <tbody>
                <tr><th>店舗</th><td>{result.merchant_raw || "(空)"}</td></tr>
                <tr><th>合計(税込)</th><td>{result.total_amount?.toLocaleString() || "-"}円</td></tr>
                <tr><th>税額</th><td>{result.tax_amount.toLocaleString()}円</td></tr>
                <tr><th>カテゴリ</th><td>{result.classification.category || "(未分類)"}</td></tr>
              </tbody>
            </table>
            <button onClick={onUploaded}>一覧で確認・編集</button>
          </div>
        )}
      </div>

      {/* 右カラム: CSV取込 */}
      <CsvImportCard onImported={onUploaded} />
    </div>
  );
}
EOF

# ===========================================================================
# 11. frontend/src/components/GraphView.tsx (円グラフ + 棒グラフ)
# ===========================================================================
echo "==> frontend/src/components/GraphView.tsx"
cat > frontend/src/components/GraphView.tsx <<'EOF'
import { useEffect, useMemo, useState } from "react";
import {
  Bar, BarChart, Cell, Legend, Pie, PieChart, ResponsiveContainer,
  Tooltip, XAxis, YAxis,
} from "recharts";
import { categorySummary, monthlySummary } from "../api";
import type { CategorySummary, MonthlySummary } from "../api";

// 9カテゴリ分の色
const COLORS: Record<string, string> = {
  "食費": "#22c55e",
  "酒類": "#f59e0b",
  "外食": "#ef4444",
  "日用品": "#3b82f6",
  "交通費": "#8b5cf6",
  "医療費": "#ec4899",
  "娯楽費": "#06b6d4",
  "衣料費": "#f97316",
  "その他": "#94a3b8",
};

function currentYm(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

export function GraphView() {
  const [ym, setYm] = useState<string>(currentYm());
  const [cat, setCat] = useState<CategorySummary | null>(null);
  const [monthly, setMonthly] = useState<MonthlySummary | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    Promise.all([categorySummary(ym), monthlySummary(6)])
      .then(([c, m]) => { setCat(c); setMonthly(m); })
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }, [ym]);

  const pieData = useMemo(() => {
    if (!cat) return [];
    return cat.slices.map((s) => ({
      name: s.category, value: s.amount,
    }));
  }, [cat]);

  return (
    <div>
      <div className="card">
        <h2>カテゴリ別支出 ({ym})</h2>
        <div style={{ marginBottom: 12 }}>
          <label>表示月: </label>
          <input type="month" value={ym} onChange={(e) => setYm(e.target.value)} />
        </div>
        {error && <p className="err">{error}</p>}
        {loading && <p>読込中...</p>}
        {cat && !loading && (
          <>
            <p>合計: <b>{cat.total.toLocaleString()}円</b></p>
            {pieData.length === 0 ? (
              <p className="hint">この月にデータがありません.</p>
            ) : (
              <ResponsiveContainer width="100%" height={320}>
                <PieChart>
                  <Pie
                    data={pieData}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    outerRadius={110}
                    label={(entry: { name: string; value: number; percent: number }) =>
                      `${entry.name} ${entry.value.toLocaleString()}円 (${(entry.percent * 100).toFixed(1)}%)`
                    }
                  >
                    {pieData.map((entry) => (
                      <Cell key={entry.name} fill={COLORS[entry.name] ?? "#94a3b8"} />
                    ))}
                  </Pie>
                  <Tooltip
                    formatter={(value: number) => `${value.toLocaleString()}円`}
                  />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            )}
          </>
        )}
      </div>

      <div className="card">
        <h2>月次合計推移 (過去6ヶ月)</h2>
        {monthly && monthly.slices.length > 0 && (
          <ResponsiveContainer width="100%" height={280}>
            <BarChart data={monthly.slices}>
              <XAxis dataKey="ym" />
              <YAxis tickFormatter={(v: number) => v.toLocaleString()} />
              <Tooltip formatter={(value: number) => `${value.toLocaleString()}円`} />
              <Bar dataKey="total" fill="#1f6feb" />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>
    </div>
  );
}
EOF

# ===========================================================================
# 12. frontend/src/App.tsx (グラフタブ追加)
# ===========================================================================
echo "==> frontend/src/App.tsx (graph タブ追加)"
cat > frontend/src/App.tsx <<'EOF'
import { useState } from "react";
import "./App.css";
import { UploadView } from "./components/UploadView";
import { ListView } from "./components/ListView";
import { GraphView } from "./components/GraphView";

type Tab = "upload" | "list" | "graph";

export default function App() {
  const [tab, setTab] = useState<Tab>("upload");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="app">
      <header className="app-header">
        <h1>家計簿</h1>
        <nav className="tabs">
          <button className={tab === "upload" ? "active" : ""}
                  onClick={() => setTab("upload")}>取込</button>
          <button className={tab === "list" ? "active" : ""}
                  onClick={() => setTab("list")}>一覧</button>
          <button className={tab === "graph" ? "active" : ""}
                  onClick={() => setTab("graph")}>グラフ</button>
        </nav>
      </header>
      <main>
        {tab === "upload" && (
          <UploadView onUploaded={() => {
            setRefreshKey((k) => k + 1);
            setTab("list");
          }} />
        )}
        {tab === "list" && <ListView refreshKey={refreshKey} />}
        {tab === "graph" && <GraphView />}
      </main>
    </div>
  );
}
EOF

# ===========================================================================
# 13. frontend/src/App.css (two-col + csv-preview スタイル追加)
# ===========================================================================
echo "==> frontend/src/App.css (2カラム + CSVプレビュー)"
if ! grep -q "two-col" frontend/src/App.css; then
  cat >> frontend/src/App.css <<'EOF'

.two-col {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
}
.two-col > .card { margin: 0; }
@media (max-width: 720px) {
  .two-col { grid-template-columns: 1fr; }
}
.csv-preview { margin-top: 16px; padding-top: 16px; border-top: 1px solid #eee; }
.csv-preview code { background: #f6f8fa; padding: 2px 4px; border-radius: 3px; font-size: 0.9em; }
.app { max-width: 1100px; }
EOF
fi

# ===========================================================================
# 14. テスト + 起動
# ===========================================================================
echo ""
echo "==> backend pytest"
cd backend && uv run pytest -v 2>&1 | tail -40
cd "$REPO"

echo ""
echo "==> restart servers"
pkill -f uvicorn 2>/dev/null || true
pkill -f vite 2>/dev/null || true
sleep 2
cd backend
nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &
sleep 4
cd "$REPO"
cd frontend
nohup npm run dev > /tmp/vite.log 2>&1 &
sleep 5
cd "$REPO"

echo ""
echo "==> backend health"
curl -s http://localhost:8000/api/health && echo

echo ""
echo "==> 集計API動作確認 (今月)"
YM=$(date +%Y-%m)
curl -s "http://localhost:8000/api/summary/category?ym=$YM" | python3 -m json.tool

echo ""
echo "==> 月次API動作確認"
curl -s "http://localhost:8000/api/summary/monthly?months=6" | python3 -m json.tool | head -30

cat <<EOM

============================================================
C3 セットアップ完了.

新機能:
  - CSV一括取込 (プレビュー → 確定実行)
  - 月次カテゴリ集計API
  - 円グラフ (今月カテゴリ別支出)
  - 棒グラフ (過去6ヶ月の月次合計)
  - 取込タブ: 画像アップロード + CSV取込 を左右2カラム同時表示
  - グラフタブ新設

CSVサンプル (これをコピーして hoge.csv として保存→ブラウザでアップロード):
receipt_id,merchantRaw,items,totalAmount,purchasedAt
001,セブンイレブン渋谷,おにぎり|牛乳,620,2026-05-15
002,マツモトキヨシ新宿,洗剤|シャンプー,980,2026-05-16
003,ENEOS,ガソリン,5000,2026-05-17
004,Amazon.co.jp,イヤホン,3000,2026-05-18

確認: VS Code PORTS → 5173 → 🌐
  - 「取込」タブ: 画像とCSVが横並び
  - 「グラフ」タブ: 円グラフ + 月次棒グラフ
============================================================
EOM
