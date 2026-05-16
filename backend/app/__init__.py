"""Classifier package — Python port of the TypeScript classifier in src/.

Public API:
    Category, ClassificationResult, ReceiptInput, ScreeningLabel  - types
    normalize_merchant - merchant name normalization
    classify_receipt - main classification entrypoint
    merchant_rules, ambiguous_merchants, item_keyword_rules - rule tables
"""
from __future__ import annotations

from .classify import (
    AUTO_CONFIDENCE,
    MANUAL_REVIEW_CONFIDENCE,
    REVIEW_CONFIDENCE,
    classify_receipt,
)
from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import (
    Category,
    ClassificationResult,
    ReceiptInput,
    ScreeningLabel,
)

__all__ = [
    "AUTO_CONFIDENCE",
    "MANUAL_REVIEW_CONFIDENCE",
    "REVIEW_CONFIDENCE",
    "Category",
    "ClassificationResult",
    "ReceiptInput",
    "ScreeningLabel",
    "ambiguous_merchants",
    "classify_receipt",
    "item_keyword_rules",
    "merchant_rules",
    "normalize_merchant",
]
