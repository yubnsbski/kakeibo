from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from typing import Dict, List, Literal, Optional

Category = Literal["食費", "日用品", "交通", "医療", "通信", "娯楽", "教育", "その他"]
CATEGORY_VALUES: set[str] = {"食費", "日用品", "交通", "医療", "通信", "娯楽", "教育", "その他"}

MERCHANT_RULE_CONFIDENCE = 0.92
ITEM_RULE_CONFIDENCE = 0.78
MANUAL_REVIEW_CONFIDENCE = 0.35
REVIEW_CONFIDENCE = 0.0

MERCHANT_RULES: Dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通",
    "JR東日本": "交通",
}

AMBIGUOUS_MERCHANTS = ["Amazon", "楽天", "イオン", "ドンキホーテ", "メルカリ"]

ITEM_KEYWORD_RULES: Dict[str, Category] = {
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
    category: Optional[Category]
    confidence: float
    needs_review: bool
    reason: str
    reasons: List[str]
    screening_label: Literal["recordable", "needs_review"]


def normalize_merchant(raw: str) -> str:
    normalized = unicodedata.normalize("NFKC", raw).strip()
    normalized = normalized.replace("・", "")
    normalized = re.sub(r"\s+", "", normalized)
    normalized = normalized.replace("-", "")
    return normalized


def _find_user_override_category(
    merchant_normalized: str, user_category_overrides: Optional[Dict[str, str]]
) -> Optional[Category]:
    if not user_category_overrides:
        return None

    for merchant, category in user_category_overrides.items():
        normalized_key = normalize_merchant(merchant)
        if normalized_key and normalized_key in merchant_normalized and category in CATEGORY_VALUES:
            return category

    return None


def _match_merchant_rule(merchant_normalized: str) -> Optional[tuple[Category, str]]:
    for merchant, category in MERCHANT_RULES.items():
        if merchant in merchant_normalized:
            return category, f"merchant_rule: {merchant}"
    return None


def _match_item_rule(items: List[str]) -> Optional[tuple[Category, str]]:
    for item in items:
        normalized_item = item.strip()
        if not normalized_item:
            continue
        for keyword, category in ITEM_KEYWORD_RULES.items():
            if keyword in normalized_item:
                return category, f"item_keyword: {keyword}"
    return None


def classify_receipt(input_data: ReceiptInput) -> ClassificationResult:
    merchant_normalized = normalize_merchant(input_data.merchant_raw)
    items = [item for item in (input_data.items or []) if item.strip()]
    is_ambiguous = any(merchant in merchant_normalized for merchant in AMBIGUOUS_MERCHANTS)

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

    category, match_reason = match

    if is_ambiguous:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=MANUAL_REVIEW_CONFIDENCE,
            needs_review=True,
            reason="ambiguous merchant requires manual category",
            reasons=[match_reason, "ambiguous_merchant_with_items"],
            screening_label="needs_review",
        )

    return ClassificationResult(
        merchant_normalized=merchant_normalized,
        category=category,
        confidence=MERCHANT_RULE_CONFIDENCE if merchant_match else ITEM_RULE_CONFIDENCE,
        needs_review=False,
        reason=f"rule_match: {category}",
        reasons=[match_reason],
        screening_label="recordable",
    )
