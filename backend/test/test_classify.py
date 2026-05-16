"""Tests for classify_receipt — port of tests/classifyReceipt.test.ts.

All 7 original test cases preserved with identical inputs and assertions.
Test names use the Japanese descriptions from the TS source as docstrings.
"""
from __future__ import annotations

from app.classifier import ReceiptInput, classify_receipt


def test_seven_eleven_classified_as_food():
    """セブンイレブンは食費に分類する"""
    result = classify_receipt(
        ReceiptInput(
            merchantRaw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
            items=["おにぎり", "牛乳"],
            totalAmount=620,
        )
    )
    assert result.category == "食費"
    assert result.needsReview is False
    assert "merchant_rule: セブンイレブン" in result.reasons
    assert result.screeningLabel == "recordable"


def test_merchant_rule_takes_priority_over_item_keyword():
    """店舗名ルールは明細キーワードより優先される"""
    result = classify_receipt(
        ReceiptInput(
            merchantRaw="マツモトキヨシ 新宿店",
            items=["おにぎり"],
            totalAmount=480,
        )
    )
    assert result.category == "日用品"
    assert result.reason == "rule_match: 日用品"
    assert result.reasons == ["merchant_rule: マツモトキヨシ"]


def test_user_override_has_highest_priority():
    """ユーザー修正ルールを最優先で適用する"""
    result = classify_receipt(
        ReceiptInput(
            merchantRaw="Amazon.co.jp",
            items=[],
            userCategoryOverrides={"Amazon": "通信"},
            totalAmount=3000,
        )
    )
    assert result.category == "通信"
    assert result.needsReview is False
    assert result.reason == "user_override: 通信"


def test_item_keyword_classification_when_no_merchant_rule():
    """店舗名ルールがない場合は明細キーワードで分類する"""
    result = classify_receipt(
        ReceiptInput(
            merchantRaw="不明店舗",
            items=["ガソリン"],
            totalAmount=3000,
        )
    )
    assert result.category == "交通"
    assert result.needsReview is False
    assert result.reasons == ["item_keyword: ガソリン"]


def test_amazon_without_items_needs_review():
    """Amazonは明細なしなら要確認にする"""
    result = classify_receipt(
        ReceiptInput(
            merchantRaw="Amazon.co.jp",
            items=[],
            totalAmount=3000,
        )
    )
    assert result.category is None
    assert result.needsReview is True
    assert result.reasons == ["ambiguous_merchant_no_items"]
    assert result.screeningLabel == "needs_review"


def test_amazon_with_items_still_needs_review():
    """Amazonは明細ありでも手動分類前提なので要確認"""
    result = classify_receipt(
        ReceiptInput(
            merchantRaw="Amazon.co.jp",
            items=["イヤホン"],
            totalAmount=3000,
        )
    )
    assert result.category is None
    assert result.needsReview is True
    assert result.reason == "ambiguous merchant requires manual category"


def test_no_rule_match_needs_review():
    """分類ルールがなければ要確認"""
    result = classify_receipt(
        ReceiptInput(
            merchantRaw="未知の店舗",
            items=["未知の品目"],
            totalAmount=1000,
        )
    )
    assert result.category is None
    assert result.needsReview is True
    assert result.reason == "no rule matched"
    assert result.screeningLabel == "needs_review"
