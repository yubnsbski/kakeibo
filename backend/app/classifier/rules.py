"""Classification rule tables — 9-category system, merged with TS legacy."""
from __future__ import annotations
from .types import Category

merchant_rules: dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通費",
    "JR東日本": "交通費",
}

# Note: ドン・キホーテ (中黒入り) も含める. normalize_merchant で中黒は除去されるが、
# 原文マッチ用に表記揺れも保持.
ambiguous_merchants: list[str] = [
    "Amazon", "楽天", "イオン", "ドンキホーテ", "メルカリ",
]

item_keyword_rules: dict[str, Category] = {
    # 食費
    "おにぎり": "食費",
    "弁当": "食費",
    "牛乳": "食費",
    "パン": "食費",
    # 酒類
    "ビール": "酒類",
    "ワイン": "酒類",
    "日本酒": "酒類",
    "チューハイ": "酒類",
    # 日用品 (TS legacy から移植: ティッシュ, トイレットペーパー)
    "洗剤": "日用品",
    "シャンプー": "日用品",
    "歯ブラシ": "日用品",
    "ティッシュ": "日用品",
    "トイレットペーパー": "日用品",
    # 医療費
    "薬": "医療費",
    # 交通費 (TS legacy から移植: バス, 電車)
    "ガソリン": "交通費",
    "バス": "交通費",
    "電車": "交通費",
    # 娯楽費
    "本": "娯楽費",
    "映画": "娯楽費",
    # 衣料費
    "シャツ": "衣料費",
    "靴": "衣料費",
}
