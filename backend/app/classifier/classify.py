"""Receipt classifier."""
from __future__ import annotations
from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import Category, ClassificationResult, ReceiptInput

AUTO_CONFIDENCE = 0.9
MANUAL_REVIEW_CONFIDENCE = 0.4
REVIEW_CONFIDENCE = 0.0


def _find_user_override(merchant_normalized: str, overrides: dict[str, Category] | None) -> Category | None:
    if not overrides:
        return None
    for merchant, category in overrides.items():
        normalized_key = normalize_merchant(merchant)
        if normalized_key and normalized_key in merchant_normalized:
            return category
    return None


def _match_merchant_rule(merchant_normalized: str) -> dict | None:
    for merchant, category in merchant_rules.items():
        if merchant in merchant_normalized:
            return {"category": category, "reason": f"merchant_rule: {merchant}"}
    return None


def _match_item_rule(items: list[str]) -> dict | None:
    for item in items:
        for keyword, category in item_keyword_rules.items():
            if keyword in item:
                return {"category": category, "reason": f"item_keyword: {keyword}"}
    return None


def classify_receipt(input_data: ReceiptInput) -> ClassificationResult:
    merchant_normalized = normalize_merchant(input_data.merchantRaw)
    items = input_data.items or []
    is_ambiguous = any(m in merchant_normalized for m in ambiguous_merchants)

    override = _find_user_override(merchant_normalized, input_data.userCategoryOverrides)
    if override is not None:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=override,
            confidence=1.0, needsReview=False,
            reason=f"user_override: {override}",
            reasons=["user_override"], screeningLabel="recordable",
        )

    if is_ambiguous and len(items) == 0:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=None,
            confidence=REVIEW_CONFIDENCE, needsReview=True,
            reason="ambiguous merchant without items",
            reasons=["ambiguous_merchant_no_items"], screeningLabel="needs_review",
        )

    merchant_match = _match_merchant_rule(merchant_normalized)
    item_match = None if merchant_match else _match_item_rule(items)
    match = merchant_match or item_match

    if match is None:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=None,
            confidence=REVIEW_CONFIDENCE, needsReview=True,
            reason="no rule matched", reasons=["no_rule"], screeningLabel="needs_review",
        )

    if is_ambiguous:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=None,
            confidence=REVIEW_CONFIDENCE, needsReview=True,
            reason="ambiguous merchant requires manual category",
            reasons=["ambiguous_merchant_with_items"], screeningLabel="needs_review",
        )

    return ClassificationResult(
        merchantNormalized=merchant_normalized, category=match["category"],
        confidence=AUTO_CONFIDENCE, needsReview=False,
        reason=f"rule_match: {match['category']}",
        reasons=[match["reason"]], screeningLabel="recordable",
    )
