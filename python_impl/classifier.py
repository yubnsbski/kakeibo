from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

AUTO_CONFIDENCE = 0.9
MANUAL_REVIEW_CONFIDENCE = 0.4
REVIEW_CONFIDENCE = 0.0

MERCHANT_RULES: Dict[str, str] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通",
    "JR東日本": "交通",
}

AMBIGUOUS_MERCHANTS = ["Amazon", "楽天", "イオン", "ドンキホーテ", "メルカリ"]

ITEM_KEYWORD_RULES: Dict[str, str] = {
    "おにぎり": "食費",
    "弁当": "食費",
    "牛乳": "食費",
    "洗剤": "日用品",
    "シャンプー": "日用品",
    "薬": "医療",
    "ガソリン": "交通",
    "本": "教育",
    "イヤホン": "通信",
    "充電器": "通信",
    "映画": "娯楽",
}


@dataclass
class ReceiptInput:
    merchant_raw: str
    items: Optional[List[str]] = None
    user_category_overrides: Optional[Dict[str, str]] = None


@dataclass
class ClassificationResult:
    merchant_normalized: str
    category: Optional[str]
    confidence: float
    needs_review: bool
    reason: str
    reasons: List[str]
    screening_label: str


def normalize_merchant(raw: str) -> str:
    text = "".join(raw.strip().split())
    text = text.replace("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ", "セブンイレブン")
    text = text.replace("ｾﾌﾞﾝｲﾚﾌﾞﾝ", "セブンイレブン")
    text = text.replace("セブン-イレブン", "セブンイレブン")
    text = text.replace("セブンーイレブン", "セブンイレブン")
    text = text.replace("ファミマ", "ファミリーマート")
    text = text.replace("ﾏﾂｷﾖ", "マツモトキヨシ")
    text = text.replace("ドン・キホーテ", "ドンキホーテ")
    return text


def sanitize_items(items: Optional[List[str]]) -> List[str]:
    return [item.strip() for item in (items or []) if item.strip()]


def _find_user_override_category(merchant_normalized: str, overrides: Optional[Dict[str, str]]) -> Optional[str]:
    if not overrides:
        return None
    for merchant, category in overrides.items():
        normalized_key = normalize_merchant(merchant)
        if normalized_key and normalized_key in merchant_normalized:
            return category
    return None


def _match_merchant_rule(merchant_normalized: str) -> Optional[tuple[str, str]]:
    for merchant, category in MERCHANT_RULES.items():
        if merchant in merchant_normalized:
            return category, f"merchant_rule: {merchant}"
    return None


def _match_item_rule(items: List[str]) -> Optional[tuple[str, str]]:
    for item in items:
        for keyword, category in ITEM_KEYWORD_RULES.items():
            if keyword in item:
                return category, f"item_keyword: {keyword}"
    return None


def classify_receipt(input_data: ReceiptInput) -> ClassificationResult:
    merchant_normalized = normalize_merchant(input_data.merchant_raw)
    items = sanitize_items(input_data.items)
    is_ambiguous = any(m in merchant_normalized for m in AMBIGUOUS_MERCHANTS)

    override = _find_user_override_category(merchant_normalized, input_data.user_category_overrides)
    if override:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=override,
            confidence=1.0,
            needs_review=False,
            reason=f"user_override: {override}",
            reasons=["user_override"],
            screening_label="recordable",
        )

    if is_ambiguous and not items:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=REVIEW_CONFIDENCE,
            needs_review=True,
            reason="ambiguous merchant without items",
            reasons=["ambiguous_merchant_no_items"],
            screening_label="needs_review",
        )

    merchant_match = _match_merchant_rule(merchant_normalized)
    item_match = None if merchant_match else _match_item_rule(items)
    match = merchant_match or item_match

    if not match:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=REVIEW_CONFIDENCE,
            needs_review=True,
            reason="no rule matched",
            reasons=["no_rule_matched"],
            screening_label="needs_review",
        )

    if is_ambiguous:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=MANUAL_REVIEW_CONFIDENCE,
            needs_review=True,
            reason="ambiguous merchant requires manual category",
            reasons=[match[1], "ambiguous_merchant_with_items"],
            screening_label="needs_review",
        )

    return ClassificationResult(
        merchant_normalized=merchant_normalized,
        category=match[0],
        confidence=AUTO_CONFIDENCE,
        needs_review=False,
        reason=f"rule_match: {match[0]}",
        reasons=[match[1]],
        screening_label="recordable",
    )
