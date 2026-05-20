import unittest

from kakeibo.classify_breakdown import (
    BreakdownOptions,
    classify_receipt_breakdown,
    summarize_items_by_category,
)
from kakeibo.types import ReceiptInput


class ClassifyReceiptBreakdownTests(unittest.TestCase):
    def test_familymart_mixed_receipt(self):
        result = classify_receipt_breakdown(
            ReceiptInput(
                merchant_raw="FamilyMart 船橋海神二丁目店",
                items=["ミルクの束縛ミルクCO", "雑誌書籍"],
                total_amount=408,
                purchased_at="2026-05-04",
            )
        )
        self.assertEqual(len(result.items), 2)
        self.assertEqual(result.items[0].category, "食費")
        self.assertEqual(result.items[1].category, "教育")
        self.assertTrue(result.is_mixed)
        self.assertIsNone(result.dominant_category)
        self.assertTrue(result.needs_review)

    def test_uniform_category(self):
        result = classify_receipt_breakdown(
            ReceiptInput(
                merchant_raw="セブンイレブン 渋谷店",
                items=["おにぎり鮭", "おにぎり梅", "牛乳1L"],
                total_amount=800,
            )
        )
        self.assertEqual(result.dominant_category, "食費")
        self.assertFalse(result.is_mixed)
        self.assertFalse(result.needs_review)

    def test_unclassified_item_triggers_review(self):
        result = classify_receipt_breakdown(
            ReceiptInput(
                merchant_raw="セブンイレブン",
                items=["おにぎり鮭", "謎の物体"],
            )
        )
        self.assertIsNone(result.items[1].category)
        self.assertTrue(result.needs_review)

    def test_empty_items(self):
        result = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="Amazon.co.jp", total_amount=3000)
        )
        self.assertEqual(result.items, [])
        self.assertIsNone(result.dominant_category)
        self.assertTrue(result.needs_review)

    def test_merchant_normalized_passes_through(self):
        result = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店", items=["おにぎり"])
        )
        self.assertIn("セブンイレブン", result.merchant_normalized)

    def test_tax_rate_hint_per_item(self):
        result = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="FamilyMart", items=["未知の食品X", "雑誌書籍"]),
            BreakdownOptions(per_item_tax_rate_hints=["reduced", "standard"]),
        )
        self.assertEqual(result.items[0].category, "食費")
        self.assertEqual(result.items[0].reason, "tax_rate_hint: reduced→食費")
        self.assertEqual(result.items[1].category, "教育")

    def test_tax_rate_hint_length_mismatch_raises(self):
        with self.assertRaises(ValueError):
            classify_receipt_breakdown(
                ReceiptInput(merchant_raw="FamilyMart", items=["a", "b"]),
                BreakdownOptions(per_item_tax_rate_hints=["reduced"]),
            )

    def test_summarize_items_by_category(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="FamilyMart", items=["ミルク", "雑誌書籍"])
        )
        summary = dict(summarize_items_by_category(breakdown))
        self.assertEqual(summary.get("食費"), ["ミルク"])
        self.assertEqual(summary.get("教育"), ["雑誌書籍"])


if __name__ == "__main__":
    unittest.main()
