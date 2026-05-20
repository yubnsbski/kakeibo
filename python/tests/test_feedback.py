import unittest

from kakeibo.feedback import (
    ConfirmedItem,
    ManualReviewEntry,
    merge_labeled_examples,
    to_labeled_examples,
)
from kakeibo.keyword_miner import LabeledExample, LabeledItem


class ToLabeledExamplesTests(unittest.TestCase):
    def test_basic_conversion(self):
        result = to_labeled_examples(
            [
                ManualReviewEntry(
                    source="familymart_2026-05-04",
                    confirmed_items=[
                        ConfirmedItem(text="ミルクの束縛ミルクCO", confirmed_category="食費"),
                        ConfirmedItem(text="雑誌書籍", confirmed_category="教育"),
                    ],
                )
            ]
        )
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0].source, "familymart_2026-05-04")
        self.assertEqual(
            result[0].items,
            [
                LabeledItem(text="ミルクの束縛ミルクCO", category="食費"),
                LabeledItem(text="雑誌書籍", category="教育"),
            ],
        )

    def test_empty_texts_filtered(self):
        result = to_labeled_examples(
            [
                ManualReviewEntry(
                    source="r001",
                    confirmed_items=[
                        ConfirmedItem(text="  ", confirmed_category="食費"),
                        ConfirmedItem(text="おにぎり", confirmed_category="食費"),
                    ],
                )
            ]
        )
        self.assertEqual(result[0].items, [LabeledItem(text="おにぎり", category="食費")])

    def test_review_with_no_valid_items_excluded(self):
        result = to_labeled_examples(
            [
                ManualReviewEntry(
                    source="empty",
                    confirmed_items=[ConfirmedItem(text="  ", confirmed_category="食費")],
                )
            ]
        )
        self.assertEqual(result, [])


class MergeLabeledExamplesTests(unittest.TestCase):
    def test_same_source_merges_and_dedupes(self):
        existing = [
            LabeledExample(
                source="familymart_2026-05-04",
                items=[LabeledItem(text="ミルクの束縛ミルクCO", category="食費")],
            )
        ]
        additions = [
            LabeledExample(
                source="familymart_2026-05-04",
                items=[
                    LabeledItem(text="ミルクの束縛ミルクCO", category="食費"),
                    LabeledItem(text="雑誌書籍", category="教育"),
                ],
            )
        ]
        merged = merge_labeled_examples(existing, additions)
        target = next(e for e in merged if e.source == "familymart_2026-05-04")
        self.assertEqual(
            target.items,
            [
                LabeledItem(text="ミルクの束縛ミルクCO", category="食費"),
                LabeledItem(text="雑誌書籍", category="教育"),
            ],
        )

    def test_different_sources_stay_separate(self):
        existing = [LabeledExample(source="a", items=[LabeledItem(text="おにぎり", category="食費")])]
        additions = [LabeledExample(source="b", items=[LabeledItem(text="本", category="教育")])]
        merged = merge_labeled_examples(existing, additions)
        self.assertEqual(sorted(e.source for e in merged), ["a", "b"])

    def test_sourceless_examples_always_appended(self):
        merged = merge_labeled_examples(
            [LabeledExample(items=[LabeledItem(text="x", category="食費")])],
            [LabeledExample(items=[LabeledItem(text="y", category="日用品")])],
        )
        self.assertEqual(len(merged), 2)

    def test_inputs_not_mutated(self):
        existing = [
            LabeledExample(source="a", items=[LabeledItem(text="おにぎり", category="食費")])
        ]
        additions = [
            LabeledExample(source="a", items=[LabeledItem(text="牛乳", category="食費")])
        ]
        snapshot_existing = [tuple(i.text for i in e.items) for e in existing]
        snapshot_additions = [tuple(i.text for i in e.items) for e in additions]
        merge_labeled_examples(existing, additions)
        self.assertEqual(
            snapshot_existing, [tuple(i.text for i in e.items) for e in existing]
        )
        self.assertEqual(
            snapshot_additions, [tuple(i.text for i in e.items) for e in additions]
        )


if __name__ == "__main__":
    unittest.main()
