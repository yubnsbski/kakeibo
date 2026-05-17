"""Classifier package."""
from __future__ import annotations
from .classify import (
    AUTO_CONFIDENCE, MANUAL_REVIEW_CONFIDENCE, REVIEW_CONFIDENCE, classify_receipt,
)
from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import (
    CATEGORY_TAX_RATE, Category, ClassificationResult, ReceiptInput, ScreeningLabel,
)

__all__ = [
    "AUTO_CONFIDENCE", "MANUAL_REVIEW_CONFIDENCE", "REVIEW_CONFIDENCE",
    "CATEGORY_TAX_RATE", "Category", "ClassificationResult", "ReceiptInput",
    "ScreeningLabel", "ambiguous_merchants", "classify_receipt",
    "item_keyword_rules", "merchant_rules", "normalize_merchant",
]
