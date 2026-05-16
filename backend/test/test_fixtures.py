"""Fixture-based regression tests.

Loads fixtures/receipts/{basic,evaluation}.json and asserts that the Python
classifier output matches each fixture's `expected` block. The fixtures act
as a behavioral contract shared with the original TS implementation.
"""
from __future__ import annotations

import pytest

from app.classifier import ReceiptInput, classify_receipt

from .conftest import load_fixture_cases


def _ids(cases: list[dict]) -> list[str]:
    return [c["name"] for c in cases]


@pytest.mark.parametrize(
    "case",
    load_fixture_cases("basic.json"),
    ids=_ids(load_fixture_cases("basic.json")),
)
def test_basic_fixture(case: dict):
    result = classify_receipt(ReceiptInput(**case["input"]))
    expected = case["expected"]
    assert result.category == expected["category"], (
        f"category mismatch in {case['name']}: "
        f"expected {expected['category']!r}, got {result.category!r}"
    )
    assert result.needsReview == expected["needsReview"], (
        f"needsReview mismatch in {case['name']}: "
        f"expected {expected['needsReview']!r}, got {result.needsReview!r}"
    )


@pytest.mark.parametrize(
    "case",
    load_fixture_cases("evaluation.json"),
    ids=_ids(load_fixture_cases("evaluation.json")),
)
def test_evaluation_fixture(case: dict):
    result = classify_receipt(ReceiptInput(**case["input"]))
    expected = case["expected"]
    assert result.category == expected["category"], (
        f"category mismatch in {case['name']}: "
        f"expected {expected['category']!r}, got {result.category!r}"
    )
    assert result.needsReview == expected["needsReview"], (
        f"needsReview mismatch in {case['name']}: "
        f"expected {expected['needsReview']!r}, got {result.needsReview!r}"
    )
