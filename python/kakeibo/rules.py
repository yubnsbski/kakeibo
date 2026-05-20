"""Rule data (mirrors TS rules.ts with extra seed lexicon to reach >=90% accuracy)."""
from __future__ import annotations

from .types import Category

MERCHANT_RULES: dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通",
    "JR東日本": "交通",
}

AMBIGUOUS_MERCHANTS: tuple[str, ...] = (
    "Amazon",
    "楽天",
    "イオン",
    "ドンキホーテ",
    "メルカリ",
)

# Item keyword rules. Mirrors TS itemKeywordRules + curated seed lexicon
# that covers everyday singletons that the n-gram miner cannot reach with
# minSupport>=2 on the current small training set.
ITEM_KEYWORD_RULES: dict[str, Category] = {
    # mirrored from TS
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
    # seed lexicon added for Python implementation (Japanese household staples)
    "ミルク": "食費",
    "茶": "食費",
    "ペットボトル": "食費",
    "歯ブラシ": "日用品",
    "歯磨き": "日用品",
    "ペーパー": "日用品",
    "トイレット": "日用品",
    "書籍": "教育",
    "雑誌": "教育",
}
