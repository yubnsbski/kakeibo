from receipt_classifier import ReceiptInput, classify_receipt


def test_merchant_rule_takes_priority_over_item_keyword() -> None:
    result = classify_receipt(
        ReceiptInput(
            merchant_raw="マツモトキヨシ 新宿店",
            items=["おにぎり"],
        )
    )

    assert result.category == "日用品"
    assert result.reason == "rule_match: 日用品"
    assert result.reasons == ["merchant_rule: マツモトキヨシ"]


def test_user_override_is_highest_priority() -> None:
    result = classify_receipt(
        ReceiptInput(
            merchant_raw="Amazon.co.jp",
            items=[],
            user_category_overrides={"Amazon": "通信"},
        )
    )

    assert result.category == "通信"
    assert result.needs_review is False
    assert result.reason == "user_override: 通信"


def test_ambiguous_merchant_without_items_requires_review() -> None:
    result = classify_receipt(ReceiptInput(merchant_raw="楽天市場", items=[]))

    assert result.category is None
    assert result.needs_review is True
    assert result.reasons == ["ambiguous_merchant_no_items"]


def test_item_keyword_rule_when_no_merchant_rule() -> None:
    result = classify_receipt(ReceiptInput(merchant_raw="不明店舗", items=["ガソリン"]))

    assert result.category == "交通"
    assert result.needs_review is False
    assert result.confidence == 0.78
    assert result.reasons == ["item_keyword: ガソリン"]


def test_invalid_user_override_category_is_ignored() -> None:
    result = classify_receipt(
        ReceiptInput(
            merchant_raw="Amazon.co.jp",
            items=[],
            user_category_overrides={"Amazon": "無効カテゴリ"},
        )
    )

    assert result.category is None
    assert result.needs_review is True
    assert result.reasons == ["ambiguous_merchant_no_items"]


def test_ambiguous_merchant_with_items_still_needs_review() -> None:
    result = classify_receipt(ReceiptInput(merchant_raw="Amazon.co.jp", items=["イヤホン"]))

    assert result.category is None
    assert result.needs_review is True
    assert result.reason == "ambiguous merchant requires manual category"
