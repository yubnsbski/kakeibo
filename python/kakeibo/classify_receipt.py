"""Store-level receipt classification (mirror of classifyReceipt.ts)."""
from __future__ import annotations

from typing import Optional

from .normalize_merchant import normalize_merchant
from .rules import AMBIGUOUS_MERCHANTS, ITEM_KEYWORD_RULES, MERCHANT_RULES
from .types import Category, ClassificationResult, ReceiptInput

_AUTO_CONFIDENCE = 0.9
_MANUAL_REVIEW_CONFIDENCE = 0.4
_REVIEW_CONFIDENCE = 0.0


def classify_receipt(input_: ReceiptInput) -> ClassificationResult:
    merchant_normalized = normalize_merchant(input_.merchant_raw)
    items = list(input_.items)
    is_ambiguous = any(m in merchant_normalized for m in AMBIGUOUS_MERCHANTS)

    override = _find_user_override(merchant_normalized, input_.user_category_overrides)
    if override is not None:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=override,
            confidence=1.0,
            needs_review=False,
            reason=f"user_override: {override}",
            reasons=["user_override"],
            screening_label="recordable",
        )

    if is_ambiguous and len(items) == 0:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=_REVIEW_CONFIDENCE,
            needs_review=True,
            reason="ambiguous merchant without items",
            reasons=["ambiguous_merchant_no_items"],
            screening_label="needs_review",
        )

    merchant_match = _match_merchant_rule(merchant_normalized)
    item_match = None if merchant_match else _match_item_rule(items)
    match = merchant_match or item_match

    if match is None:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=_REVIEW_CONFIDENCE,
            needs_review=True,
            reason="no rule matched",
            reasons=["no_rule_matched"],
            screening_label="needs_review",
        )

    category, reason_detail = match

    if is_ambiguous:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=_MANUAL_REVIEW_CONFIDENCE,
            needs_review=True,
            reason="ambiguous merchant requires manual category",
            reasons=[reason_detail, "ambiguous_merchant_with_items"],
            screening_label="needs_review",
        )

    return ClassificationResult(
        merchant_normalized=merchant_normalized,
        category=category,
        confidence=_AUTO_CONFIDENCE,
        needs_review=False,
        reason=f"rule_match: {category}",
        reasons=[reason_detail],
        screening_label="recordable",
    )


def _find_user_override(
    merchant_normalized: str,
    overrides: Optional[dict[str, Category]],
) -> Optional[Category]:
    if not overrides:
        return None
    for merchant, category in overrides.items():
        normalized_key = normalize_merchant(merchant)
        if normalized_key and normalized_key in merchant_normalized:
            return category
    return None


def _match_merchant_rule(
    merchant_normalized: str,
) -> Optional[tuple[Category, str]]:
    for merchant, category in MERCHANT_RULES.items():
        if merchant in merchant_normalized:
            return category, f"merchant_rule: {merchant}"
    return None


def _match_item_rule(items: list[str]) -> Optional[tuple[Category, str]]:
    for item in items:
        for keyword, category in ITEM_KEYWORD_RULES.items():
            if keyword in item:
                return category, f"item_keyword: {keyword}"
    return None
