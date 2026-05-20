"""Allocate receipt amount across categories (mirror of allocateAmounts.ts)."""
from __future__ import annotations

import math
from dataclasses import dataclass
from typing import Optional

from .types import (
    AmountAllocationResult,
    Category,
    CategoryAllocation,
    ReceiptBreakdown,
)


@dataclass(frozen=True)
class AllocateOptions:
    per_item_amounts: Optional[list[float]] = None


def allocate_amounts_by_category(
    breakdown: ReceiptBreakdown,
    total_amount: float,
    options: Optional[AllocateOptions] = None,
) -> AmountAllocationResult:
    opts = options or AllocateOptions()
    _assert_non_negative(total_amount, "total_amount")

    items = breakdown.items
    if len(items) == 0:
        return AmountAllocationResult(
            total_amount=total_amount,
            allocations=[],
            strategy="equal_split",
            unclassified_amount=total_amount,
        )

    per_item = _resolve_per_item_amounts(len(items), total_amount, opts.per_item_amounts)
    strategy: str = "per_item_amounts" if opts.per_item_amounts is not None else "equal_split"

    buckets: dict[Optional[Category], dict] = {}
    for index, item in enumerate(items):
        bucket = buckets.setdefault(item.category, {"amount": 0.0, "item_texts": []})
        bucket["amount"] += per_item[index]
        bucket["item_texts"].append(item.text)

    allocations = [
        CategoryAllocation(category=cat, amount=_round_currency(b["amount"]), item_texts=list(b["item_texts"]))
        for cat, b in buckets.items()
    ]
    allocations.sort(key=lambda a: a.amount, reverse=True)

    unclassified_amount = next(
        (a.amount for a in allocations if a.category is None), 0.0
    )

    return AmountAllocationResult(
        total_amount=total_amount,
        allocations=allocations,
        strategy=strategy,  # type: ignore[arg-type]
        unclassified_amount=unclassified_amount,
    )


def _resolve_per_item_amounts(
    item_count: int,
    total_amount: float,
    provided: Optional[list[float]],
) -> list[float]:
    if provided is not None:
        if len(provided) != item_count:
            raise ValueError(
                f"per_item_amounts length ({len(provided)}) "
                f"does not match items length ({item_count})"
            )
        for amount in provided:
            _assert_non_negative(amount, "per_item_amounts entry")
        return list(provided)
    return _equal_split(total_amount, item_count)


def _equal_split(total: float, count: int) -> list[float]:
    if count == 0:
        return []
    base = math.floor((total / count) * 100) / 100
    amounts = [base] * count
    distributed = _round_currency(base * count)
    remainder = _round_currency(total - distributed)
    amounts[-1] = _round_currency(amounts[-1] + remainder)
    return amounts


def _round_currency(value: float) -> float:
    return round(value * 100) / 100


def _assert_non_negative(value: float, label: str) -> None:
    if value is None or not math.isfinite(value) or value < 0:
        raise ValueError(f"{label} must be a finite non-negative number, got {value}")
