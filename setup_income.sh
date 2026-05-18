#!/usr/bin/env bash
# 収入機能 + 前月比較 一括追加.
#
# 変更:
#   - DB: transactions.tx_type (expense|income), category_master.is_income
#   - 収入カテゴリ3種を初期データに追加 (給与/副収入/その他収入)
#   - 集計API: 収支サマリー + 前月比較
#   - UI: 編集モーダルに収入/支出トグル, グラフタブに収支カード+前月比カード
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_income.sh

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "収入機能 + 前月比較"
echo "============================================================"

# ===========================================================================
# 1. backend/app/models.py に tx_type 列 + is_income 列追加
# ===========================================================================
echo "==> backend/app/models.py"
cat > backend/app/models.py <<'EOF'
"""SQLModel models — with income/expense support."""
from __future__ import annotations
from datetime import date, datetime
from typing import Optional, Literal

from sqlmodel import Field, SQLModel

TxStatus = Literal["auto_saved", "user_confirmed", "manually_added"]
TxType = Literal["expense", "income"]


class TransactionBase(SQLModel):
    receipt_id: Optional[str] = None
    merchant_raw: str
    merchant_normalized: str
    items_text: str = ""
    screening_category: Optional[str] = None
    needs_review: bool = False
    reason: str = ""
    confidence: float = 0.0
    amount: int
    tax_amount: int = 0
    tx_type: str = Field(default="expense")  # "expense" or "income"
    purchased_at: date
    memo: Optional[str] = None
    receipt_image_id: Optional[int] = Field(default=None, foreign_key="receipts.id")
    status: str = Field(default="manually_added")
    ocr_raw_text: Optional[str] = None


class Transaction(TransactionBase, table=True):
    __tablename__ = "transactions"
    id: Optional[int] = Field(default=None, primary_key=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class TransactionItem(SQLModel, table=True):
    __tablename__ = "transaction_items"
    id: Optional[int] = Field(default=None, primary_key=True)
    transaction_id: int = Field(foreign_key="transactions.id", index=True)
    name: str
    amount: int = 0
    tax_amount: int = 0
    category: Optional[str] = None
    sort_order: int = 0


class TransactionItemBase(SQLModel):
    name: str
    amount: int = 0
    category: Optional[str] = None
    sort_order: int = 0


class TransactionItemCreate(TransactionItemBase):
    pass


class TransactionItemRead(TransactionItemBase):
    id: int
    transaction_id: int
    tax_amount: int


class TransactionItemUpdate(SQLModel):
    name: Optional[str] = None
    amount: Optional[int] = None
    category: Optional[str] = None
    sort_order: Optional[int] = None


class TransactionCreate(TransactionBase):
    pass


class TransactionReadWithItems(TransactionBase):
    id: int
    created_at: datetime
    updated_at: datetime
    items: list = []


class TransactionRead(TransactionBase):
    id: int
    created_at: datetime
    updated_at: datetime


class TransactionUpdate(SQLModel):
    merchant_raw: Optional[str] = None
    merchant_normalized: Optional[str] = None
    items_text: Optional[str] = None
    screening_category: Optional[str] = None
    needs_review: Optional[bool] = None
    reason: Optional[str] = None
    confidence: Optional[float] = None
    amount: Optional[int] = None
    tax_amount: Optional[int] = None
    tx_type: Optional[str] = None
    purchased_at: Optional[date] = None
    memo: Optional[str] = None
    status: Optional[str] = None


class Receipt(SQLModel, table=True):
    __tablename__ = "receipts"
    id: Optional[int] = Field(default=None, primary_key=True)
    filename: str
    ocr_text: Optional[str] = None
    status: str = "pending"
    created_at: datetime = Field(default_factory=datetime.utcnow)


class UserCategoryOverride(SQLModel, table=True):
    __tablename__ = "user_category_overrides"
    id: Optional[int] = Field(default=None, primary_key=True)
    merchant_pattern: str = Field(unique=True)
    category: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class UserCategoryOverrideCreate(SQLModel):
    merchant_pattern: str
    category: str


class UserCategoryOverrideRead(SQLModel):
    id: int
    merchant_pattern: str
    category: str
    created_at: datetime


class CategoryMaster(SQLModel, table=True):
    __tablename__ = "category_master"
    name: str = Field(primary_key=True)
    description: str = ""
    tax_rate: int = 10
    sort_order: int = 0
    is_income: bool = False  # True なら収入カテゴリ


class CategoryMasterRead(SQLModel):
    name: str
    description: str
    tax_rate: int
    sort_order: int
    is_income: bool


def calc_tax_amount(amount_incl_tax: int, tax_rate: int) -> int:
    if amount_incl_tax <= 0 or tax_rate <= 0:
        return 0
    return round(amount_incl_tax * tax_rate / (100 + tax_rate))


def derive_header_category_from_items(items):
    if not items:
        return None
    by_category = {}
    for item in items:
        if item.category:
            by_category[item.category] = by_category.get(item.category, 0) + item.amount
    if not by_category:
        return None
    return max(by_category.items(), key=lambda x: x[1])[0]


def calc_header_totals_from_items(items, tax_rate_lookup):
    total_amount = 0
    total_tax = 0
    for item in items:
        total_amount += item.amount
        rate = tax_rate_lookup(item.category)
        total_tax += calc_tax_amount(item.amount, rate)
    return total_amount, total_tax
EOF

# ===========================================================================
# 2. backend/app/database.py に収入カテゴリ追加
# ===========================================================================
echo "==> backend/app/database.py (収入カテゴリ追加)"
cat > backend/app/database.py <<'EOF'
"""SQLite + SQLModel database wiring with seeding."""
from __future__ import annotations
import os
from collections.abc import Generator
from pathlib import Path
from sqlmodel import Session, SQLModel, create_engine, select

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_DB_PATH = _BACKEND_ROOT / "data.db"
DB_PATH = os.getenv("KAKEIBO_DB_PATH", str(_DEFAULT_DB_PATH))
DB_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(DB_URL, echo=False, connect_args={"check_same_thread": False})

# (name, desc, tax_rate, sort_order, is_income)
_INITIAL_CATEGORIES = [
    ("食費", "スーパー, コンビニ, 弁当, 食品", 8, 1, False),
    ("酒類", "ビール, ワイン, 日本酒, チューハイ", 10, 2, False),
    ("外食", "レストラン, カフェ, 居酒屋", 10, 3, False),
    ("日用品", "ドラッグストア, 洗剤, トイレ, キッチン", 10, 4, False),
    ("交通費", "電車, バス, タクシー, ガソリン, 駐車場", 10, 5, False),
    ("医療費", "病院, 薬局, 医薬品, 診察", 10, 6, False),
    ("娯楽費", "書店, 映画, ゲーム, 趣味, レジャー", 10, 7, False),
    ("衣料費", "アパレル, 靴, ファッション, クリーニング", 10, 8, False),
    ("その他", "判断できないもの", 10, 9, False),
    # 収入カテゴリ
    ("給与", "本業の給与収入", 0, 101, True),
    ("副収入", "副業, ボーナス, 副業収入", 0, 102, True),
    ("その他収入", "還付金, 贈与, 投資収益等", 0, 103, True),
]


def create_db_and_tables() -> None:
    from . import models  # noqa: F401
    SQLModel.metadata.create_all(engine)
    _seed_categories()


def _seed_categories() -> None:
    from .models import CategoryMaster
    with Session(engine) as session:
        existing = session.exec(select(CategoryMaster)).first()
        if existing is not None:
            # 既存DB に収入カテゴリが無ければ追加
            existing_names = {c.name for c in session.exec(select(CategoryMaster)).all()}
            for name, desc, rate, order, is_income in _INITIAL_CATEGORIES:
                if name not in existing_names:
                    session.add(CategoryMaster(
                        name=name, description=desc, tax_rate=rate,
                        sort_order=order, is_income=is_income,
                    ))
            session.commit()
            return
        for name, desc, rate, order, is_income in _INITIAL_CATEGORIES:
            session.add(CategoryMaster(
                name=name, description=desc, tax_rate=rate,
                sort_order=order, is_income=is_income,
            ))
        session.commit()


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
EOF

# ===========================================================================
# 3. backend/app/routers/summary.py に収支 + 前月比較APIを追加
# ===========================================================================
echo "==> backend/app/routers/summary.py (収支 + 前月比)"
cat > backend/app/routers/summary.py <<'EOF'
"""Summary API — cashflow + monthly comparison."""
from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlmodel import Session, select

from app.database import get_session
from app.models import CategoryMaster, Transaction, TransactionItem

router = APIRouter(prefix="/api/summary", tags=["summary"])


# ===== Models =====

class CategorySliceItem(BaseModel):
    category: str
    amount: int


class CategorySummary(BaseModel):
    ym: str
    total: int
    slices: list[CategorySliceItem]


class MonthlySliceItem(BaseModel):
    ym: str
    total: int


class MonthlySummary(BaseModel):
    months: int
    slices: list[MonthlySliceItem]


class MonthlyByCategoryRow(BaseModel):
    ym: str
    by_category: dict[str, int]
    total: int


class MonthlyByCategoryResponse(BaseModel):
    months: int
    categories: list[str]
    rows: list[MonthlyByCategoryRow]


class DailyCumulativePoint(BaseModel):
    date: str
    cumulative: int


class DailyCumulativeResponse(BaseModel):
    ym: str
    points: list[DailyCumulativePoint]
    total: int


class TopTransactionItem(BaseModel):
    id: int
    purchased_at: str
    merchant: str
    category: str | None
    amount: int


class TopTransactionsResponse(BaseModel):
    ym: str
    limit: int
    items: list[TopTransactionItem]


class CashflowSummary(BaseModel):
    ym: str
    income: int
    expense: int
    balance: int  # income - expense


class CategoryDiff(BaseModel):
    category: str
    current: int
    previous: int
    diff: int  # current - previous
    ratio: float | None  # (current - previous) / previous (previous>0 のみ)


class MonthCompareResponse(BaseModel):
    current_ym: str
    previous_ym: str
    diffs: list[CategoryDiff]


# ===== Helpers =====

CATEGORY_ORDER = [
    "食費", "酒類", "外食", "日用品",
    "交通費", "医療費", "娯楽費", "衣料費", "その他",
]


def _month_range(ym: str) -> tuple[date, date]:
    y, m = ym.split("-")
    y_i, m_i = int(y), int(m)
    start = date(y_i, m_i, 1)
    if m_i == 12:
        end = date(y_i + 1, 1, 1)
    else:
        end = date(y_i, m_i + 1, 1)
    return start, end


def _previous_ym(ym: str) -> str:
    y, m = ym.split("-")
    y_i, m_i = int(y), int(m)
    m_i -= 1
    if m_i == 0:
        m_i = 12
        y_i -= 1
    return f"{y_i:04d}-{m_i:02d}"


def _generate_yms(months: int) -> list[str]:
    today = date.today()
    y, m = today.year, today.month
    yms: list[str] = []
    for _ in range(months):
        yms.append(f"{y:04d}-{m:02d}")
        m -= 1
        if m == 0:
            m = 12
            y -= 1
    yms.reverse()
    return yms


def _aggregate_by_category(
    session: Session, start: date, end: date, tx_type: str = "expense",
) -> dict[str, int]:
    """期間内のカテゴリ別合計 (デフォルトは支出のみ)."""
    by_cat: dict[str, int] = defaultdict(int)
    tx_stmt = select(
        Transaction.id, Transaction.screening_category, Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
        Transaction.tx_type == tx_type,
    )
    tx_rows = list(session.exec(tx_stmt).all())

    items_by_tx: dict[int, list[TransactionItem]] = defaultdict(list)
    if tx_rows:
        tx_ids = [row[0] for row in tx_rows]
        item_stmt = select(TransactionItem).where(
            TransactionItem.transaction_id.in_(tx_ids)  # type: ignore
        )
        for item in session.exec(item_stmt).all():
            items_by_tx[item.transaction_id].append(item)

    for tx_id, screening_category, amount in tx_rows:
        items = items_by_tx.get(tx_id, [])
        if items:
            for item in items:
                if item.category:
                    by_cat[item.category] += item.amount
        else:
            if screening_category:
                by_cat[screening_category] += amount
    return dict(by_cat)


def _sum_by_type(session: Session, start: date, end: date, tx_type: str) -> int:
    """期間内の取引合計 (収入 or 支出)."""
    stmt = select(Transaction.amount).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
        Transaction.tx_type == tx_type,
    )
    return sum(row for row in session.exec(stmt).all())


# ===== Endpoints =====

@router.get("/category", response_model=CategorySummary)
def category_summary(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> CategorySummary:
    start, end = _month_range(ym)
    by_cat = _aggregate_by_category(session, start, end, "expense")
    slices = sorted(
        [CategorySliceItem(category=c, amount=a) for c, a in by_cat.items()],
        key=lambda x: -x.amount,
    )
    return CategorySummary(ym=ym, total=sum(s.amount for s in slices), slices=slices)


@router.get("/monthly", response_model=MonthlySummary)
def monthly_summary(
    months: int = Query(6, ge=1, le=24),
    session: Session = Depends(get_session),
) -> MonthlySummary:
    yms = _generate_yms(months)
    slices: list[MonthlySliceItem] = []
    for ym in yms:
        start, end = _month_range(ym)
        by_cat = _aggregate_by_category(session, start, end, "expense")
        slices.append(MonthlySliceItem(ym=ym, total=sum(by_cat.values())))
    return MonthlySummary(months=months, slices=slices)


@router.get("/monthly_by_category", response_model=MonthlyByCategoryResponse)
def monthly_by_category(
    months: int = Query(6, ge=1, le=24),
    session: Session = Depends(get_session),
) -> MonthlyByCategoryResponse:
    yms = _generate_yms(months)
    rows: list[MonthlyByCategoryRow] = []
    for ym in yms:
        start, end = _month_range(ym)
        by_cat = _aggregate_by_category(session, start, end, "expense")
        rows.append(MonthlyByCategoryRow(
            ym=ym, by_category=by_cat, total=sum(by_cat.values()),
        ))
    return MonthlyByCategoryResponse(months=months, categories=CATEGORY_ORDER, rows=rows)


@router.get("/daily_cumulative", response_model=DailyCumulativeResponse)
def daily_cumulative(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> DailyCumulativeResponse:
    start, end = _month_range(ym)
    tx_stmt = select(
        Transaction.purchased_at, Transaction.id, Transaction.screening_category, Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
        Transaction.tx_type == "expense",
    ).order_by(Transaction.purchased_at)  # type: ignore
    tx_rows = list(session.exec(tx_stmt).all())

    items_by_tx: dict[int, list[TransactionItem]] = defaultdict(list)
    if tx_rows:
        tx_ids = [row[1] for row in tx_rows]
        item_stmt = select(TransactionItem).where(
            TransactionItem.transaction_id.in_(tx_ids)  # type: ignore
        )
        for item in session.exec(item_stmt).all():
            items_by_tx[item.transaction_id].append(item)

    daily_total: dict[date, int] = defaultdict(int)
    for purchased_at, tx_id, screening_category, amount in tx_rows:
        items = items_by_tx.get(tx_id, [])
        if items:
            for item in items:
                daily_total[purchased_at] += item.amount
        else:
            daily_total[purchased_at] += amount

    points: list[DailyCumulativePoint] = []
    cum = 0
    cursor = start
    while cursor < end:
        cum += daily_total.get(cursor, 0)
        points.append(DailyCumulativePoint(date=cursor.isoformat(), cumulative=cum))
        cursor += timedelta(days=1)
    return DailyCumulativeResponse(ym=ym, points=points, total=cum)


@router.get("/top_transactions", response_model=TopTransactionsResponse)
def top_transactions(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    limit: int = Query(10, ge=1, le=50),
    session: Session = Depends(get_session),
) -> TopTransactionsResponse:
    start, end = _month_range(ym)
    stmt = select(
        Transaction.id,
        Transaction.purchased_at,
        Transaction.merchant_normalized,
        Transaction.merchant_raw,
        Transaction.screening_category,
        Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
        Transaction.tx_type == "expense",
    ).order_by(Transaction.amount.desc()).limit(limit)  # type: ignore
    rows = session.exec(stmt).all()
    items = [
        TopTransactionItem(
            id=row[0], purchased_at=row[1].isoformat(),
            merchant=row[2] or row[3] or "(空)",
            category=row[4], amount=row[5],
        )
        for row in rows
    ]
    return TopTransactionsResponse(ym=ym, limit=limit, items=items)


@router.get("/cashflow", response_model=CashflowSummary)
def cashflow_summary(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> CashflowSummary:
    """指定月の収支 (収入 / 支出 / 差額)."""
    start, end = _month_range(ym)
    income = _sum_by_type(session, start, end, "income")
    expense = _sum_by_type(session, start, end, "expense")
    return CashflowSummary(ym=ym, income=income, expense=expense, balance=income - expense)


@router.get("/month_compare", response_model=MonthCompareResponse)
def month_compare(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> MonthCompareResponse:
    """今月と先月のカテゴリ別差分."""
    prev = _previous_ym(ym)
    cur_start, cur_end = _month_range(ym)
    prev_start, prev_end = _month_range(prev)
    cur_by_cat = _aggregate_by_category(session, cur_start, cur_end, "expense")
    prev_by_cat = _aggregate_by_category(session, prev_start, prev_end, "expense")

    all_cats = sorted(set(cur_by_cat.keys()) | set(prev_by_cat.keys()))
    diffs: list[CategoryDiff] = []
    for c in all_cats:
        cur_v = cur_by_cat.get(c, 0)
        prev_v = prev_by_cat.get(c, 0)
        d = cur_v - prev_v
        ratio = ((cur_v - prev_v) / prev_v) if prev_v > 0 else None
        diffs.append(CategoryDiff(
            category=c, current=cur_v, previous=prev_v, diff=d, ratio=ratio,
        ))
    diffs.sort(key=lambda x: -abs(x.diff))
    return MonthCompareResponse(current_ym=ym, previous_ym=prev, diffs=diffs)
EOF

# ===========================================================================
# 4. frontend/src/types.ts に TxType + is_income 追加
# ===========================================================================
echo "==> frontend/src/types.ts (TxType追加)"
python3 <<'PYEOF'
from pathlib import Path
p = Path("frontend/src/types.ts")
text = p.read_text(encoding="utf-8")

# CategoryMaster に is_income 追加
if "is_income" not in text:
    text = text.replace(
        "export interface CategoryMaster {\n  name: Category;\n  description: string;\n  tax_rate: number;\n  sort_order: number;\n}",
        """export interface CategoryMaster {
  name: string;
  description: string;
  tax_rate: number;
  sort_order: number;
  is_income: boolean;
}""",
    )

# TxType 追加
if "export type TxType" in text and "expense" not in text:
    text = text.replace(
        'export type TxStatus = "auto_saved" | "user_confirmed" | "manually_added";',
        'export type TxStatus = "auto_saved" | "user_confirmed" | "manually_added";\n\nexport type TxKind = "expense" | "income";',
    )
elif "TxKind" not in text:
    # 追加
    text = text.replace(
        'export type TxStatus = "auto_saved" | "user_confirmed" | "manually_added";',
        'export type TxStatus = "auto_saved" | "user_confirmed" | "manually_added";\n\nexport type TxKind = "expense" | "income";',
    )

# Transaction interface に tx_type 追加
if "tx_type" not in text:
    text = text.replace(
        "  status: TxStatus;",
        "  status: TxStatus;\n  tx_type: TxKind;",
    )

p.write_text(text, encoding="utf-8")
print("  types.ts 更新完了")
PYEOF

# ===========================================================================
# 5. frontend/src/api.ts に cashflow/month_compare 追加
# ===========================================================================
echo "==> frontend/src/api.ts (cashflow/month_compare API追加)"
python3 <<'PYEOF'
from pathlib import Path
p = Path("frontend/src/api.ts")
text = p.read_text(encoding="utf-8")
if "cashflowSummary" not in text:
    addition = """

// ===== Cashflow (income/expense) =====
export interface CashflowSummary {
  ym: string;
  income: number;
  expense: number;
  balance: number;
}

export interface CategoryDiff {
  category: string;
  current: number;
  previous: number;
  diff: number;
  ratio: number | null;
}

export interface MonthCompareResponse {
  current_ym: string;
  previous_ym: string;
  diffs: CategoryDiff[];
}

export async function cashflowSummary(ym: string): Promise<CashflowSummary> {
  return handle<CashflowSummary>(await fetch(`${BASE}/summary/cashflow?ym=${ym}`));
}

export async function monthCompare(ym: string): Promise<MonthCompareResponse> {
  return handle<MonthCompareResponse>(await fetch(`${BASE}/summary/month_compare?ym=${ym}`));
}
"""
    text = text.rstrip() + addition
    p.write_text(text, encoding="utf-8")
    print("  api.ts 追加完了")
else:
    print("  既存")
PYEOF

# ===========================================================================
# 6. frontend/src/components/GraphView.tsx 拡張 (収支カード + 前月比カード)
# ===========================================================================
echo "==> frontend/src/components/GraphView.tsx"
cat > frontend/src/components/GraphView.tsx <<'EOF'
import { useEffect, useMemo, useState } from "react";
import {
  Bar, BarChart, CartesianGrid, Cell, Legend, Line, LineChart,
  Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import {
  cashflowSummary, categorySummary, dailyCumulative,
  monthCompare, monthlyByCategory, monthlySummary, topTransactions,
} from "../api";
import type {
  CashflowSummary, CategorySummary, DailyCumulativeResponse,
  MonthCompareResponse, MonthlyByCategoryResponse, MonthlySummary, TopTransactionsResponse,
} from "../api";

const COLORS: Record<string, string> = {
  "食費": "#22c55e", "酒類": "#f59e0b", "外食": "#ef4444",
  "日用品": "#3b82f6", "交通費": "#8b5cf6", "医療費": "#ec4899",
  "娯楽費": "#06b6d4", "衣料費": "#f97316", "その他": "#94a3b8",
};

function currentYm(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

export function GraphView() {
  const [ym, setYm] = useState<string>(currentYm());
  const [cashflow, setCashflow] = useState<CashflowSummary | null>(null);
  const [compare, setCompare] = useState<MonthCompareResponse | null>(null);
  const [cat, setCat] = useState<CategorySummary | null>(null);
  const [monthly, setMonthly] = useState<MonthlySummary | null>(null);
  const [stack, setStack] = useState<MonthlyByCategoryResponse | null>(null);
  const [daily, setDaily] = useState<DailyCumulativeResponse | null>(null);
  const [top, setTop] = useState<TopTransactionsResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    Promise.all([
      cashflowSummary(ym), monthCompare(ym),
      categorySummary(ym), monthlySummary(6),
      monthlyByCategory(6), dailyCumulative(ym), topTransactions(ym, 10),
    ])
      .then(([cf, cmp, c, m, s, d, t]) => {
        setCashflow(cf); setCompare(cmp); setCat(c); setMonthly(m);
        setStack(s); setDaily(d); setTop(t);
      })
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }, [ym]);

  const pieData = useMemo(() => {
    if (!cat) return [];
    return cat.slices.map((s) => ({ name: s.category, value: s.amount }));
  }, [cat]);

  const stackData = useMemo(() => {
    if (!stack) return [];
    return stack.rows.map((row) => ({ ym: row.ym, ...row.by_category }));
  }, [stack]);

  const usedCategories = useMemo(() => {
    if (!stack) return [];
    const set = new Set<string>();
    stack.rows.forEach((row) => Object.keys(row.by_category).forEach((c) => set.add(c)));
    return stack.categories.filter((c) => set.has(c));
  }, [stack]);

  return (
    <div>
      {/* 月選択 */}
      <div className="card">
        <h2>表示月の選択</h2>
        <input type="month" value={ym} onChange={(e) => setYm(e.target.value)} />
        {loading && <p>読込中...</p>}
        {error && <p className="err">{error}</p>}
      </div>

      {/* 収支サマリー (新) */}
      <div className="card">
        <h3>収支サマリー ({ym})</h3>
        {cashflow && (
          <div className="cashflow-grid">
            <div className="cashflow-item income">
              <div className="label">収入</div>
              <div className="value">{cashflow.income.toLocaleString()}円</div>
            </div>
            <div className="cashflow-item expense">
              <div className="label">支出</div>
              <div className="value">{cashflow.expense.toLocaleString()}円</div>
            </div>
            <div className={`cashflow-item balance ${cashflow.balance >= 0 ? "positive" : "negative"}`}>
              <div className="label">収支差額</div>
              <div className="value">
                {cashflow.balance >= 0 ? "+" : ""}
                {cashflow.balance.toLocaleString()}円
              </div>
            </div>
          </div>
        )}
      </div>

      {/* 前月比較 (新) */}
      <div className="card">
        <h3>前月比較 ({compare?.previous_ym} → {compare?.current_ym})</h3>
        {compare && compare.diffs.length === 0 && (
          <p className="hint">比較データなし.</p>
        )}
        {compare && compare.diffs.length > 0 && (
          <table className="tx-table" style={{ fontSize: "0.9em" }}>
            <thead>
              <tr>
                <th>カテゴリ</th>
                <th style={{ textAlign: "right" }}>先月</th>
                <th style={{ textAlign: "right" }}>今月</th>
                <th style={{ textAlign: "right" }}>差額</th>
                <th style={{ textAlign: "right" }}>増減率</th>
              </tr>
            </thead>
            <tbody>
              {compare.diffs.map((d) => (
                <tr key={d.category}>
                  <td>{d.category}</td>
                  <td style={{ textAlign: "right" }}>{d.previous.toLocaleString()}</td>
                  <td style={{ textAlign: "right" }}>{d.current.toLocaleString()}</td>
                  <td style={{
                    textAlign: "right",
                    color: d.diff > 0 ? "#cf222e" : d.diff < 0 ? "#1a7f37" : "#666",
                  }}>
                    {d.diff > 0 ? "+" : ""}{d.diff.toLocaleString()}
                  </td>
                  <td style={{
                    textAlign: "right",
                    color: (d.ratio ?? 0) > 0 ? "#cf222e" : (d.ratio ?? 0) < 0 ? "#1a7f37" : "#666",
                  }}>
                    {d.ratio === null
                      ? "(新規)"
                      : `${(d.ratio * 100 > 0 ? "+" : "")}${(d.ratio * 100).toFixed(1)}%`}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* 既存: カテゴリ別円グラフ */}
      <div className="card">
        <h3>カテゴリ別支出 ({ym})</h3>
        {cat && pieData.length > 0 && (
          <>
            <p>合計: <b>{cat.total.toLocaleString()}円</b></p>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie data={pieData} dataKey="value" nameKey="name"
                     cx="50%" cy="50%" outerRadius={100}
                     label={(e: any) => `${e.name} ${e.value.toLocaleString()}円`}>
                  {pieData.map((entry) => (
                    <Cell key={entry.name} fill={COLORS[entry.name] ?? "#94a3b8"} />
                  ))}
                </Pie>
                <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </>
        )}
        {cat && pieData.length === 0 && <p className="hint">支出データなし.</p>}
      </div>

      {/* 日次累積 */}
      <div className="card">
        <h3>日次累積支出 ({ym})</h3>
        {daily && daily.points.length > 0 && (
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={daily.points}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="date" tickFormatter={(d: string) => d.slice(-2)} />
              <YAxis tickFormatter={(v: number) => (v / 1000).toFixed(0) + "k"} />
              <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
              <Line type="monotone" dataKey="cumulative" stroke="#1f6feb"
                    strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 月別カテゴリ積み上げ */}
      <div className="card">
        <h3>過去6ヶ月のカテゴリ別支出</h3>
        {stack && stackData.length > 0 && (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={stackData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="ym" />
              <YAxis tickFormatter={(v: number) => (v / 1000).toFixed(0) + "k"} />
              <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
              <Legend />
              {usedCategories.map((c) => (
                <Bar key={c} dataKey={c} stackId="a" fill={COLORS[c] ?? "#94a3b8"} />
              ))}
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 月次合計 */}
      <div className="card">
        <h3>月次合計推移 (過去6ヶ月)</h3>
        {monthly && monthly.slices.length > 0 && (
          <ResponsiveContainer width="100%" height={240}>
            <BarChart data={monthly.slices}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="ym" />
              <YAxis tickFormatter={(v: number) => (v / 1000).toFixed(0) + "k"} />
              <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
              <Bar dataKey="total" fill="#1f6feb" />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 大口支出 TOP10 */}
      <div className="card">
        <h3>大口支出 TOP10 ({ym})</h3>
        {top && top.items.length === 0 && <p className="hint">取引なし.</p>}
        {top && top.items.length > 0 && (
          <table className="tx-table" style={{ fontSize: "0.9em" }}>
            <thead>
              <tr>
                <th>順位</th><th>日付</th><th>店舗</th><th>カテゴリ</th>
                <th style={{ textAlign: "right" }}>金額</th>
              </tr>
            </thead>
            <tbody>
              {top.items.map((it, i) => (
                <tr key={it.id}>
                  <td>{i + 1}</td>
                  <td>{it.purchased_at}</td>
                  <td>{it.merchant}</td>
                  <td>{it.category || "(未分類)"}</td>
                  <td style={{ textAlign: "right" }}>
                    <b>{it.amount.toLocaleString()}円</b>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
EOF

# ===========================================================================
# 7. frontend/src/components/EditView.tsx に収入/支出トグル追加
# ===========================================================================
echo "==> frontend/src/components/EditView.tsx (収入/支出トグル追加)"
python3 <<'PYEOF'
from pathlib import Path
p = Path("frontend/src/components/EditView.tsx")
text = p.read_text(encoding="utf-8")

# tx_type state を追加 (memo state の近く)
if "tx_type" not in text:
    text = text.replace(
        "const [memo, setMemo] = useState(tx.memo || \"\");",
        'const [memo, setMemo] = useState(tx.memo || "");\n  const [txType, setTxType] = useState<string>(tx.tx_type || "expense");',
    )

    # form-grid に「種別」セレクタ追加 (日付フィールドの直後)
    text = text.replace(
        '<label>日付</label>\n          <input type="date" value={purchasedAt}\n                 onChange={(e) => setPurchasedAt(e.target.value)} />',
        '<label>種別</label>\n          <select value={txType} onChange={(e) => setTxType(e.target.value)}>\n            <option value="expense">支出</option>\n            <option value="income">収入</option>\n          </select>\n          <label>日付</label>\n          <input type="date" value={purchasedAt}\n                 onChange={(e) => setPurchasedAt(e.target.value)} />',
    )

    # updateTransaction の引数に tx_type 追加
    text = text.replace(
        "status: \"user_confirmed\",\n      });",
        'status: "user_confirmed",\n        tx_type: txType,\n      });',
    )

    p.write_text(text, encoding="utf-8")
    print("  EditView.tsx 更新完了")
else:
    print("  既存")
PYEOF

# ===========================================================================
# 8. frontend/src/App.css に cashflow スタイル追加
# ===========================================================================
echo "==> frontend/src/App.css (cashflow グリッド)"
if ! grep -q "cashflow-grid" frontend/src/App.css; then
  cat >> frontend/src/App.css <<'EOF'

.cashflow-grid {
  display: grid;
  grid-template-columns: 1fr 1fr 1fr;
  gap: 12px;
  margin: 12px 0;
}
.cashflow-item {
  padding: 16px;
  border-radius: 8px;
  text-align: center;
}
.cashflow-item .label {
  font-size: 0.85em;
  color: #57606a;
  margin-bottom: 4px;
}
.cashflow-item .value {
  font-size: 1.3em;
  font-weight: bold;
}
.cashflow-item.income { background: #dafbe1; color: #1a7f37; }
.cashflow-item.expense { background: #ffebe9; color: #cf222e; }
.cashflow-item.balance.positive { background: #ddf4ff; color: #0969da; }
.cashflow-item.balance.negative { background: #fff8c5; color: #9a6700; }
@media (max-width: 720px) {
  .cashflow-grid { grid-template-columns: 1fr; }
}
EOF
fi

# ===========================================================================
# 9. data.db を migrate (tx_type 列 + is_income 列 追加)
# ===========================================================================
echo ""
echo "==> data.db を migrate (tx_type / is_income 列追加)"
python3 <<'PYEOF'
import sqlite3, os
db = "/workspaces/kakeibo/backend/data.db"
if not os.path.exists(db):
    print("  data.db 不在、初回起動時に作成される")
else:
    con = sqlite3.connect(db)
    cur = con.cursor()
    # tx_type 列追加
    try:
        cur.execute("ALTER TABLE transactions ADD COLUMN tx_type TEXT NOT NULL DEFAULT 'expense'")
        print("  transactions.tx_type 列追加")
    except sqlite3.OperationalError as e:
        if "duplicate column" in str(e):
            print("  transactions.tx_type 列 既存")
        else:
            raise
    # is_income 列追加
    try:
        cur.execute("ALTER TABLE category_master ADD COLUMN is_income INTEGER NOT NULL DEFAULT 0")
        print("  category_master.is_income 列追加")
    except sqlite3.OperationalError as e:
        if "duplicate column" in str(e):
            print("  category_master.is_income 列 既存")
        else:
            raise
    con.commit()
    con.close()
PYEOF

# ===========================================================================
# 10. uvicorn 再起動
# ===========================================================================
echo ""
echo "==> uvicorn 再起動"
pkill -9 -f uvicorn 2>/dev/null; sleep 2
(cd /workspaces/kakeibo/backend && nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 5

echo ""
echo "==> health"
curl -s http://localhost:8000/api/health; echo

YM=$(date +%Y-%m)

echo ""
echo "==> 収支サマリー"
curl -s "http://localhost:8000/api/summary/cashflow?ym=$YM" | python3 -m json.tool

echo ""
echo "==> 前月比較"
curl -s "http://localhost:8000/api/summary/month_compare?ym=$YM" | python3 -m json.tool | head -30

echo ""
echo "==> カテゴリ一覧 (収入カテゴリ含む)"
curl -s http://localhost:8000/api/categories | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'  全{len(data)}カテゴリ')
for c in data:
    kind = '収入' if c['is_income'] else '支出'
    print(f'    [{kind}] {c[\"name\"]} ({c[\"tax_rate\"]}%)')
"

cat <<EOM

============================================================
収入機能 + 前月比較 完了.

新機能:
  - tx_type 列: "expense" or "income"
  - 収入カテゴリ3種: 給与/副収入/その他収入
  - GET /api/summary/cashflow: 収入/支出/差額
  - GET /api/summary/month_compare: 前月比較
  - グラフタブに「収支サマリー」「前月比較」追加
  - 編集モーダルに「種別」セレクタ追加

収入を登録するには:
  1. 「取込」→ 画像/CSV取込 で適当な取引を作る
  2. 「一覧」→ 編集
  3. 種別を「収入」に変更, カテゴリ「給与」等を選択
  4. 保存
  → 収支サマリーに反映

ブラウザリロード: Ctrl+Shift+R
============================================================
EOM
