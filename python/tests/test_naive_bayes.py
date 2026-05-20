"""Tests for the Multinomial Naive Bayes classifier."""
from __future__ import annotations

import json
import math
import unittest
from pathlib import Path

from kakeibo.keyword_miner import LabeledExample, LabeledItem
from kakeibo.naive_bayes import (
    NaiveBayesModel,
    predict_category,
    train_naive_bayes,
)

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"


def _load_labeled_examples() -> list[LabeledExample]:
    raw = json.loads(
        (FIXTURES_DIR / "training" / "labeled-items.json").read_text(encoding="utf-8")
    )
    return [
        LabeledExample(
            source=entry.get("source"),
            items=[
                LabeledItem(text=item["text"], category=item["category"])
                for item in entry["items"]
            ],
        )
        for entry in raw
    ]


class TrainNaiveBayesTests(unittest.TestCase):
    def test_obvious_prediction_food(self):
        examples = [
            LabeledExample(
                items=[
                    LabeledItem(text="おにぎり鮭", category="食費"),
                    LabeledItem(text="おにぎり梅", category="食費"),
                    LabeledItem(text="牛乳1L", category="食費"),
                ]
            ),
            LabeledExample(
                items=[
                    LabeledItem(text="シャンプー本体", category="日用品"),
                    LabeledItem(text="液体洗剤詰替", category="日用品"),
                    LabeledItem(text="歯ブラシ", category="日用品"),
                ]
            ),
        ]
        model = train_naive_bayes(examples)
        category, margin = predict_category(model, "おにぎり鮭")
        self.assertEqual(category, "食費")
        self.assertGreater(margin, 0.0)

    def test_obvious_prediction_daily(self):
        examples = [
            LabeledExample(
                items=[
                    LabeledItem(text="おにぎり鮭", category="食費"),
                    LabeledItem(text="おにぎり梅", category="食費"),
                ]
            ),
            LabeledExample(
                items=[
                    LabeledItem(text="シャンプー本体", category="日用品"),
                    LabeledItem(text="シャンプー詰替", category="日用品"),
                ]
            ),
        ]
        model = train_naive_bayes(examples)
        category, margin = predict_category(model, "シャンプー本体")
        self.assertEqual(category, "日用品")
        self.assertGreater(margin, 0.0)

    def test_unseen_text_still_predicts(self):
        examples = [
            LabeledExample(
                items=[
                    LabeledItem(text="おにぎり鮭", category="食費"),
                    LabeledItem(text="おにぎり梅", category="食費"),
                ]
            ),
            LabeledExample(
                items=[
                    LabeledItem(text="シャンプー本体", category="日用品"),
                    LabeledItem(text="シャンプー詰替", category="日用品"),
                ]
            ),
        ]
        model = train_naive_bayes(examples)
        # Text shares no character n-grams with any training data
        # but still produces some prediction (priors only).
        category, margin = predict_category(model, "謎の物体XYZ")
        self.assertIsNotNone(category)
        self.assertGreaterEqual(margin, 0.0)

    def test_prior_reflects_doc_counts(self):
        examples = [
            LabeledExample(
                items=[
                    LabeledItem(text="aa", category="食費"),
                    LabeledItem(text="bb", category="食費"),
                    LabeledItem(text="cc", category="食費"),
                ]
            ),
            LabeledExample(
                items=[LabeledItem(text="dd", category="日用品")]
            ),
        ]
        model = train_naive_bayes(examples)
        # 3 docs vs 1 doc → 食費 prior must be strictly larger.
        self.assertGreater(
            model.category_log_priors["食費"],
            model.category_log_priors["日用品"],
        )
        # Sanity: priors are normalized log-probabilities of doc fractions.
        self.assertAlmostEqual(model.category_log_priors["食費"], math.log(3 / 4))
        self.assertAlmostEqual(model.category_log_priors["日用品"], math.log(1 / 4))

    def test_margin_is_difference_between_top_two(self):
        examples = [
            LabeledExample(
                items=[
                    LabeledItem(text="おにぎり鮭", category="食費"),
                    LabeledItem(text="おにぎり梅", category="食費"),
                ]
            ),
            LabeledExample(
                items=[
                    LabeledItem(text="シャンプー本体", category="日用品"),
                    LabeledItem(text="シャンプー詰替", category="日用品"),
                ]
            ),
        ]
        model = train_naive_bayes(examples)
        category, margin = predict_category(model, "おにぎり梅")
        self.assertEqual(category, "食費")

        # Recompute the margin manually to verify it equals best - second.
        from kakeibo.keyword_miner import extract_ngrams

        features = extract_ngrams(
            "おにぎり梅", model.feature_min_length, model.feature_max_length
        )
        scores = []
        for cat, log_prior in model.category_log_priors.items():
            score = log_prior
            for feat in features:
                ll = model.feature_log_likelihoods[cat].get(feat)
                if ll is not None:
                    score += ll
            scores.append(score)
        scores.sort(reverse=True)
        expected_margin = scores[0] - scores[1]
        self.assertAlmostEqual(margin, expected_margin)
        self.assertGreater(margin, 0.0)

    def test_empty_text_returns_none(self):
        examples = [
            LabeledExample(
                items=[LabeledItem(text="おにぎり鮭", category="食費")]
            )
        ]
        model = train_naive_bayes(examples)
        self.assertEqual(predict_category(model, ""), (None, 0.0))

    def test_untrained_model_returns_none(self):
        model = train_naive_bayes([])
        self.assertEqual(predict_category(model, "おにぎり"), (None, 0.0))

    def test_model_is_frozen_dataclass(self):
        examples = [
            LabeledExample(items=[LabeledItem(text="おにぎり鮭", category="食費")])
        ]
        model = train_naive_bayes(examples)
        self.assertIsInstance(model, NaiveBayesModel)
        with self.assertRaises(Exception):
            model.feature_min_length = 99  # type: ignore[misc]


class NaiveBayesSmokeTests(unittest.TestCase):
    """Smoke tests using the actual labeled-items.json fixture."""

    def test_holdout_item_gets_some_prediction(self):
        examples = _load_labeled_examples()
        all_items = [(item, ex.source) for ex in examples for item in ex.items]
        self.assertGreater(len(all_items), 1)

        # Hold out the first item; train on the rest.
        held_out, _ = all_items[0]
        train_items = [it for it, _ in all_items[1:]]
        training = [LabeledExample(items=train_items)]
        model = train_naive_bayes(training)

        category, margin = predict_category(model, held_out.text)
        # Smoke test: we don't assert accuracy, only that a prediction is
        # produced without crashing and the margin is finite & non-negative.
        self.assertIsNotNone(category)
        self.assertGreaterEqual(margin, 0.0)
        self.assertTrue(math.isfinite(margin))

    def test_full_fixture_trains_and_predicts(self):
        examples = _load_labeled_examples()
        model = train_naive_bayes(examples)
        self.assertGreater(len(model.vocabulary), 0)
        self.assertGreater(len(model.category_log_priors), 1)

        # Pick a few obvious cases and ensure they predict their family
        # category. These items literally appear in training data, so this
        # is a sanity check that training didn't silently break.
        category, _ = predict_category(model, "おにぎり鮭")
        self.assertEqual(category, "食費")
        category, _ = predict_category(model, "シャンプー本体")
        self.assertEqual(category, "日用品")


if __name__ == "__main__":
    unittest.main()
