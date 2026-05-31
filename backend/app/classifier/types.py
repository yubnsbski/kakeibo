"""Classifier types — 9-category system with tax rate."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict

Category = Literal[
    "食費", "酒類", "外食", "日用品",
    "交通費", "医療費", "娯楽費", "衣料費", "その他",
]
ScreeningLabel = Literal["recordable", "needs_review"]

CATEGORY_TAX_RATE: dict[Category, int] = {
    "食費": 8, "酒類": 10, "外食": 10, "日用品": 10,
    "交通費": 10, "医療費": 10, "娯楽費": 10, "衣料費": 10, "その他": 10,
}


class ReceiptInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")
    merchantRaw: str
    items: list[str] | None = None
    totalAmount: int | None = None
    purchasedAt: str | None = None
    userCategoryOverrides: dict[str, Category] | None = None


class ClassificationResult(BaseModel):
    merchantNormalized: str
    category: Category | None
    confidence: float
    needsReview: bool
    reason: str
    reasons: list[str]
    screeningLabel: ScreeningLabel
