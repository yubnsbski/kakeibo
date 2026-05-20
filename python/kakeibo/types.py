"""Shared type definitions for the kakeibo classifier."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Literal, Optional

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

TaxRateHint = Literal["reduced", "standard"]

ScreeningLabel = Literal["recordable", "needs_review"]


@dataclass(frozen=True)
class ReceiptInput:
    merchant_raw: str
    items: list[str] = field(default_factory=list)
    total_amount: Optional[float] = None
    purchased_at: Optional[str] = None
    user_category_overrides: Optional[dict[str, Category]] = None


@dataclass(frozen=True)
class ClassificationResult:
    merchant_normalized: str
    category: Optional[Category]
    confidence: float
    needs_review: bool
    reason: str
    reasons: list[str]
    screening_label: ScreeningLabel


@dataclass(frozen=True)
class ItemClassification:
    text: str
    category: Optional[Category]
    reason: str
    matched_keyword: Optional[str]


@dataclass(frozen=True)
class ReceiptBreakdown:
    merchant_normalized: str
    items: list[ItemClassification]
    dominant_category: Optional[Category]
    is_mixed: bool
    needs_review: bool


@dataclass(frozen=True)
class CategoryAllocation:
    category: Optional[Category]
    amount: float
    item_texts: list[str]


@dataclass(frozen=True)
class AmountAllocationResult:
    total_amount: float
    allocations: list[CategoryAllocation]
    strategy: Literal["per_item_amounts", "equal_split"]
    unclassified_amount: float
