from app.classify import classify_receipt

def test_convenience_store_food():
    result = classify_receipt({
        "merchantRaw": "セブンイレブン 渋谷店",
        "items": ["おにぎり", "牛乳"],
        "totalAmount": 620
    })
    assert result["category"] == "食費"
    assert result["needsReview"] is False

def test_ambiguous_without_items_review():
    result = classify_receipt({
        "merchantRaw": "Amazon.co.jp",
        "items": [],
        "totalAmount": 3000
    })
    assert result["category"] is None
    assert result["needsReview"] is True
    assert result["reason"] == "ambiguous merchant without items"

def test_no_rule_review():
    result = classify_receipt({
        "merchantRaw": "未知の店舗",
        "items": ["未知の品目"],
        "totalAmount": 1000
    })
    assert result["category"] is None
    assert result["needsReview"] is True
    assert result["reason"] == "no rule matched"
