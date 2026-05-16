from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional

Category = str
MERCHANT_SCORE = 80
ITEM_SCORE = 50
SMALL_MARGIN = 20

MERCHANT_RULES: Dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通",
    "JR東日本": "交通",
}

AMBIGUOUS_MERCHANTS: List[str] = ["Amazon", "楽天", "イオン", "ドン・キホーテ", "ドンキホーテ", "メルカリ"]

ITEM_KEYWORD_RULES: Dict[str, Category] = {
    "おにぎり": "食費",
    "弁当": "食費",
    "牛乳": "食費",
    "洗剤": "日用品",
    "シャンプー": "日用品",
    "薬": "医療",
    "ガソリン": "交通",
    "本": "教育",
}


@dataclass
class CategoryScore:
    category: Category
    score: int


@dataclass
class ClassificationResult:
    merchant_normalized: str
    category: Optional[Category]
    confidence: float
    needs_review: bool
    reason: str
    reasons: List[str]
    scores: List[CategoryScore]


def normalize_merchant(raw: str) -> str:
    text = "".join(raw.strip().split())
    text = text.replace("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ", "セブンイレブン")
    text = text.replace("セブン-イレブン", "セブンイレブン")
    text = text.replace("セブンーイレブン", "セブンイレブン")
    text = text.replace("ファミマ", "ファミリーマート")
    text = text.replace("ﾏﾂｷﾖ", "マツモトキヨシ")
    text = text.replace("ドン・キホーテ", "ドンキホーテ")
    return text


def classify_receipt(
    merchant_raw: str,
    items: Optional[List[str]] = None,
    user_category_overrides: Optional[Dict[str, Category]] = None,
) -> ClassificationResult:
    merchant_normalized = normalize_merchant(merchant_raw)
    item_list = items or []
    reasons: List[str] = []
    score_map: Dict[Category, int] = {}

    if user_category_overrides:
        for merchant, category in user_category_overrides.items():
            key = normalize_merchant(merchant)
            if key and key in merchant_normalized:
                return ClassificationResult(merchant_normalized, category, 0.99, False, f"user_override: {category}", ["user_override"], [CategoryScore(category, 999)])

    for merchant in AMBIGUOUS_MERCHANTS:
        if merchant in merchant_normalized and not item_list:
            return ClassificationResult(merchant_normalized, None, 0.3, True, f"ambiguous merchant: {merchant}", [f"ambiguous_merchant_no_items: {merchant}"], [])

    for merchant, category in MERCHANT_RULES.items():
        if merchant in merchant_normalized:
            score_map[category] = score_map.get(category, 0) + MERCHANT_SCORE
            reasons.append(f"merchant_rule: {merchant}")

    for item in item_list:
        for keyword, category in ITEM_KEYWORD_RULES.items():
            if keyword in item:
                score_map[category] = score_map.get(category, 0) + ITEM_SCORE
                reasons.append(f"item_keyword: {keyword}")

    scores = sorted([CategoryScore(k, v) for k, v in score_map.items() if v > 0], key=lambda x: x.score, reverse=True)
    if not scores:
        return ClassificationResult(merchant_normalized, None, 0.1, True, "no rule matched", ["no_rule_matched"], [])

    best = scores[0]
    second = scores[1] if len(scores) > 1 else None
    confidence = min(0.99, round(best.score / sum(s.score for s in scores), 2))
    is_ambiguous_top = any(m in merchant_normalized for m in AMBIGUOUS_MERCHANTS)
    has_small_margin = (best.score - second.score) < SMALL_MARGIN if second else False
    needs_review = is_ambiguous_top or has_small_margin

    reason = "ambiguous merchant requires review" if (is_ambiguous_top and needs_review) else "score margin too small" if needs_review else f"score_winner: {best.category}"
    return ClassificationResult(merchant_normalized, None if needs_review else best.category, confidence, needs_review, reason, reasons, scores)
