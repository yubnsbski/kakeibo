"""Evaluation tests including hard accuracy >= 90% requirement."""
from __future__ import annotations

import json
import os
import unittest
from pathlib import Path

from kakeibo.classify_item import ClassifyItemOptions
from kakeibo.evaluate import (
    ItemEvaluationCase,
    ReceiptEvaluationCase,
    evaluate_items,
    evaluate_receipts,
    format_item_report,
    format_receipt_report,
)
from kakeibo.keyword_miner import LabeledExample, LabeledItem, MineOptions, mine_keywords
from kakeibo.rules import ITEM_KEYWORD_RULES
from kakeibo.types import ReceiptInput

FIXTURES_DIR = Path(__file__).resolve().parent.parent / "fixtures"


def _load_receipt_eval_cases() -> list[ReceiptEvaluationCase]:
    raw = json.loads((FIXTURES_DIR / "receipts" / "evaluation.json").read_text(encoding="utf-8"))
    cases = []
    for entry in raw:
        cases.append(
            ReceiptEvaluationCase(
                name=entry["name"],
                input=ReceiptInput(
                    merchant_raw=entry["input"]["merchantRaw"],
                    items=entry["input"].get("items", []),
                    total_amount=entry["input"].get("totalAmount"),
                    purchased_at=entry["input"].get("purchasedAt"),
                ),
                expected_category=entry["expected"]["category"],
                expected_needs_review=entry["expected"]["needsReview"],
            )
        )
    return cases


def _load_labeled_examples() -> list[LabeledExample]:
    raw = json.loads(
        (FIXTURES_DIR / "training" / "labeled-items.json").read_text(encoding="utf-8")
    )
    return [
        LabeledExample(
            source=entry.get("source"),
            items=[LabeledItem(text=it["text"], category=it["category"]) for it in entry["items"]],
        )
        for entry in raw
    ]


def _flatten_to_item_cases(examples: list[LabeledExample]) -> list[ItemEvaluationCase]:
    return [
        ItemEvaluationCase(text=item.text, expected_category=item.category)
        for ex in examples
        for item in ex.items
    ]


class ReceiptEvaluationTests(unittest.TestCase):
    def test_receipt_eval_perfect(self):
        cases = _load_receipt_eval_cases()
        report = evaluate_receipts(cases)
        self.assertEqual(report.accuracy, 1.0, msg=format_receipt_report(report))


class ItemAccuracyTests(unittest.TestCase):
    def test_baseline_accuracy_meets_90_percent(self):
        cases = _flatten_to_item_cases(_load_labeled_examples())
        report = evaluate_items(cases)
        self.assertGreaterEqual(
            report.accuracy,
            0.90,
            msg=(
                f"baseline accuracy below threshold:\n{format_item_report(report)}"
            ),
        )

    def test_accuracy_with_mined_keywords_at_least_baseline(self):
        examples = _load_labeled_examples()
        cases = _flatten_to_item_cases(examples)
        baseline = evaluate_items(cases)

        mined = mine_keywords(
            examples,
            MineOptions(
                min_length=2,
                max_length=3,
                min_support=2,
                min_purity=0.8,
                exclude_existing_keywords=tuple(ITEM_KEYWORD_RULES.keys()),
            ),
        )
        additional = {c.keyword: c.category for c in mined}
        augmented = evaluate_items(
            cases, ClassifyItemOptions(additional_keyword_rules=additional)
        )

        self.assertGreaterEqual(
            augmented.accuracy,
            baseline.accuracy,
            msg=(
                "mined keywords regressed accuracy\n"
                f"baseline:\n{format_item_report(baseline)}\n"
                f"augmented:\n{format_item_report(augmented)}"
            ),
        )

    @unittest.skipUnless(
        os.environ.get("EVALUATE_REPORT") == "1",
        "set EVALUATE_REPORT=1 to print evaluation report",
    )
    def test_print_report(self):
        cases = _flatten_to_item_cases(_load_labeled_examples())
        baseline = evaluate_items(cases)
        print("\n" + format_item_report(baseline))


if __name__ == "__main__":
    unittest.main()
