"""Summary API — extended for cashflow visualization."""
from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlmodel import Session, select

from app.database import get_session
from app.models import Transaction, TransactionItem

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
    """月×カテゴリ合計 (積み上げ棒用)."""
    ym: str
    by_category: dict[str, int]  # {"食費": 12000, ...}
    total: int


class MonthlyByCategoryResponse(BaseModel):
    months: int
    categories: list[str]  # 表示順
    rows: list[MonthlyByCategoryRow]


class DailyCumulativePoint(BaseModel):
    date: str  # YYYY-MM-DD
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
    session: Session, start: date, end: date,
) -> dict[str, int]:
    """期間内のカテゴリ別合計."""
    by_cat: dict[str, int] = defaultdict(int)
    tx_stmt = select(
        Transaction.id, Transaction.screening_category, Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
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


# ===== Endpoints =====

@router.get("/category", response_model=CategorySummary)
def category_summary(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> CategorySummary:
    start, end = _month_range(ym)
    by_cat = _aggregate_by_category(session, start, end)
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
        by_cat = _aggregate_by_category(session, start, end)
        slices.append(MonthlySliceItem(ym=ym, total=sum(by_cat.values())))
    return MonthlySummary(months=months, slices=slices)


@router.get("/monthly_by_category", response_model=MonthlyByCategoryResponse)
def monthly_by_category(
    months: int = Query(6, ge=1, le=24),
    session: Session = Depends(get_session),
) -> MonthlyByCategoryResponse:
    """月×カテゴリのマトリクス (積み上げ棒グラフ用)."""
    yms = _generate_yms(months)
    rows: list[MonthlyByCategoryRow] = []
    for ym in yms:
        start, end = _month_range(ym)
        by_cat = _aggregate_by_category(session, start, end)
        rows.append(MonthlyByCategoryRow(
            ym=ym, by_category=by_cat, total=sum(by_cat.values()),
        ))
    return MonthlyByCategoryResponse(
        months=months, categories=CATEGORY_ORDER, rows=rows,
    )


@router.get("/daily_cumulative", response_model=DailyCumulativeResponse)
def daily_cumulative(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> DailyCumulativeResponse:
    """指定月の日次累積支出."""
    start, end = _month_range(ym)
    # 日別合計を取得 (取引のみベース、明細単位は集計しない簡易版)
    tx_stmt = select(
        Transaction.purchased_at, Transaction.id, Transaction.screening_category, Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
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

    # 月初から月末まで全日埋める
    points: list[DailyCumulativePoint] = []
    cum = 0
    cursor = start
    while cursor < end:
        cum += daily_total.get(cursor, 0)
        points.append(DailyCumulativePoint(
            date=cursor.isoformat(), cumulative=cum,
        ))
        cursor += timedelta(days=1)
    return DailyCumulativeResponse(ym=ym, points=points, total=cum)


@router.get("/top_transactions", response_model=TopTransactionsResponse)
def top_transactions(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    limit: int = Query(10, ge=1, le=50),
    session: Session = Depends(get_session),
) -> TopTransactionsResponse:
    """指定月の大口支出TOP."""
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
    ).order_by(Transaction.amount.desc()).limit(limit)  # type: ignore
    rows = session.exec(stmt).all()
    items = [
        TopTransactionItem(
            id=row[0],
            purchased_at=row[1].isoformat(),
            merchant=row[2] or row[3] or "(空)",
            category=row[4],
            amount=row[5],
        )
        for row in rows
    ]
    return TopTransactionsResponse(ym=ym, limit=limit, items=items)
