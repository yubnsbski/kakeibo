import sys
import unittest
from pathlib import Path

CURRENT_DIR = Path(__file__).resolve().parent
if str(CURRENT_DIR) not in sys.path:
    sys.path.insert(0, str(CURRENT_DIR))

from receipt_classifier import classify_receipt


class ReceiptClassifierTest(unittest.TestCase):
    def test_seven_eleven_is_food(self) -> None:
        result = classify_receipt("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店", ["おにぎり", "牛乳"])
        self.assertEqual(result.category, "食費")
        self.assertFalse(result.needs_review)

    def test_user_override_is_priority(self) -> None:
        result = classify_receipt("Amazon.co.jp", [], {"Amazon": "通信"})
        self.assertEqual(result.category, "通信")
        self.assertFalse(result.needs_review)
        self.assertEqual(result.reason, "user_override: 通信")

    def test_ambiguous_merchant_with_no_items_needs_review(self) -> None:
        result = classify_receipt("ドン・キホーテ 渋谷店", [])
        self.assertIsNone(result.category)
        self.assertTrue(result.needs_review)
        self.assertEqual(result.reason, "ambiguous merchant: ドンキホーテ")


if __name__ == "__main__":
    unittest.main()
