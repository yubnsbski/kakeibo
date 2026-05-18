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
