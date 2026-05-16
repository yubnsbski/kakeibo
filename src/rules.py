"""Classification rule tables — Python port of src/rules.ts.

These tables are authoritative for rule-based classification. Adding entries
here is the standard way to expand classifier coverage. Keep entries sorted
by category for readability when growing the lists.
"""
from __future__ import annotations

from .types import Category

# Merchant name → category. Substring match; first hit wins (insertion order).
merchant_rules: dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通",
    "JR東日本": "交通",
}

# Ambiguous merchants: never classified by merchant name alone. If no items,
# result becomes needs_review (per docs/classification-policy.md).
ambiguous_merchants: list[str] = [
    "Amazon",
    "楽天",
    "イオン",
    "ドンキホーテ",
    "メルカリ",
]

# Item keyword → category. Used when merchant rule does not match, or as a
# secondary signal for ambiguous merchants.
item_keyword_rules: dict[str, Category] = {
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
