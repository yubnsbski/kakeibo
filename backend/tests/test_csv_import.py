"""CSV取込ロジックのテスト (新列契約: date,amount,category,memo)."""
from __future__ import annotations

from app.csv_import import EXPECTED_HEADER, parse_csv, validate_all


def _make_csv(*rows: str) -> str:
    return EXPECTED_HEADER + "\n" + "\n".join(rows)


def test_parse_valid_csv():
    csv = _make_csv(
        "2026-05-15,620,食費,セブンイレブン",
        "2026-05-16,480,日用品,マツモトキヨシ",
    )
    result = parse_csv(csv)
    assert result.header_error is None
    assert len(result.rows) == 2
    assert result.rows[0].date == "2026-05-15"
    assert result.rows[0].amount == 620
    assert result.rows[0].category == "食費"
    assert result.rows[0].memo == "セブンイレブン"


def test_invalid_header():
    result = parse_csv("foo,bar,baz\n1,2,3")
    assert result.header_error is not None
    assert "invalid CSV header" in result.header_error


def test_validate_missing_date():
    csv = _make_csv(",500,食費,メモ")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "missing_date"


def test_validate_invalid_date_format():
    csv = _make_csv("2026/05/15,500,食費,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "missing_date"


def test_validate_invalid_date_value():
    csv = _make_csv("2026-02-30,500,食費,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "missing_date"


def test_validate_invalid_amount():
    csv = _make_csv("2026-05-15,0,食費,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_amount"

    csv = _make_csv("2026-05-15,abc,食費,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_amount"


def test_validate_unknown_category():
    csv = _make_csv("2026-05-15,500,謎カテゴリ,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "unknown_category"


def test_validate_empty_category_ok():
    csv = _make_csv("2026-05-15,500,,メモ")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == ""


def test_validate_pass():
    csv = _make_csv("2026-05-15,620,食費,セブン")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
