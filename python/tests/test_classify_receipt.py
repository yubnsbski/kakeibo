import unittest

from kakeibo.classify_receipt import classify_receipt
from kakeibo.types import ReceiptInput


class ClassifyReceiptTests(unittest.TestCase):
    def test_seven_eleven_food(self):
        result = classify_receipt(
            ReceiptInput(
                merchant_raw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
                items=["おにぎり", "牛乳"],
                total_amount=620,
            )
        )
        self.assertEqual(result.category, "食費")
        self.assertFalse(result.needs_review)
        self.assertIn("merchant_rule: セブンイレブン", result.reasons)

    def test_merchant_rule_beats_item_keyword(self):
        result = classify_receipt(
            ReceiptInput(
                merchant_raw="マツモトキヨシ 新宿店",
                items=["おにぎり"],
                total_amount=480,
            )
        )
        self.assertEqual(result.category, "日用品")
        self.assertEqual(result.reasons, ["merchant_rule: マツモトキヨシ"])

    def test_user_override_top_priority(self):
        result = classify_receipt(
            ReceiptInput(
                merchant_raw="Amazon.co.jp",
                user_category_overrides={"Amazon": "通信"},
                total_amount=3000,
            )
        )
        self.assertEqual(result.category, "通信")
        self.assertEqual(result.reason, "user_override: 通信")

    def test_amazon_without_items_needs_review(self):
        result = classify_receipt(
            ReceiptInput(merchant_raw="Amazon.co.jp", total_amount=3000)
        )
        self.assertIsNone(result.category)
        self.assertTrue(result.needs_review)
        self.assertEqual(result.reasons, ["ambiguous_merchant_no_items"])

    def test_unknown_merchant_unknown_item(self):
        result = classify_receipt(
            ReceiptInput(merchant_raw="未知の店舗", items=["未知の品目"], total_amount=1000)
        )
        self.assertIsNone(result.category)
        self.assertTrue(result.needs_review)
        self.assertEqual(result.reason, "no rule matched")


class MixedItemCategoriesTests(unittest.TestCase):
    def test_family_mart_mixed_items_surfaced(self):
        result = classify_receipt(
            ReceiptInput(
                merchant_raw="ファミリーマート 渋谷店",
                items=["ミルクの束縛ミルクCO", "雑誌書籍"],
                total_amount=1500,
            )
        )
        # Merchant rule still decides the headline category.
        self.assertEqual(result.category, "食費")
        # But item-level mix is surfaced as an informational signal.
        self.assertIn("食費", result.mixed_item_categories)
        self.assertIn("教育", result.mixed_item_categories)
        self.assertEqual(len(result.mixed_item_categories), 2)

    def test_uniform_receipt_no_mixed_categories(self):
        result = classify_receipt(
            ReceiptInput(
                merchant_raw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
                items=["おにぎり", "牛乳"],
                total_amount=620,
            )
        )
        self.assertEqual(result.category, "食費")
        self.assertEqual(result.mixed_item_categories, ())

    def test_no_items_no_mixed_categories(self):
        result = classify_receipt(
            ReceiptInput(merchant_raw="Amazon.co.jp", total_amount=3000)
        )
        self.assertEqual(result.mixed_item_categories, ())

    def test_merchant_rule_still_surfaces_item_mix(self):
        # マツモトキヨシ resolves to 日用品 via merchant rule, but if items
        # contain a mix of categories the breakdown should still surface them.
        result = classify_receipt(
            ReceiptInput(
                merchant_raw="マツモトキヨシ 新宿店",
                items=["シャンプー", "本"],
                total_amount=2000,
            )
        )
        self.assertEqual(result.category, "日用品")
        self.assertIn("日用品", result.mixed_item_categories)
        self.assertIn("教育", result.mixed_item_categories)
        self.assertEqual(len(result.mixed_item_categories), 2)


if __name__ == "__main__":
    unittest.main()
