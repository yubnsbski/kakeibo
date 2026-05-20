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


if __name__ == "__main__":
    unittest.main()
