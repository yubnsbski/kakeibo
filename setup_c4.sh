#!/usr/bin/env bash
# kakeibo C4: 明細単位カテゴリ分類対応.
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_c4.sh
#
# 変更:
#   - DB: transaction_items テーブル新設
#   - API: 明細 CRUD + ヘッダ自動再計算
#   - UI: 編集モーダルに明細セクション
#   - 既存挙動: 明細未使用なら従来通り
#
# 注意: data.db リセット.

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "C4 setup: 明細単位カテゴリ分類"
echo "============================================================"

# ===========================================================================
# 1. backend/app/models.py (transaction_items テーブル + 関数追加)
# ===========================================================================
echo "==> backend/app/models.py"
cat > backend/app/models.py <<'EOF'
"""SQLModel models — C4: with transaction_items."""
from __future__ import annotations
from datetime import date, datetime
from typing import Literal
from sqlmodel import Field, Relationship, SQLModel

TxStatus = Literal["auto_saved", "user_confirmed", "manually_added"]


class TransactionBase(SQLModel):
    receipt_id: str | None = None
    merchant_raw: str
    merchant_normalized: str
    items_text: str = ""
    screening_category: str | None = None
    needs_review: bool = False
    reason: str = ""
    confidence: float = 0.0
    amount: int
    tax_amount: int = 0
    purchased_at: date
    memo: str | None = None
    receipt_image_id: int | None = Field(default=None, foreign_key="receipts.id")
    status: str = Field(default="manually_added")
    ocr_raw_text: str | None = None


class Transaction(TransactionBase, table=True):
    __tablename__ = "transactions"
    id: int | None = Field(default=None, primary_key=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)

    items: list["TransactionItem"] = Relationship(
        back_populates="transaction",
        sa_relationship_kwargs={"cascade": "all, delete-orphan", "order_by": "TransactionItem.sort_order"},
    )


class TransactionItem(SQLModel, table=True):
    """明細1行 (C4)."""
    __tablename__ = "transaction_items"
    id: int | None = Field(default=None, primary_key=True)
    transaction_id: int = Field(foreign_key="transactions.id", index=True)
    name: str
    amount: int = 0
    tax_amount: int = 0
    category: str | None = None
    sort_order: int = 0

    transaction: Transaction | None = Relationship(back_populates="items")


class TransactionItemBase(SQLModel):
    name: str
    amount: int = 0
    category: str | None = None
    sort_order: int = 0


class TransactionItemCreate(TransactionItemBase):
    pass


class TransactionItemRead(TransactionItemBase):
    id: int
    transaction_id: int
    tax_amount: int


class TransactionItemUpdate(SQLModel):
    name: str | None = None
    amount: int | None = None
    category: str | None = None
    sort_order: int | None = None


class TransactionCreate(TransactionBase):
    pass


class TransactionReadWithItems(TransactionBase):
    id: int
    created_at: datetime
    updated_at: datetime
    items: list[TransactionItemRead] = []


class TransactionRead(TransactionBase):
    id: int
    created_at: datetime
    updated_at: datetime


class TransactionUpdate(SQLModel):
    merchant_raw: str | None = None
    merchant_normalized: str | None = None
    items_text: str | None = None
    screening_category: str | None = None
    needs_review: bool | None = None
    reason: str | None = None
    confidence: float | None = None
    amount: int | None = None
    tax_amount: int | None = None
    purchased_at: date | None = None
    memo: str | None = None
    status: str | None = None


class Receipt(SQLModel, table=True):
    __tablename__ = "receipts"
    id: int | None = Field(default=None, primary_key=True)
    filename: str
    ocr_text: str | None = None
    status: str = "pending"
    created_at: datetime = Field(default_factory=datetime.utcnow)


class UserCategoryOverride(SQLModel, table=True):
    __tablename__ = "user_category_overrides"
    id: int | None = Field(default=None, primary_key=True)
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


class CategoryMasterRead(SQLModel):
    name: str
    description: str
    tax_rate: int
    sort_order: int


def calc_tax_amount(amount_incl_tax: int, tax_rate: int) -> int:
    """税込金額から税額逆算."""
    if amount_incl_tax <= 0 or tax_rate <= 0:
        return 0
    return round(amount_incl_tax * tax_rate / (100 + tax_rate))


def derive_header_category_from_items(items: list[TransactionItem]) -> str | None:
    """明細から主カテゴリを導出 (最大金額のカテゴリ).

    None を返す場合:
      - 明細が空
      - 全明細が未分類 (category=None)
    """
    if not items:
        return None
    by_category: dict[str, int] = {}
    for item in items:
        if item.category:
            by_category[item.category] = by_category.get(item.category, 0) + item.amount
    if not by_category:
        return None
    return max(by_category.items(), key=lambda x: x[1])[0]


def calc_header_totals_from_items(
    items: list[TransactionItem], tax_rate_lookup
) -> tuple[int, int]:
    """明細から合計金額・税額を算出.

    tax_rate_lookup: (category: str | None) -> int  の callable.
    """
    total_amount = 0
    total_tax = 0
    for item in items:
        total_amount += item.amount
        rate = tax_rate_lookup(item.category)
        total_tax += calc_tax_amount(item.amount, rate)
    return total_amount, total_tax
EOF

# ===========================================================================
# 2. backend/app/routers/transactions.py (items API + ヘッダ自動再計算)
# ===========================================================================
echo "==> backend/app/routers/transactions.py"
cat > backend/app/routers/transactions.py <<'EOF'
"""Transactions + items CRUD with header auto-recalc."""
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


def _tax_rate_for(category: str | None, session: Session) -> int:
    if category is None:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


def _recalc_header_from_items(tx: Transaction, session: Session) -> None:
    """明細が存在する場合のみヘッダを再計算.

    明細が空 → ヘッダの amount / screening_category / tax_amount は変更しない.
    """
    if not tx.items:
        return
    total_amount, total_tax = calc_header_totals_from_items(
        tx.items, lambda cat: _tax_rate_for(cat, session)
    )
    tx.amount = total_amount
    tx.tax_amount = total_tax
    tx.screening_category = derive_header_category_from_items(tx.items)


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
) -> list[Transaction]:
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
    return tx


@router.post("", response_model=TransactionRead, status_code=201)
def create_transaction(payload: TransactionCreate, session: Session = Depends(get_session)) -> Transaction:
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
    # 明細がある場合はヘッダを明細から再計算 (PATCHのamount/categoryは無視される)
    _recalc_header_from_items(tx, session)
    tx.updated_at = datetime.utcnow()
    session.add(tx)
    session.commit()
    session.refresh(tx)
    return tx


@router.delete("/{tx_id}", status_code=204)
def delete_transaction(tx_id: int, session: Session = Depends(get_session)) -> None:
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    session.delete(tx)
    session.commit()


# ===== Items endpoints =====

@router.get("/{tx_id}/items", response_model=list[TransactionItemRead])
def list_items(tx_id: int, session: Session = Depends(get_session)):
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="transaction not found")
    return tx.items


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
    session.refresh(tx)
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
    # 自動 tax_amount 再計算
    rate = _tax_rate_for(item.category, session)
    item.tax_amount = calc_tax_amount(item.amount, rate)
    session.add(item)
    session.flush()
    tx = session.get(Transaction, tx_id)
    if tx is not None:
        session.refresh(tx)
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
        session.refresh(tx)
        _recalc_header_from_items(tx, session)
        tx.updated_at = datetime.utcnow()
        session.add(tx)
    session.commit()
EOF

# ===========================================================================
# 3. backend/tests/test_items_api.py
# ===========================================================================
echo "==> backend/tests/test_items_api.py"
cat > backend/tests/test_items_api.py <<'EOF'
"""明細単位カテゴリ分類 (C4) のテスト."""
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


def _create_tx(client, **overrides):
    base = {
        "merchant_raw": "テスト",
        "merchant_normalized": "テスト",
        "items_text": "",
        "screening_category": None,
        "needs_review": False,
        "reason": "",
        "confidence": 0,
        "amount": 0,
        "purchased_at": "2026-05-17",
        "status": "manually_added",
    }
    base.update(overrides)
    r = client.post("/api/transactions", json=base)
    assert r.status_code == 201
    return r.json()


def test_add_items_recalculates_header(client):
    tx = _create_tx(client, amount=0)
    tx_id = tx["id"]
    # 明細を3つ追加
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "おにぎり", "amount": 180, "category": "食費"})
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "ビール", "amount": 300, "category": "酒類"})
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "弁当", "amount": 500, "category": "食費"})

    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["amount"] == 980, f"expected 980, got {data['amount']}"
    # 食費 (180+500=680) > 酒類 (300) → 主カテゴリは食費
    assert data["screening_category"] == "食費"
    assert len(data["items"]) == 3


def test_item_update_recalculates_header(client):
    tx = _create_tx(client)
    tx_id = tx["id"]
    r = client.post(f"/api/transactions/{tx_id}/items",
                    json={"name": "X", "amount": 100, "category": "食費"})
    item_id = r.json()["id"]

    client.patch(f"/api/transactions/{tx_id}/items/{item_id}",
                 json={"amount": 500, "category": "酒類"})

    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["amount"] == 500
    assert data["screening_category"] == "酒類"


def test_item_delete_recalculates_header(client):
    tx = _create_tx(client)
    tx_id = tx["id"]
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "A", "amount": 100, "category": "食費"})
    r = client.post(f"/api/transactions/{tx_id}/items",
                    json={"name": "B", "amount": 200, "category": "酒類"})
    item_id = r.json()["id"]

    client.delete(f"/api/transactions/{tx_id}/items/{item_id}")

    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["amount"] == 100
    assert data["screening_category"] == "食費"


def test_empty_items_keeps_header_amount(client):
    """明細空ならヘッダはそのまま."""
    tx = _create_tx(client, amount=1500, screening_category="食費")
    tx_id = tx["id"]
    r = client.get(f"/api/transactions/{tx_id}")
    assert r.json()["amount"] == 1500
    assert r.json()["screening_category"] == "食費"
    assert r.json()["items"] == []


def test_unclassified_items_yield_null_category(client):
    """全明細が未分類ならヘッダカテゴリも null."""
    tx = _create_tx(client)
    tx_id = tx["id"]
    client.post(f"/api/transactions/{tx_id}/items",
                json={"name": "X", "amount": 100, "category": None})
    r = client.get(f"/api/transactions/{tx_id}")
    data = r.json()
    assert data["screening_category"] is None
    assert data["amount"] == 100


def test_item_tax_amount_auto_calculated(client):
    """食費は8%、酒類は10%."""
    tx = _create_tx(client)
    tx_id = tx["id"]
    r1 = client.post(f"/api/transactions/{tx_id}/items",
                     json={"name": "おにぎり", "amount": 108, "category": "食費"})
    r2 = client.post(f"/api/transactions/{tx_id}/items",
                     json={"name": "ビール", "amount": 110, "category": "酒類"})
    assert r1.json()["tax_amount"] == 8, r1.json()
    assert r2.json()["tax_amount"] == 10, r2.json()
EOF

# ===========================================================================
# 4. frontend/src/types.ts (TransactionItem 型追加)
# ===========================================================================
echo "==> frontend/src/types.ts"
cat > frontend/src/types.ts <<'EOF'
export type Category =
  | "食費" | "酒類" | "外食" | "日用品"
  | "交通費" | "医療費" | "娯楽費" | "衣料費" | "その他";

export const CATEGORIES: Category[] = [
  "食費", "酒類", "外食", "日用品",
  "交通費", "医療費", "娯楽費", "衣料費", "その他",
];

export const DEFAULT_TAX_RATE: Record<Category, number> = {
  "食費": 8, "酒類": 10, "外食": 10, "日用品": 10,
  "交通費": 10, "医療費": 10, "娯楽費": 10, "衣料費": 10, "その他": 10,
};

export interface CategoryMaster {
  name: Category;
  description: string;
  tax_rate: number;
  sort_order: number;
}

export type TxStatus = "auto_saved" | "user_confirmed" | "manually_added";

export interface TransactionItem {
  id: number;
  transaction_id: number;
  name: string;
  amount: number;
  tax_amount: number;
  category: string | null;
  sort_order: number;
}

export interface Transaction {
  id: number;
  receipt_id: string | null;
  merchant_raw: string;
  merchant_normalized: string;
  items_text: string;
  screening_category: string | null;
  needs_review: boolean;
  reason: string;
  confidence: number;
  amount: number;
  tax_amount: number;
  purchased_at: string;
  memo: string | null;
  receipt_image_id: number | null;
  status: TxStatus;
  ocr_raw_text: string | null;
  created_at: string;
  updated_at: string;
  items?: TransactionItem[];
}

export interface ReceiptUploadResponse {
  transaction_id: number;
  filename: string;
  raw_text: string;
  merchant_raw: string;
  items: string[];
  total_amount: number | null;
  tax_amount: number;
  classification: {
    merchantNormalized: string;
    category: Category | null;
    confidence: number;
    needsReview: boolean;
    reason: string;
    reasons: string[];
    screeningLabel: "recordable" | "needs_review";
  };
}

export interface UserCategoryOverride {
  id: number;
  merchant_pattern: string;
  category: string;
  created_at: string;
}
EOF

# ===========================================================================
# 5. frontend/src/api.ts (items API 追加)
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

export async function uploadReceipt(file: File): Promise<ReceiptUploadResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/receipts/upload`, { method: "POST", body: fd });
  return handle<ReceiptUploadResponse>(r);
}

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
  const r = await fetch(`${BASE}/transactions/${id}`);
  return handle<Transaction>(r);
}

export async function updateTransaction(
  id: number, patch: Partial<Transaction>
): Promise<Transaction> {
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

export async function listOverrides(): Promise<UserCategoryOverride[]> {
  const r = await fetch(`${BASE}/overrides`);
  return handle<UserCategoryOverride[]>(r);
}

export async function createOverride(
  merchant_pattern: string, category: string
): Promise<UserCategoryOverride> {
  const r = await fetch(`${BASE}/overrides`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ merchant_pattern, category }),
  });
  return handle<UserCategoryOverride>(r);
}

export async function listCategories(): Promise<CategoryMaster[]> {
  const r = await fetch(`${BASE}/categories`);
  return handle<CategoryMaster[]>(r);
}

// ===== Items =====

export async function createItem(
  txId: number,
  item: { name: string; amount: number; category: string | null; sort_order?: number }
): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...item, sort_order: item.sort_order ?? 0 }),
  });
  return handle<TransactionItem>(r);
}

export async function updateItem(
  txId: number, itemId: number, patch: Partial<TransactionItem>
): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, {
    method: "PATCH", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  return handle<TransactionItem>(r);
}

export async function deleteItem(txId: number, itemId: number): Promise<void> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, {
    method: "DELETE",
  });
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
}
EOF

# ===========================================================================
# 6. frontend/src/components/EditView.tsx (明細セクション)
# ===========================================================================
echo "==> frontend/src/components/EditView.tsx"
cat > frontend/src/components/EditView.tsx <<'EOF'
import { useEffect, useState } from "react";
import {
  updateTransaction, createOverride, listCategories,
  getTransaction, createItem, updateItem, deleteItem,
} from "../api";
import type { Transaction, TransactionItem, CategoryMaster } from "../types";
import { CATEGORIES, DEFAULT_TAX_RATE } from "../types";

interface Props {
  tx: Transaction;
  onClose: () => void;
  onSaved: () => void;
}

export function EditView({ tx, onClose, onSaved }: Props) {
  const [merchantNormalized, setMerchantNormalized] = useState(tx.merchant_normalized);
  const [category, setCategory] = useState<string>(tx.screening_category || "");
  const [amount, setAmount] = useState(String(tx.amount));
  const [purchasedAt, setPurchasedAt] = useState(tx.purchased_at);
  const [memo, setMemo] = useState(tx.memo || "");
  const [needsReview, setNeedsReview] = useState(tx.needs_review);
  const [registerOverride, setRegisterOverride] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [catMaster, setCatMaster] = useState<CategoryMaster[]>([]);
  const [items, setItems] = useState<TransactionItem[]>([]);
  const [itemsBusy, setItemsBusy] = useState(false);

  useEffect(() => {
    listCategories().then(setCatMaster).catch(() => {});
    // 明細を取得
    getTransaction(tx.id).then((full) => {
      setItems(full.items || []);
    }).catch(() => {});
  }, [tx.id]);

  const taxRateFor = (cat: string | null): number => {
    if (!cat) return 10;
    const found = catMaster.find((c) => c.name === cat);
    if (found) return found.tax_rate;
    return DEFAULT_TAX_RATE[cat as keyof typeof DEFAULT_TAX_RATE] ?? 10;
  };

  const taxRate = taxRateFor(category);
  const amountNum = parseInt(amount, 10) || 0;
  const headerTaxAmt = amountNum > 0 && taxRate > 0
    ? Math.round((amountNum * taxRate) / (100 + taxRate)) : 0;
  const headerExTax = amountNum - headerTaxAmt;

  const itemsTotal = items.reduce((s, it) => s + it.amount, 0);
  const itemsTaxTotal = items.reduce((s, it) => s + it.tax_amount, 0);
  const hasItems = items.length > 0;
  const totalMatch = !hasItems || amountNum === itemsTotal;

  async function handleAddItem() {
    setItemsBusy(true);
    try {
      const created = await createItem(tx.id, {
        name: "新しい明細", amount: 0, category: null,
        sort_order: items.length,
      });
      setItems([...items, created]);
      // ヘッダ再取得
      const fresh = await getTransaction(tx.id);
      setAmount(String(fresh.amount));
      setCategory(fresh.screening_category || "");
    } catch (e) { setError(String(e)); }
    finally { setItemsBusy(false); }
  }

  async function handleItemChange(
    itemId: number, patch: Partial<TransactionItem>
  ) {
    setItemsBusy(true);
    try {
      await updateItem(tx.id, itemId, patch);
      const fresh = await getTransaction(tx.id);
      setItems(fresh.items || []);
      setAmount(String(fresh.amount));
      setCategory(fresh.screening_category || "");
    } catch (e) { setError(String(e)); }
    finally { setItemsBusy(false); }
  }

  async function handleItemDelete(itemId: number) {
    setItemsBusy(true);
    try {
      await deleteItem(tx.id, itemId);
      const fresh = await getTransaction(tx.id);
      setItems(fresh.items || []);
      setAmount(String(fresh.amount));
      setCategory(fresh.screening_category || "");
    } catch (e) { setError(String(e)); }
    finally { setItemsBusy(false); }
  }

  async function handleSave() {
    setBusy(true); setError(null);
    try {
      await updateTransaction(tx.id, {
        merchant_normalized: merchantNormalized,
        // 明細がある場合はサーバ側で再計算されるので送信不要だが、明示で送る
        screening_category: hasItems ? undefined : (category || null),
        amount: hasItems ? undefined : amountNum,
        purchased_at: purchasedAt,
        memo: memo || null,
        needs_review: needsReview,
        status: "user_confirmed",
      });
      if (registerOverride && category && merchantNormalized) {
        await createOverride(merchantNormalized, category);
      }
      onSaved();
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>取引編集 (ID: {tx.id})</h3>
        <div className="form-grid">
          <label>日付</label>
          <input type="date" value={purchasedAt}
                 onChange={(e) => setPurchasedAt(e.target.value)} />
          <label>店舗(正規化)</label>
          <input type="text" value={merchantNormalized}
                 onChange={(e) => setMerchantNormalized(e.target.value)} />
          <label>主カテゴリ</label>
          <div className="tax-info">
            {hasItems
              ? `${category || "(未分類)"} ※明細から自動`
              : (
                <select value={category} onChange={(e) => setCategory(e.target.value)}>
                  <option value="">(未分類)</option>
                  {CATEGORIES.map((c) => (<option key={c} value={c}>{c}</option>))}
                </select>
              )}
          </div>
          <label>合計金額(税込)</label>
          <div className="tax-info">
            {hasItems
              ? `${amountNum.toLocaleString()}円 ※明細から自動`
              : (
                <input type="number" value={amount}
                       onChange={(e) => setAmount(e.target.value)} />
              )}
          </div>
          <label>税抜換算 (主)</label>
          <div className="tax-info">
            {amountNum > 0
              ? `${headerExTax.toLocaleString()}円 (税額 ${headerTaxAmt.toLocaleString()}円, ${taxRate}%)`
              : "-"}
          </div>
          <label>メモ</label>
          <input type="text" value={memo}
                 onChange={(e) => setMemo(e.target.value)} />
          <label>要確認</label>
          <input type="checkbox" checked={needsReview}
                 onChange={(e) => setNeedsReview(e.target.checked)} />
          <label>この店舗→カテゴリを記憶</label>
          <input type="checkbox" checked={registerOverride}
                 onChange={(e) => setRegisterOverride(e.target.checked)}
                 disabled={!category || !merchantNormalized || hasItems} />
        </div>

        {/* 明細セクション */}
        <div className="items-section">
          <h4>明細 ({items.length}件)</h4>
          {!hasItems && (
            <p className="hint">
              明細を追加するとカテゴリごとの分類ができます。
              明細を追加した瞬間、ヘッダの金額・カテゴリは明細から自動算出されます。
            </p>
          )}
          {items.length > 0 && (
            <table className="items-table">
              <thead>
                <tr>
                  <th>品目</th>
                  <th style={{ width: 90 }}>金額(税込)</th>
                  <th style={{ width: 110 }}>カテゴリ</th>
                  <th style={{ width: 60 }}>税率</th>
                  <th style={{ width: 70 }}>税額</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.map((it) => (
                  <tr key={it.id}>
                    <td>
                      <input
                        type="text" value={it.name}
                        onChange={(e) => setItems(items.map(
                          (x) => x.id === it.id ? { ...x, name: e.target.value } : x
                        ))}
                        onBlur={(e) => handleItemChange(it.id, { name: e.target.value })}
                      />
                    </td>
                    <td>
                      <input
                        type="number" value={it.amount}
                        onChange={(e) => setItems(items.map(
                          (x) => x.id === it.id
                            ? { ...x, amount: parseInt(e.target.value, 10) || 0 }
                            : x
                        ))}
                        onBlur={(e) =>
                          handleItemChange(it.id, { amount: parseInt(e.target.value, 10) || 0 })
                        }
                      />
                    </td>
                    <td>
                      <select
                        value={it.category || ""}
                        onChange={(e) =>
                          handleItemChange(it.id, { category: e.target.value || null })
                        }
                      >
                        <option value="">未分類</option>
                        {CATEGORIES.map((c) => (
                          <option key={c} value={c}>{c}</option>
                        ))}
                      </select>
                    </td>
                    <td>{taxRateFor(it.category)}%</td>
                    <td style={{ textAlign: "right" }}>{it.tax_amount}</td>
                    <td>
                      <button className="danger" onClick={() => handleItemDelete(it.id)}>
                        削除
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <td>合計</td>
                  <td style={{ textAlign: "right" }}><b>{itemsTotal.toLocaleString()}</b></td>
                  <td colSpan={2}></td>
                  <td style={{ textAlign: "right" }}>{itemsTaxTotal.toLocaleString()}</td>
                  <td></td>
                </tr>
              </tfoot>
            </table>
          )}
          <button onClick={handleAddItem} disabled={itemsBusy}>+ 明細を追加</button>
          {!totalMatch && (
            <p className="err">
              ⚠ ヘッダ合計({amountNum.toLocaleString()}円)と明細合計({itemsTotal.toLocaleString()}円)が一致しません
            </p>
          )}
        </div>

        {tx.ocr_raw_text && (
          <details>
            <summary>OCR raw text (参考)</summary>
            <pre>{tx.ocr_raw_text}</pre>
          </details>
        )}
        {error && <p className="err">{error}</p>}
        <div className="actions">
          <button onClick={handleSave} disabled={busy}>保存(確認済にする)</button>
          <button onClick={onClose}>キャンセル</button>
        </div>
      </div>
    </div>
  );
}
EOF

# ===========================================================================
# 7. frontend/src/App.css に items-section 追加
# ===========================================================================
echo "==> frontend/src/App.css (items styles 追加)"
if ! grep -q "items-section" frontend/src/App.css; then
  cat >> frontend/src/App.css <<'EOF'

.items-section { margin-top: 24px; padding-top: 16px; border-top: 1px solid #eee; }
.items-section h4 { margin-top: 0; }
.items-table { width: 100%; border-collapse: collapse; font-size: 0.88em; margin: 8px 0; }
.items-table th, .items-table td { padding: 4px 6px; border-bottom: 1px solid #eee; text-align: left; }
.items-table tfoot td { padding-top: 8px; border-top: 2px solid #d0d7de; }
.items-table input[type=text], .items-table input[type=number], .items-table select {
  width: 100%; padding: 4px 6px; border: 1px solid #d0d7de; border-radius: 4px;
  box-sizing: border-box;
}
.modal { max-width: 720px; }
EOF
fi

# ===========================================================================
# 8. data.db リセット (transaction_items テーブル追加のため)
# ===========================================================================
echo ""
echo "==> reset data.db (transaction_items 追加のため)"
rm -f backend/data.db backend/data.db-journal backend/data.db-wal backend/data.db-shm

# ===========================================================================
# 9. pytest
# ===========================================================================
echo ""
echo "==> backend pytest"
cd backend && uv run pytest -v 2>&1 | tail -40
cd "$REPO"

# ===========================================================================
# 10. server restart
# ===========================================================================
echo ""
echo "==> restart uvicorn (vite は触らない)"
pkill -f uvicorn 2>/dev/null || true
sleep 2
cd backend
nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &
sleep 4
cd "$REPO"

echo ""
echo "==> backend health"
curl -s http://localhost:8000/api/health && echo

echo ""
echo "==> 明細API動作確認"
TX=$(curl -s -X POST http://localhost:8000/api/transactions \
  -H "Content-Type: application/json" \
  -d '{"merchant_raw":"テスト","merchant_normalized":"テスト","amount":0,"purchased_at":"2026-05-17"}')
TX_ID=$(echo "$TX" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
echo "  created transaction id=$TX_ID"

curl -s -X POST http://localhost:8000/api/transactions/$TX_ID/items \
  -H "Content-Type: application/json" \
  -d '{"name":"おにぎり","amount":180,"category":"食費"}' >/dev/null
curl -s -X POST http://localhost:8000/api/transactions/$TX_ID/items \
  -H "Content-Type: application/json" \
  -d '{"name":"ビール","amount":300,"category":"酒類"}' >/dev/null

echo "  items added: おにぎり(食費 180) + ビール(酒類 300)"
echo ""
echo "  ヘッダ再計算結果:"
curl -s http://localhost:8000/api/transactions/$TX_ID | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'    amount = {d[\"amount\"]} (期待 480)')
print(f'    screening_category = {d[\"screening_category\"]} (期待 酒類: 最大金額カテゴリ)')
print(f'    items count = {len(d.get(\"items\", []))}')
for it in d.get('items', []):
    print(f'      - {it[\"name\"]} {it[\"amount\"]}円 [{it[\"category\"]}] 税{it[\"tax_amount\"]}')
"

cat <<EOM

============================================================
C4 セットアップ完了.

変更点:
  - transaction_items テーブル新設
  - 明細CRUD API: GET/POST/PATCH/DELETE /api/transactions/{id}/items
  - ヘッダ自動再計算: 明細追加/編集/削除時、amount + screening_category 自動更新
  - 編集UIに明細セクション追加 (品目/金額/カテゴリ/税率/税額 表)

確認: http://localhost:5173
  → 取引を編集 → 「+ 明細を追加」で行追加
  → 明細のカテゴリ変更で税率自動表示
  → 明細合計がヘッダ金額に同期、最大金額カテゴリが主カテゴリ
============================================================
EOM
