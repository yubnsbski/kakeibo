"""Receipt classifier + line-item classifier."""
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
    """ヘッダ単位の分類 (レシート全体に1カテゴリ)."""
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


# ===== 明細単位分類 (新規) =====

class LineItemClassification:
    """明細1行の分類結果."""
    def __init__(self, item: str, category: Category | None, reason: str):
        self.item = item
        self.category = category
        self.reason = reason

    def dict(self) -> dict:
        return {"item": self.item, "category": self.category, "reason": self.reason}


def _find_merchant_category(merchant_normalized: str) -> Category | None:
    """店舗ルール一致なら返す (理由不要)."""
    for merchant, category in merchant_rules.items():
        if merchant in merchant_normalized:
            return category
    return None


def _find_item_category(item: str) -> tuple[Category, str] | None:
    """品目キーワード一致なら (category, keyword) を返す."""
    for keyword, category in item_keyword_rules.items():
        if keyword in item:
            return (category, keyword)
    return None


def classify_line_items(
    items: list[str], merchant_raw: str,
    user_overrides: dict[str, Category] | None = None,
) -> list[LineItemClassification]:
    """各明細品目を分類.

    優先順位:
        1. ユーザー修正ルール (店舗名一致 → 全明細を override カテゴリ)
        2. アイテムキーワード一致 → そのカテゴリ
        3. 通常店舗 (非曖昧) なら 店舗カテゴリにフォールバック
        4. 曖昧店舗 or 未一致 → None (要確認)

    Returns: 各明細の分類結果リスト
    """
    merchant_normalized = normalize_merchant(merchant_raw)
    is_ambiguous = any(m in merchant_normalized for m in ambiguous_merchants)

    # ユーザー override 優先
    override = _find_user_override(merchant_normalized, user_overrides)

    merchant_category = None if is_ambiguous else _find_merchant_category(merchant_normalized)

    results: list[LineItemClassification] = []
    for item_text in items:
        item_text = item_text.strip()
        if not item_text:
            continue

        # 1. user_override 最優先 (店舗単位なので明細全部に適用)
        if override is not None:
            results.append(LineItemClassification(
                item=item_text, category=override,
                reason=f"user_override: {override}",
            ))
            continue

        # 2. アイテムキーワード判定
        item_match = _find_item_category(item_text)
        if item_match is not None:
            cat, keyword = item_match
            results.append(LineItemClassification(
                item=item_text, category=cat,
                reason=f"item_keyword: {keyword}",
            ))
            continue

        # 3. 通常店舗のフォールバック
        if merchant_category is not None:
            results.append(LineItemClassification(
                item=item_text, category=merchant_category,
                reason=f"merchant_fallback: {merchant_category}",
            ))
            continue

        # 4. 曖昧店舗 or 全く未一致 → None
        results.append(LineItemClassification(
            item=item_text, category=None,
            reason="no_match (要確認)",
        ))
    return results
