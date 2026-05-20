import unittest

from kakeibo.allocate_amounts import AllocateOptions, allocate_amounts_by_category
from kakeibo.classify_breakdown import classify_receipt_breakdown
from kakeibo.types import ReceiptInput


class AllocateAmountsByCategoryTests(unittest.TestCase):
    def test_familymart_real_receipt_split(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(
                merchant_raw="FamilyMart 船橋海神二丁目店",
                items=["ミルクの束縛ミルクCO", "雑誌書籍"],
                total_amount=408,
            )
        )
        result = allocate_amounts_by_category(
            breakdown, 408, AllocateOptions(per_item_amounts=[228, 180])
        )
        self.assertEqual(result.strategy, "per_item_amounts")
        food = next(a for a in result.allocations if a.category == "食費")
        education = next(a for a in result.allocations if a.category == "教育")
        self.assertEqual(food.amount, 228)
        self.assertEqual(education.amount, 180)
        self.assertEqual(result.unclassified_amount, 0)

    def test_equal_split_default(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="FamilyMart", items=["ミルク", "雑誌書籍"])
        )
        result = allocate_amounts_by_category(breakdown, 408)
        self.assertEqual(result.strategy, "equal_split")
        total = sum(a.amount for a in result.allocations)
        self.assertAlmostEqual(total, 408, places=2)

    def test_unclassified_item_bucketed_with_null_category(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="セブンイレブン", items=["おにぎり", "謎の物体"])
        )
        result = allocate_amounts_by_category(
            breakdown, 1000, AllocateOptions(per_item_amounts=[400, 600])
        )
        unclassified = next(a for a in result.allocations if a.category is None)
        self.assertEqual(unclassified.amount, 600)
        self.assertEqual(unclassified.item_texts, ["謎の物体"])
        self.assertEqual(result.unclassified_amount, 600)

    def test_empty_items_unclassified_total(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="Amazon.co.jp", total_amount=3000)
        )
        result = allocate_amounts_by_category(breakdown, 3000)
        self.assertEqual(result.allocations, [])
        self.assertEqual(result.unclassified_amount, 3000)

    def test_same_category_items_merged(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(
                merchant_raw="セブンイレブン",
                items=["おにぎり鮭", "おにぎり梅", "牛乳1L"],
            )
        )
        result = allocate_amounts_by_category(
            breakdown, 900, AllocateOptions(per_item_amounts=[200, 200, 500])
        )
        self.assertEqual(len(result.allocations), 1)
        self.assertEqual(result.allocations[0].category, "食費")
        self.assertEqual(result.allocations[0].amount, 900)

    def test_per_item_amounts_length_mismatch_raises(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="セブンイレブン", items=["おにぎり", "牛乳"])
        )
        with self.assertRaises(ValueError):
            allocate_amounts_by_category(
                breakdown, 500, AllocateOptions(per_item_amounts=[500])
            )

    def test_negative_total_raises(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(merchant_raw="セブンイレブン", items=["おにぎり"])
        )
        with self.assertRaises(ValueError):
            allocate_amounts_by_category(breakdown, -100)

    def test_equal_split_remainder_absorbed_in_last_item(self):
        breakdown = classify_receipt_breakdown(
            ReceiptInput(
                merchant_raw="セブンイレブン",
                items=["おにぎり鮭", "おにぎり梅", "牛乳1L"],
            )
        )
        result = allocate_amounts_by_category(breakdown, 100)
        total = sum(a.amount for a in result.allocations)
        self.assertAlmostEqual(total, 100, places=2)


if __name__ == "__main__":
    unittest.main()
