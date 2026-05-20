import unittest

from kakeibo.keyword_miner import (
    LabeledExample,
    LabeledItem,
    MineOptions,
    extract_ngrams,
    mine_keywords,
)


class ExtractNgramsTests(unittest.TestCase):
    def test_range_extraction(self):
        result = extract_ngrams("おにぎり", 2, 3)
        for expected in ("おに", "にぎ", "ぎり", "おにぎ", "にぎり"):
            self.assertIn(expected, result)
        self.assertEqual(len(result), len(set(result)))

    def test_short_text_skipped(self):
        self.assertEqual(extract_ngrams("薬", 2, 3), [])


class MineKeywordsTests(unittest.TestCase):
    def test_high_purity_keywords_extracted(self):
        examples = [
            LabeledExample(items=[LabeledItem(text="おにぎり鮭", category="食費")]),
            LabeledExample(items=[LabeledItem(text="おにぎり梅", category="食費")]),
            LabeledExample(items=[LabeledItem(text="シャンプー本体", category="日用品")]),
            LabeledExample(items=[LabeledItem(text="シャンプー詰替", category="日用品")]),
        ]
        candidates = mine_keywords(examples, MineOptions(min_support=2, min_purity=1.0))
        keywords = {(c.keyword, c.category) for c in candidates}
        self.assertTrue(
            any(k[0] in {"おにぎ", "にぎり"} and k[1] == "食費" for k in keywords)
        )
        self.assertTrue(any(k[0] == "シャン" and k[1] == "日用品" for k in keywords))

    def test_low_purity_filtered(self):
        examples = [
            LabeledExample(items=[LabeledItem(text="あいうえ", category="食費")]),
            LabeledExample(items=[LabeledItem(text="あいうえ", category="日用品")]),
        ]
        candidates = mine_keywords(examples, MineOptions(min_support=1, min_purity=0.8))
        self.assertEqual(candidates, [])

    def test_exclude_existing(self):
        examples = [
            LabeledExample(items=[LabeledItem(text="牛乳1L", category="食費")]),
            LabeledExample(items=[LabeledItem(text="牛乳パック", category="食費")]),
        ]
        candidates = mine_keywords(
            examples,
            MineOptions(min_support=2, min_purity=1.0, exclude_existing_keywords=("牛乳",)),
        )
        self.assertFalse(any(c.keyword == "牛乳" for c in candidates))


if __name__ == "__main__":
    unittest.main()
