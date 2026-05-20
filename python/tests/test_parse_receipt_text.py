import unittest
from pathlib import Path

from kakeibo.allocate_amounts import AllocateOptions, allocate_amounts_by_category
from kakeibo.classify_breakdown import BreakdownOptions, classify_receipt_breakdown
from kakeibo.parse_receipt_text import ParsedReceipt, parse_receipt_text


FIXTURE_PATH = (
    Path(__file__).resolve().parents[2]
    / "fixtures"
    / "receipts"
    / "raw"
    / "familymart_2026-05-04.txt"
)


def _load_fixture() -> str:
    return FIXTURE_PATH.read_text(encoding="utf-8")


class ParseReceiptTextTests(unittest.TestCase):
    def test_familymart_fixture_parses_all_fields(self):
        parsed = parse_receipt_text(_load_fixture())
        self.assertIsInstance(parsed, ParsedReceipt)
        self.assertEqual(parsed.receipt_input.merchant_raw, "FamilyMart")
        self.assertEqual(parsed.receipt_input.purchased_at, "2026-05-04")
        self.assertEqual(parsed.receipt_input.total_amount, 408)
        self.assertEqual(
            parsed.receipt_input.items,
            ["ミルクの束縛ミルクCO", "雑誌書籍"],
        )
        self.assertEqual(parsed.per_item_amounts, [248, 180])
        self.assertEqual(parsed.per_item_tax_rate_hints, ["reduced", "standard"])

    def test_missing_date_is_none(self):
        text = (
            "FamilyMart\n"
            "ミルクの束縛ミルクCO    ¥248軽\n"
            "合 計                    ¥248\n"
        )
        parsed = parse_receipt_text(text)
        self.assertIsNone(parsed.receipt_input.purchased_at)
        self.assertEqual(parsed.receipt_input.total_amount, 248)
        self.assertEqual(parsed.receipt_input.items, ["ミルクの束縛ミルクCO"])

    def test_missing_total_is_none(self):
        text = (
            "FamilyMart\n"
            "2026年 5月 4日 (月) 12:24\n"
            "ミルクの束縛ミルクCO    ¥248軽\n"
        )
        parsed = parse_receipt_text(text)
        self.assertIsNone(parsed.receipt_input.total_amount)
        self.assertEqual(parsed.receipt_input.purchased_at, "2026-05-04")
        self.assertEqual(parsed.receipt_input.items, ["ミルクの束縛ミルクCO"])

    def test_discount_line_is_excluded_from_items(self):
        parsed = parse_receipt_text(_load_fixture())
        for item_text in parsed.receipt_input.items:
            self.assertNotIn("値下", item_text)
        self.assertEqual(len(parsed.receipt_input.items), 2)

    def test_paren_lines_are_excluded_from_items(self):
        text = (
            "FamilyMart\n"
            "ミルクの束縛ミルクCO    ¥248軽\n"
            "(商品合計                ¥428)\n"
            "(値引合計                 -20)\n"
            "( 10% 対象               ¥180)\n"
            "  (内消費税等              ¥16)\n"
            "雑誌書籍                  ¥180\n"
        )
        parsed = parse_receipt_text(text)
        self.assertEqual(
            parsed.receipt_input.items,
            ["ミルクの束縛ミルクCO", "雑誌書籍"],
        )
        for item_text in parsed.receipt_input.items:
            self.assertFalse(item_text.startswith("("))

    def test_empty_input_returns_empty_parsed_receipt(self):
        parsed = parse_receipt_text("")
        self.assertEqual(parsed.receipt_input.merchant_raw, "")
        self.assertEqual(parsed.receipt_input.items, [])
        self.assertIsNone(parsed.receipt_input.total_amount)
        self.assertIsNone(parsed.receipt_input.purchased_at)
        self.assertEqual(parsed.per_item_amounts, [])
        self.assertEqual(parsed.per_item_tax_rate_hints, [])

    def test_whitespace_only_input_returns_empty_parsed_receipt(self):
        parsed = parse_receipt_text("   \n\n  \t  \n")
        self.assertEqual(parsed.receipt_input.items, [])
        self.assertEqual(parsed.per_item_amounts, [])
        self.assertEqual(parsed.per_item_tax_rate_hints, [])


class ParseReceiptTextIntegrationTests(unittest.TestCase):
    def test_classify_receipt_breakdown_with_parsed_hints(self):
        parsed = parse_receipt_text(_load_fixture())
        breakdown = classify_receipt_breakdown(
            parsed.receipt_input,
            BreakdownOptions(per_item_tax_rate_hints=parsed.per_item_tax_rate_hints),
        )
        self.assertEqual(len(breakdown.items), 2)
        self.assertEqual(breakdown.items[0].category, "食費")
        self.assertEqual(breakdown.items[1].category, "教育")

    def test_allocate_amounts_with_parsed_amounts(self):
        parsed = parse_receipt_text(_load_fixture())
        breakdown = classify_receipt_breakdown(
            parsed.receipt_input,
            BreakdownOptions(per_item_tax_rate_hints=parsed.per_item_tax_rate_hints),
        )
        result = allocate_amounts_by_category(
            breakdown,
            total_amount=parsed.receipt_input.total_amount,
            options=AllocateOptions(per_item_amounts=parsed.per_item_amounts),
        )
        by_category = {alloc.category: alloc.amount for alloc in result.allocations}
        self.assertEqual(by_category.get("食費"), 248)
        self.assertEqual(by_category.get("教育"), 180)


if __name__ == "__main__":
    unittest.main()
