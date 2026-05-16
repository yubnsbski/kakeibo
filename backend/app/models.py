"""SQLModel database models.

Column names follow operation-playbook.md §3 CSV contract:
    receipt_id, merchant_normalized, items_text, screening_category,
    needs_review, reason, confidence, amount, purchased_at

Additional fields (id, merchant_raw, memo, receipt_image_id, timestamps)
extend the contract but never replace contract column names.
"""
from __future__ import annotations

from datetime import date, datetime

from sqlmodel import Field, SQLModel


class TransactionBase(SQLModel):
    """Fields shared between DB row, API create, API read."""

    receipt_id: str | None = None
    merchant_raw: str
    merchant_normalized: str
    items_text: str = ""  # `|`-separated per playbook §5
    screening_category: str | None = None
    needs_review: bool = False
    reason: str = ""
    confidence: float = 0.0
    amount: int
    purchased_at: date
    memo: str | None = None
    receipt_image_id: int | None = Field(default=None, foreign_key="receipts.id")


class Transaction(TransactionBase, table=True):
    __tablename__ = "transactions"
    id: int | None = Field(default=None, primary_key=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class TransactionCreate(TransactionBase):
    """Payload for POST /api/transactions."""


class TransactionRead(TransactionBase):
    """Payload for GET /api/transactions/{id} and list responses."""

    id: int
    created_at: datetime
    updated_at: datetime


class TransactionUpdate(SQLModel):
    """Payload for PATCH /api/transactions/{id}. All fields optional."""

    merchant_raw: str | None = None
    merchant_normalized: str | None = None
    items_text: str | None = None
    screening_category: str | None = None
    needs_review: bool | None = None
    reason: str | None = None
    confidence: float | None = None
    amount: int | None = None
    purchased_at: date | None = None
    memo: str | None = None


class Receipt(SQLModel, table=True):
    __tablename__ = "receipts"
    id: int | None = Field(default=None, primary_key=True)
    filename: str
    ocr_text: str | None = None
    status: str = "pending"  # pending | reviewed | linked
    created_at: datetime = Field(default_factory=datetime.utcnow)


class UserCategoryOverride(SQLModel, table=True):
    __tablename__ = "user_category_overrides"
    id: int | None = Field(default=None, primary_key=True)
    merchant_pattern: str = Field(unique=True)
    category: str
    created_at: datetime = Field(default_factory=datetime.utcnow)
