"""Tests for classify_receipt — 9-category system."""
from __future__ import annotations
from app.classifier import ReceiptInput, classify_receipt


def test_seven_eleven_classified_as_food():
    r = classify_receipt(ReceiptInput(merchantRaw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
                                        items=["おにぎり", "牛乳"], totalAmount=620))
    assert r.category == "食費"
    assert r.needsReview is False


def test_amazon_without_items_needs_review():
    r = classify_receipt(ReceiptInput(merchantRaw="Amazon.co.jp", items=[], totalAmount=3000))
    assert r.category is None
    assert r.needsReview is True


def test_beer_classified_as_liquor():
    r = classify_receipt(ReceiptInput(merchantRaw="酒屋", items=["ビール"], totalAmount=500))
    assert r.category == "酒類"


def test_shirt_classified_as_clothing():
    r = classify_receipt(ReceiptInput(merchantRaw="アパレル店", items=["シャツ"], totalAmount=3000))
    assert r.category == "衣料費"


def test_no_rule_match_needs_review():
    r = classify_receipt(ReceiptInput(merchantRaw="未知の店舗", items=["未知"], totalAmount=1000))
    assert r.category is None
    assert r.needsReview is True


# === TS legacy から移植したキーワードのテスト ===

def test_tissue_classified_as_daily_goods():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["ティッシュ"], totalAmount=300))
    assert r.category == "日用品"
    assert r.reasons == ["item_keyword: ティッシュ"]


def test_toilet_paper_classified_as_daily_goods():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["トイレットペーパー"], totalAmount=400))
    assert r.category == "日用品"


def test_train_classified_as_transport():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["電車"], totalAmount=180))
    assert r.category == "交通費"
    assert r.reasons == ["item_keyword: 電車"]


def test_bus_classified_as_transport():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["バス"], totalAmount=210))
    assert r.category == "交通費"
