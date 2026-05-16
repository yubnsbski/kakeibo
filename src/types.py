"""Classifier types — Python port of src/types.ts.

Field names follow the TypeScript source (camelCase) for direct compatibility
with existing fixtures (fixtures/receipts/*.json). The CSV / DB layer downstream
translates to snake_case per operation-playbook.md §3 contract.
"""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict

Category = Literal[
    "食費",
    "日用品",
    "交通",
    "医療",
    "通信",
    "娯楽",
    "教育",
    "その他",
]

ScreeningLabel = Literal["recordable", "needs_review"]


class ReceiptInput(BaseModel):
    """Input to classify_receipt. Matches TS ReceiptInput exactly."""

    model_config = ConfigDict(populate_by_name=True, extra="ignore")

    merchantRaw: str
    items: list[str] | None = None
    totalAmount: int | None = None
    purchasedAt: str | None = None
    userCategoryOverrides: dict[str, Category] | None = None


class ClassificationResult(BaseModel):
    """Output from classify_receipt. Matches TS ClassificationResult exactly."""

    merchantNormalized: str
    category: Category | None
    confidence: float
    needsReview: bool
    reason: str
    reasons: list[str]
    screeningLabel: ScreeningLabel
