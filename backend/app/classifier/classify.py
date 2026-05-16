"""Receipt classifier — Python port of src/classifyReceipt.ts.

The behavioral contract is fixed by tests/classifyReceipt.test.ts (7 cases)
and fixtures/receipts/{basic,evaluation}.json. The decision tree below
satisfies all of those without exception:

    1. user_override                → recordable, confidence 1.0
    2. ambiguous merchant + no items → needs_review, category null
    3. no rule matched              → needs_review, category null
    4. ambiguous merchant + items   → needs_review, category null
       (items don't override the ambiguous flag — see test 6)
    5. normal match                 → recordable, confidence 0.9

Constants AUTO_CONFIDENCE / MANUAL_REVIEW_CONFIDENCE / REVIEW_CONFIDENCE
mirror the TypeScript source.
"""
from __future__ import annotations

from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import Category, ClassificationResult, ReceiptInput

AUTO_CONFIDENCE = 0.9
MANUAL_REVIEW_CONFIDENCE = 0.4
REVIEW_CONFIDENCE = 0.0


def _find_user_override(
    merchant_normalized: str,
    overrides: dict[str, Category] | None,
) -> Category | None:
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
    """Classify a receipt input into a category with confidence and review flag.

    Decision order is fixed; see module docstring.
    """
    merchant_normalized = normalize_merchant(input_data.merchantRaw)
    items = input_data.items or []
    is_ambiguous = any(m in merchant_normalized for m in ambiguous_merchants)

    # 1. user override (highest priority)
    override = _find_user_override(merchant_normalized, input_data.userCategoryOverrides)
    if override is not None:
        return ClassificationResult(
            merchantNormalized=merchant_normalized,
            category=override,
            confidence=1.0,
            needsReview=False,
            reason=f"user_override: {override}",
            reasons=["user_override"],
            screeningLabel="recordable",
        )

    # 2. ambiguous merchant with no items → needs_review
    if is_ambiguous and len(items) == 0:
        return ClassificationResult(
            merchantNormalized=merchant_normalized,
            category=None,
            confidence=REVIEW_CONFIDENCE,
            needsReview=True,
            reason="ambiguous merchant without items",
            reasons=["ambiguous_merchant_no_items"],
            screeningLabel="needs_review",
        )

    # 3. try merchant rule, fall back to item rule
    merchant_match = _match_merchant_rule(merchant_normalized)
    item_match = None if merchant_match else _match_item_rule(items)
    match = merchant_match or item_match

    # 4. no match → needs_review
    if match is None:
        return ClassificationResult(
            merchantNormalized=merchant_normalized,
            category=None,
            confidence=REVIEW_CONFIDENCE,
            needsReview=True,
            reason="no rule matched",
            reasons=["no_rule"],
            screeningLabel="needs_review",
        )

    # 5. ambiguous merchant with items → still needs_review (test 6 contract)
    if is_ambiguous:
        return ClassificationResult(
            merchantNormalized=merchant_normalized,
            category=None,
            confidence=REVIEW_CONFIDENCE,
            needsReview=True,
            reason="ambiguous merchant requires manual category",
            reasons=["ambiguous_merchant_with_items"],
            screeningLabel="needs_review",
        )

    # 6. normal match → recordable
    return ClassificationResult(
        merchantNormalized=merchant_normalized,
        category=match["category"],
        confidence=AUTO_CONFIDENCE,
        needsReview=False,
        reason=f"rule_match: {match['category']}",
        reasons=[match["reason"]],
        screeningLabel="recordable",
    )
