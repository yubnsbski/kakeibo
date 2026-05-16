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

AMBIGUOUS_MERCHANTS: List[str] = [
    "Amazon",
    "楽天",
    "イオン",
    "ドン・キホーテ",
    "ドンキホーテ",
    "メルカリ",
]

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


@dataclass(frozen=True)
class CategoryScore:
    category: Category
    score: int


@dataclass(frozen=True)
class ClassificationResult:
    merchant_normalized: str
    category: Optional[Category]
    confidence: float
    needs_review: bool
    reason: str
    reasons: List[str]
    scores: List[CategoryScore]


def normalize_merchant(raw: str) -> str:
    text = (
        raw.strip()
        .replace(" ", "")
        .replace("\t", "")
        .replace("\n", "")
    )
    return (
        text.replace("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ", "セブンイレブン")
        .replace("セブン-イレブン", "セブンイレブン")
        .replace("セブンーイレブン", "セブンイレブン")
        .replace("ファミマ", "ファミリーマート")
        .replace("ﾏﾂｷﾖ", "マツモトキヨシ")
        .replace("ドン・キホーテ", "ドンキホーテ")
    )


def _find_user_override(
    merchant_normalized: str,
    user_category_overrides: Optional[Dict[str, Category]],
) -> Optional[Category]:
    if not user_category_overrides:
        return None

    for merchant_key, category in user_category_overrides.items():
        normalized_key = normalize_merchant(merchant_key)
        if not normalized_key:
            continue
        if normalized_key in merchant_normalized:
            return category

    return None


def _to_sorted_scores(score_map: Dict[Category, int]) -> List[CategoryScore]:
    scores = [CategoryScore(category=k, score=v) for k, v in score_map.items() if v > 0]
    return sorted(scores, key=lambda entry: entry.score, reverse=True)


def classify_receipt(
    merchant_raw: str,
    items: Optional[List[str]] = None,
    user_category_overrides: Optional[Dict[str, Category]] = None,
) -> ClassificationResult:
    merchant_normalized = normalize_merchant(merchant_raw)
    item_list = items or []
    reasons: List[str] = []
    score_map: Dict[Category, int] = {}

    user_override = _find_user_override(merchant_normalized, user_category_overrides)
    if user_override:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=user_override,
            confidence=0.99,
            needs_review=False,
            reason=f"user_override: {user_override}",
            reasons=["user_override"],
            scores=[CategoryScore(category=user_override, score=999)],
        )

    for merchant in AMBIGUOUS_MERCHANTS:
        if merchant in merchant_normalized and len(item_list) == 0:
            return ClassificationResult(
                merchant_normalized=merchant_normalized,
                category=None,
                confidence=0.3,
                needs_review=True,
                reason=f"ambiguous merchant: {merchant}",
                reasons=[f"ambiguous_merchant_no_items: {merchant}"],
                scores=[],
            )

    for merchant, category in MERCHANT_RULES.items():
        if merchant in merchant_normalized:
            score_map[category] = score_map.get(category, 0) + MERCHANT_SCORE
            reasons.append(f"merchant_rule: {merchant}")

    for item in item_list:
        for keyword, category in ITEM_KEYWORD_RULES.items():
            if keyword in item:
                score_map[category] = score_map.get(category, 0) + ITEM_SCORE
                reasons.append(f"item_keyword: {keyword}")

    scores = _to_sorted_scores(score_map)
    if len(scores) == 0:
        return ClassificationResult(
            merchant_normalized=merchant_normalized,
            category=None,
            confidence=0.1,
            needs_review=True,
            reason="no rule matched",
            reasons=["no_rule_matched"],
            scores=[],
        )

    best = scores[0]
    second = scores[1] if len(scores) > 1 else None
    total_score = sum(entry.score for entry in scores)
    confidence = min(0.99, round(best.score / total_score, 2))

    is_ambiguous_top = any(m in merchant_normalized for m in AMBIGUOUS_MERCHANTS)
    has_small_margin = (best.score - second.score) < SMALL_MARGIN if second else False
    needs_review = is_ambiguous_top or has_small_margin

    if needs_review:
        reason = (
            "ambiguous merchant requires review"
            if is_ambiguous_top
            else "score margin too small"
        )
        category: Optional[Category] = None
    else:
        reason = f"score_winner: {best.category}"
        category = best.category

    return ClassificationResult(
        merchant_normalized=merchant_normalized,
        category=category,
        confidence=confidence,
        needs_review=needs_review,
        reason=reason,
        reasons=reasons,
        scores=scores,
    )
