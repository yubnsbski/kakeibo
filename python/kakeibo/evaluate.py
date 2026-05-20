"""Evaluation harness (mirror of evaluate.ts)."""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable, Optional

from .classify_item import ClassifyItemOptions, classify_item
from .classify_receipt import classify_receipt
from .types import Category, ReceiptInput


@dataclass(frozen=True)
class ReceiptEvaluationCase:
    name: str
    input: ReceiptInput
    expected_category: Optional[Category]
    expected_needs_review: bool


@dataclass(frozen=True)
class ItemEvaluationCase:
    text: str
    expected_category: Optional[Category]


@dataclass(frozen=True)
class ReceiptEvaluationReport:
    total: int
    correct: int
    accuracy: float
    needs_review_rate: float
    failures: list[dict] = field(default_factory=list)


@dataclass(frozen=True)
class ItemEvaluationReport:
    total: int
    correct: int
    accuracy: float
    failures: list[dict] = field(default_factory=list)


def evaluate_receipts(cases: Iterable[ReceiptEvaluationCase]) -> ReceiptEvaluationReport:
    correct = 0
    needs_review_count = 0
    failures: list[dict] = []
    cases_list = list(cases)
    for c in cases_list:
        result = classify_receipt(c.input)
        ok = (
            result.category == c.expected_category
            and result.needs_review == c.expected_needs_review
        )
        if ok:
            correct += 1
        else:
            failures.append(
                {
                    "name": c.name,
                    "expected_category": c.expected_category,
                    "expected_needs_review": c.expected_needs_review,
                    "actual_category": result.category,
                    "actual_needs_review": result.needs_review,
                }
            )
        if result.needs_review:
            needs_review_count += 1
    total = len(cases_list)
    return ReceiptEvaluationReport(
        total=total,
        correct=correct,
        accuracy=0.0 if total == 0 else correct / total,
        needs_review_rate=0.0 if total == 0 else needs_review_count / total,
        failures=failures,
    )


def evaluate_items(
    cases: Iterable[ItemEvaluationCase],
    options: Optional[ClassifyItemOptions] = None,
) -> ItemEvaluationReport:
    correct = 0
    failures: list[dict] = []
    cases_list = list(cases)
    for c in cases_list:
        result = classify_item(c.text, options)
        if result.category == c.expected_category:
            correct += 1
        else:
            failures.append(
                {"text": c.text, "expected": c.expected_category, "actual": result.category}
            )
    total = len(cases_list)
    return ItemEvaluationReport(
        total=total,
        correct=correct,
        accuracy=0.0 if total == 0 else correct / total,
        failures=failures,
    )


def format_receipt_report(report: ReceiptEvaluationReport) -> str:
    lines = [
        "# receipt evaluation",
        f"accuracy:        {report.accuracy * 100:.1f}% ({report.correct}/{report.total})",
        f"needs_review_rate: {report.needs_review_rate * 100:.1f}%",
    ]
    if not report.failures:
        lines.append("failures:        (none)")
    else:
        lines.append("failures:")
        for f in report.failures:
            lines.append(
                f"  - {f['name']}: expected category={_stringify(f['expected_category'])} "
                f"needsReview={f['expected_needs_review']}, "
                f"got category={_stringify(f['actual_category'])} "
                f"needsReview={f['actual_needs_review']}"
            )
    return "\n".join(lines)


def format_item_report(report: ItemEvaluationReport) -> str:
    lines = [
        "# item evaluation",
        f"accuracy: {report.accuracy * 100:.1f}% ({report.correct}/{report.total})",
    ]
    if not report.failures:
        lines.append("failures: (none)")
    else:
        lines.append("failures:")
        for f in report.failures:
            lines.append(
                f"  - {f['text']}: expected={_stringify(f['expected'])}, got={_stringify(f['actual'])}"
            )
    return "\n".join(lines)


def _stringify(category: Optional[Category]) -> str:
    return "(null)" if category is None else category
