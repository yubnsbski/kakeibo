from __future__ import annotations

from dataclasses import dataclass
from typing import Dict, List, Optional, Tuple

import streamlit as st

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
    text = raw.strip().replace(" ", "").replace("\t", "").replace("\n", "")
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


def parse_items(items_text: str) -> List[str]:
    return [line.strip() for line in items_text.splitlines() if line.strip()]


def parse_user_overrides(overrides_text: str) -> Tuple[Dict[str, Category], List[str]]:
    """
    入力形式:
    セブンイレブン=日用品
    Amazon=仕事
    """
    overrides: Dict[str, Category] = {}
    errors: List[str] = []

    for line_number, raw_line in enumerate(overrides_text.splitlines(), start=1):
        line = raw_line.strip()
        if not line:
            continue

        if "=" not in line:
            errors.append(f"{line_number}行目: '=' がありません: {line}")
            continue

        merchant, category = [part.strip() for part in line.split("=", 1)]
        if not merchant or not category:
            errors.append(f"{line_number}行目: 店舗名またはカテゴリが空です: {line}")
            continue

        overrides[merchant] = category

    return overrides, errors


def render_rule_tables() -> None:
    st.sidebar.header("分類ルール")

    st.sidebar.subheader("店舗ルール")
    st.sidebar.dataframe(
        [{"店舗": merchant, "カテゴリ": category} for merchant, category in MERCHANT_RULES.items()],
        hide_index=True,
        use_container_width=True,
    )

    st.sidebar.subheader("曖昧店舗")
    st.sidebar.dataframe(
        [{"店舗": merchant} for merchant in AMBIGUOUS_MERCHANTS],
        hide_index=True,
        use_container_width=True,
    )

    st.sidebar.subheader("明細キーワード")
    st.sidebar.dataframe(
        [{"キーワード": keyword, "カテゴリ": category} for keyword, category in ITEM_KEYWORD_RULES.items()],
        hide_index=True,
        use_container_width=True,
    )


def render_result(result: ClassificationResult) -> None:
    category_label = result.category if result.category else "要確認"

    col1, col2, col3 = st.columns(3)
    col1.metric("分類カテゴリ", category_label)
    col2.metric("信頼度", f"{result.confidence:.2f}")
    col3.metric("レビュー要否", "必要" if result.needs_review else "不要")

    st.subheader("判定結果")
    st.write(
        {
            "正規化店舗名": result.merchant_normalized,
            "カテゴリ": result.category,
            "レビュー要否": result.needs_review,
            "代表理由": result.reason,
        }
    )

    st.subheader("判定理由")
    if result.reasons:
        st.write(result.reasons)
    else:
        st.write("理由なし")

    st.subheader("スコア")
    if result.scores:
        st.dataframe(
            [{"カテゴリ": score.category, "スコア": score.score} for score in result.scores],
            hide_index=True,
            use_container_width=True,
        )
    else:
        st.info("スコアはありません。")


def main() -> None:
    st.set_page_config(
        page_title="家計簿レシート分類デモ",
        page_icon="🧾",
        layout="wide",
    )

    st.title("家計簿レシート分類デモ")
    st.caption("OCR後の店舗名・明細テキストを入力し、カテゴリ・信頼度・レビュー要否を表示します。")

    render_rule_tables()

    with st.form("receipt_classification_form"):
        merchant_raw = st.text_input(
            "店舗名",
            value="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
            help="OCR後の店舗名を入力します。",
        )

        items_text = st.text_area(
            "明細（1行1品目）",
            value="おにぎり\n牛乳",
            height=140,
            help="レシート明細を1行ずつ入力します。空でも分類できます。",
        )

        overrides_text = st.text_area(
            "ユーザー補正ルール（任意 / 1行: 店舗=カテゴリ）",
            value="",
            height=100,
            help="例: Amazon=仕事",
        )

        submitted = st.form_submit_button("分類する")

    if not submitted:
        st.info("店舗名と明細を入力し、「分類する」を押してください。")
        return

    items = parse_items(items_text)
    user_overrides, override_errors = parse_user_overrides(overrides_text)

    if override_errors:
        st.warning("ユーザー補正ルールに不備があります。該当行は無視されます。")
        for error in override_errors:
            st.write(f"- {error}")

    result = classify_receipt(
        merchant_raw=merchant_raw,
        items=items,
        user_category_overrides=user_overrides,
    )

    render_result(result)


if __name__ == "__main__":
    main()
