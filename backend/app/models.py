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
