import unittest

from kakeibo.classify_item import ClassifyItemOptions, classify_item


class ClassifyItemTests(unittest.TestCase):
    def test_baseline_onigiri(self):
        result = classify_item("おにぎり鮭")
        self.assertEqual(result.category, "食費")
        self.assertEqual(result.matched_keyword, "おにぎり")

    def test_unknown_item(self):
        result = classify_item("謎の物体")
        self.assertIsNone(result.category)
        self.assertEqual(result.reason, "no_keyword_matched")

    def test_additional_rules(self):
        result = classify_item(
            "雑誌書籍",
            ClassifyItemOptions(additional_keyword_rules={"書籍": "教育"}),
        )
        self.assertEqual(result.category, "教育")

    def test_longest_match_wins(self):
        result = classify_item(
            "おにぎり梅",
            ClassifyItemOptions(additional_keyword_rules={"おに": "その他"}),
        )
        self.assertEqual(result.matched_keyword, "おにぎり")

    def test_empty_text(self):
        result = classify_item("   ")
        self.assertIsNone(result.category)
        self.assertEqual(result.reason, "empty_item")

    def test_tax_rate_hint_reduced_fallback(self):
        result = classify_item(
            "未知の食品商品X", ClassifyItemOptions(tax_rate_hint="reduced")
        )
        self.assertEqual(result.category, "食費")
        self.assertEqual(result.reason, "tax_rate_hint: reduced→食費")

    def test_keyword_beats_tax_hint(self):
        result = classify_item(
            "シャンプー詰替", ClassifyItemOptions(tax_rate_hint="reduced")
        )
        self.assertEqual(result.category, "日用品")

    def test_standard_hint_does_not_fallback(self):
        result = classify_item(
            "謎の物体", ClassifyItemOptions(tax_rate_hint="standard")
        )
        self.assertIsNone(result.category)


if __name__ == "__main__":
    unittest.main()
