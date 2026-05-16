"""Classifier package — Python port of the TypeScript classifier in src/.

Public API (current):
    Category, ClassificationResult, ReceiptInput, ScreeningLabel  - types
    normalize_merchant - merchant name normalization
    merchant_rules, ambiguous_merchants, item_keyword_rules - rule tables

To be added (next iteration):
    classify_receipt - main classification entrypoint
"""
from __future__ import annotations

from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import (
    Category,
    ClassificationResult,
    ReceiptInput,
    ScreeningLabel,
)

__all__ = [
    "Category",
    "ClassificationResult",
    "ReceiptInput",
    "ScreeningLabel",
    "ambiguous_merchants",
    "item_keyword_rules",
    "merchant_rules",
    "normalize_merchant",
]
