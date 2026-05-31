"""CSV取込テスト (マイナス金額 + カテゴリ拡張対応)."""
from __future__ import annotations
from app.csv_import import EXPECTED_HEADER, parse_csv, validate_all, normalize_category


def _make_csv(*rows: str) -> str:
    return EXPECTED_HEADER + "\n" + "\n".join(rows)


def test_negative_amount_expense():
    """負数 → expense + abs(amount)."""
    csv = _make_csv("2026-05-15,-620,食費,セブン")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].tx_type == "expense"
    assert rows[0].amount == 620


def test_positive_amount_income():
    """正数 → income."""
    csv = _make_csv("2026-05-15,250000,給与,会社")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].tx_type == "income"
    assert rows[0].amount == 250000


def test_zero_amount_invalid():
    csv = _make_csv("2026-05-15,0,食費,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_amount"


def test_category_alias_娯楽():
    """娯楽 → 娯楽費."""
    csv = _make_csv("2026-05-15,-1000,娯楽,本")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "娯楽費"
    assert rows[0].category_raw == "娯楽"


def test_category_alias_医療():
    csv = _make_csv("2026-05-15,-1000,医療,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].category == "医療費"


def test_new_category_家賃():
    """家賃が既知カテゴリとして通る."""
    csv = _make_csv("2026-05-15,-85000,家賃,5月分")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "家賃"


def test_new_category_光熱費():
    csv = _make_csv("2026-05-15,-12500,光熱費,電気代")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "光熱費"


def test_new_category_通信費():
    csv = _make_csv("2026-05-15,-8900,通信費,スマホ")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "通信費"


def test_income_alias_収入():
    """収入 → 給与 (デフォルト)."""
    csv = _make_csv("2026-05-15,250000,収入,給与")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "給与"
    assert rows[0].tx_type == "income"


def test_income_alias_副業():
    csv = _make_csv("2026-05-15,30000,副業,フリーランス")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].category == "副収入"


def test_unknown_category_kept():
    """不明カテゴリは unknown_category エラー (空欄で取込)."""
    csv = _make_csv("2026-05-15,-500,謎,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "unknown_category"


def test_comma_amount():
    """カンマ区切り 1,200 → 1200."""
    csv = _make_csv('"2026-05-15","-1,200","食費","ランチ"')
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].amount == 1200
    assert rows[0].tx_type == "expense"


def test_normalize_category_function():
    """normalize_category 関数の単体テスト."""
    assert normalize_category("食費") == "食費"
    assert normalize_category("娯楽") == "娯楽費"
    assert normalize_category("不明XX") == "不明XX"
    assert normalize_category("") == ""
    assert normalize_category("  食費  ") == "食費"
