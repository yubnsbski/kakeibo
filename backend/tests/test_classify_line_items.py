"""明細単位分類のテスト."""
from __future__ import annotations
from app.classifier import classify_line_items


def test_item_keyword_priority():
    """明細キーワード一致が最優先."""
    results = classify_line_items(
        items=["おにぎり", "ビール", "ティッシュ"],
        merchant_raw="不明店舗",
    )
    assert results[0].category == "食費"
    assert results[1].category == "酒類"
    assert results[2].category == "日用品"


def test_merchant_fallback_for_unmatched_items():
    """通常店舗の未一致明細は merchant カテゴリでフォールバック."""
    results = classify_line_items(
        items=["会計調整"],  # キーワード一致なし
        merchant_raw="セブンイレブン渋谷店",
    )
    assert results[0].category == "食費"
    assert "merchant_fallback" in results[0].reason


def test_ambiguous_merchant_no_fallback():
    """危険店舗の未一致明細は None."""
    results = classify_line_items(
        items=["会計調整"],
        merchant_raw="Amazon.co.jp",
    )
    assert results[0].category is None
    assert "no_match" in results[0].reason


def test_ambiguous_merchant_with_keyword_match():
    """危険店舗でも品目キーワード一致は分類成功."""
    results = classify_line_items(
        items=["シャツ"],
        merchant_raw="Amazon.co.jp",
    )
    assert results[0].category == "衣料費"


def test_user_override_applies_all_items():
    """ユーザー修正ルールは全明細に適用."""
    results = classify_line_items(
        items=["不明品目1", "不明品目2"],
        merchant_raw="Amazon.co.jp",
        user_overrides={"Amazon": "娯楽費"},
    )
    assert results[0].category == "娯楽費"
    assert results[1].category == "娯楽費"


def test_mixed_categories_in_one_receipt():
    """1レシート複数カテゴリの混在."""
    results = classify_line_items(
        items=["おにぎり", "ビール", "シャンプー", "シャツ"],
        merchant_raw="イオン",  # 危険店舗
    )
    assert results[0].category == "食費"
    assert results[1].category == "酒類"
    assert results[2].category == "日用品"
    assert results[3].category == "衣料費"


def test_empty_items():
    """明細空."""
    results = classify_line_items(items=[], merchant_raw="セブンイレブン")
    assert results == []


def test_blank_item_strings_skipped():
    """空文字明細はスキップ."""
    results = classify_line_items(
        items=["", "  ", "おにぎり"],
        merchant_raw="不明",
    )
    assert len(results) == 1
    assert results[0].item == "おにぎり"
