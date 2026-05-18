import unittest

from python_impl.classifier import ReceiptInput, classify_receipt


class ClassifierTest(unittest.TestCase):
    def test_ambiguous_no_items_needs_review(self):
        result = classify_receipt(ReceiptInput(merchant_raw="Amazon.co.jp", items=[]))
        self.assertIsNone(result.category)
        self.assertTrue(result.needs_review)
        self.assertEqual(result.reasons, ["ambiguous_merchant_no_items"])

    def test_keyword_match_with_whitespace(self):
        result = classify_receipt(ReceiptInput(merchant_raw="不明店舗", items=["  ガソリン  ", "   "]))
        self.assertEqual(result.category, "交通")
        self.assertFalse(result.needs_review)
        self.assertEqual(result.reasons, ["item_keyword: ガソリン"])

    def test_ambiguous_with_items_manual_review(self):
        result = classify_receipt(ReceiptInput(merchant_raw="ドン・キホーテ 新宿店", items=["洗剤"]))
        self.assertIsNone(result.category)
        self.assertTrue(result.needs_review)
        self.assertEqual(result.confidence, 0.4)
        self.assertEqual(result.reasons, ["item_keyword: 洗剤", "ambiguous_merchant_with_items"])


if __name__ == "__main__":
    unittest.main()
