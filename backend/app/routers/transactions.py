"""Transactions + items CRUD — no Relationship, query items on demand."""
from __future__ import annotations
from datetime import date, datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, select

from app.database import get_session
from app.models import (
    CategoryMaster, Transaction, TransactionCreate, TransactionItem,
    TransactionItemCreate, TransactionItemRead, TransactionItemUpdate,
    TransactionRead, TransactionReadWithItems, TransactionUpdate,
    calc_header_totals_from_items, calc_tax_amount, derive_header_category_from_items,
)

router = APIRouter(prefix="/api/transactions", tags=["transactions"])


def _tax_rate_for(category, session):
    if category is None:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


def _fetch_items(session, tx_id):
    """指定取引の明細を sort_order 順で取得."""
    stmt = select(TransactionItem).where(
        TransactionItem.transaction_id == tx_id
    ).order_by(TransactionItem.sort_order)  # type: ignore
    return list(session.exec(stmt).all())


def _recalc_header_from_items(tx, session):
    """明細から再計算してヘッダ更新. 明細が空なら何もしない."""
    items = _fetch_items(session, tx.id)
    if not items:
        return
    total_amount, total_tax = calc_header_totals_from_items(
        items, lambda cat: _tax_rate_for(cat, session)
    )
    tx.amount = total_amount
    tx.tax_amount = total_tax
    tx.screening_category = derive_header_category_from_items(items)


def _tx_with_items(session, tx) -> TransactionReadWithItems:
    """Transaction + items を TransactionReadWithItems に変換."""
    items = _fetch_items(session, tx.id)
    return TransactionReadWithItems(
        **tx.model_dump(),
        items=[TransactionItemRead(**it.model_dump()) for it in items],
    )


@router.get("", response_model=list[TransactionRead])
def list_transactions(
    status: str | None = Query(None),
    needs_review: bool | None = None,
    merchant: str | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    session: Session = Depends(get_session),
):
    stmt = select(Transaction)
    if status:
        statuses = [s.strip() for s in status.split(",") if s.strip()]
        stmt = stmt.where(Transaction.status.in_(statuses))  # type: ignore
    if needs_review is not None:
        stmt = stmt.where(Transaction.needs_review == needs_review)
    if merchant:
        stmt = stmt.where(Transaction.merchant_normalized.contains(merchant))  # type: ignore
    if start_date:
        stmt = stmt.where(Transaction.purchased_at >= start_date)
    if end_date:
        stmt = stmt.where(Transaction.purchased_at <= end_date)
    stmt = stmt.order_by(Transaction.purchased_at.desc(), Transaction.id.desc())  # type: ignore
    stmt = stmt.offset(offset).limit(limit)
    return list(session.exec(stmt).all())


@router.get("/{tx_id}", response_model=TransactionReadWithItems)
def get_transaction(tx_id: int, session: Session = Depends(get_session)):
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    return _tx_with_items(session, tx)


@router.post("", response_model=TransactionRead, status_code=201)
def create_transaction(payload: TransactionCreate, session: Session = Depends(get_session)):
    data = payload.model_dump()
    if data.get("tax_amount", 0) == 0 and data.get("amount", 0) > 0:
        rate = _tax_rate_for(data.get("screening_category"), session)
        data["tax_amount"] = calc_tax_amount(data["amount"], rate)
    tx = Transaction(**data)
    session.add(tx)
    session.commit()
    session.refresh(tx)
    return tx


@router.patch("/{tx_id}", response_model=TransactionReadWithItems)
def update_transaction(tx_id: int, payload: TransactionUpdate, session: Session = Depends(get_session)):
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    data = payload.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(tx, k, v)
    if ("screening_category" in data or "amount" in data) and "tax_amount" not in data:
        rate = _tax_rate_for(tx.screening_category, session)
        tx.tax_amount = calc_tax_amount(tx.amount, rate)
    # 明細がある場合はヘッダを明細から再計算
    _recalc_header_from_items(tx, session)
    tx.updated_at = datetime.utcnow()
    session.add(tx)
    session.commit()
    session.refresh(tx)
    return _tx_with_items(session, tx)


@router.delete("/{tx_id}", status_code=204)
def delete_transaction(tx_id: int, session: Session = Depends(get_session)):
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    # カスケード削除を手動実装
    items = _fetch_items(session, tx_id)
    for it in items:
        session.delete(it)
    session.delete(tx)
    session.commit()


# ===== Items endpoints =====

@router.get("/{tx_id}/items", response_model=list[TransactionItemRead])
def list_items(tx_id: int, session: Session = Depends(get_session)):
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="transaction not found")
    return _fetch_items(session, tx_id)


@router.post("/{tx_id}/items", response_model=TransactionItemRead, status_code=201)
def create_item(
    tx_id: int,
    payload: TransactionItemCreate,
    session: Session = Depends(get_session),
):
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="transaction not found")
    rate = _tax_rate_for(payload.category, session)
    item = TransactionItem(
        transaction_id=tx_id,
        name=payload.name,
        amount=payload.amount,
        tax_amount=calc_tax_amount(payload.amount, rate),
        category=payload.category,
        sort_order=payload.sort_order,
    )
    session.add(item)
    session.flush()
    _recalc_header_from_items(tx, session)
    tx.updated_at = datetime.utcnow()
    session.add(tx)
    session.commit()
    session.refresh(item)
    return item


@router.patch("/{tx_id}/items/{item_id}", response_model=TransactionItemRead)
def update_item(
    tx_id: int,
    item_id: int,
    payload: TransactionItemUpdate,
    session: Session = Depends(get_session),
):
    item = session.get(TransactionItem, item_id)
    if item is None or item.transaction_id != tx_id:
        raise HTTPException(status_code=404, detail="item not found")
    data = payload.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(item, k, v)
    rate = _tax_rate_for(item.category, session)
    item.tax_amount = calc_tax_amount(item.amount, rate)
    session.add(item)
    session.flush()
    tx = session.get(Transaction, tx_id)
    if tx is not None:
        _recalc_header_from_items(tx, session)
        tx.updated_at = datetime.utcnow()
        session.add(tx)
    session.commit()
    session.refresh(item)
    return item


@router.delete("/{tx_id}/items/{item_id}", status_code=204)
def delete_item(
    tx_id: int,
    item_id: int,
    session: Session = Depends(get_session),
):
    item = session.get(TransactionItem, item_id)
    if item is None or item.transaction_id != tx_id:
        raise HTTPException(status_code=404, detail="item not found")
    session.delete(item)
    session.flush()
    tx = session.get(Transaction, tx_id)
    if tx is not None:
        _recalc_header_from_items(tx, session)
        tx.updated_at = datetime.utcnow()
        session.add(tx)
    session.commit()