"""OCR 明細抽出ロジックのテスト."""
from __future__ import annotations
from app.ocr.extract import extract_receipt_fields


def test_extract_line_items_with_amounts():
    raw = """セブンイレブン渋谷店
2026/05/15
おにぎり        130
パン            150
牛乳            180
ティッシュ      250
小計           710
税             56
合計           766
"""
    fields = extract_receipt_fields(raw)
    assert fields.total_amount == 766
    # 明細4件、すべて金額付き
    amounts = {it.name.split()[0] if it.name else "": it.amount for it in fields.line_items}
    # 一部だけ確認 (正規化やスペースは曖昧)
    line_amounts = [it.amount for it in fields.line_items if it.amount is not None]
    assert 130 in line_amounts
    assert 180 in line_amounts


def test_excludes_total_and_tax_lines():
    raw = """店名
おにぎり 100
小計 100
税 8
合計 108
"""
    fields = extract_receipt_fields(raw)
    # 小計/税/合計は明細から除外される
    names = [it.name for it in fields.line_items]
    assert not any("合計" in n for n in names)
    assert not any("小計" in n for n in names)
    assert not any(n == "税" for n in names)
    # おにぎり 100 は残る
    found = any("おにぎり" in it.name and it.amount == 100 for it in fields.line_items)
    assert found, f"おにぎり 100 が見つからない: {[(it.name, it.amount) for it in fields.line_items]}"


def test_line_without_amount_kept_as_name_only():
    raw = """店名
おにぎり
パン 150
"""
    fields = extract_receipt_fields(raw)
    # 「おにぎり」は金額なし、None で残る
    no_amount = [it for it in fields.line_items if it.amount is None]
    assert any("おにぎり" in it.name for it in no_amount)
    # 「パン 150」は金額あり
    with_amount = [it for it in fields.line_items if it.amount == 150]
    assert any("パン" in it.name for it in with_amount)


def test_amount_with_yen_symbol():
    raw = """店名
ビール ¥350
ワイン ¥1,200
"""
    fields = extract_receipt_fields(raw)
    amounts = [it.amount for it in fields.line_items if it.amount is not None]
    assert 350 in amounts
    assert 1200 in amounts


def test_compat_items_list_returns_names():
    raw = """店名
おにぎり 130
牛乳 180
"""
    fields = extract_receipt_fields(raw)
    # items (互換) は品目名のみ
    assert "おにぎり" in " ".join(fields.items)
    assert "牛乳" in " ".join(fields.items)
