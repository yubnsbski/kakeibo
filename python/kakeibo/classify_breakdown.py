"""Per-item receipt breakdown (mirror of classifyReceiptBreakdown.ts)."""
from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from typing import Optional

from .classify_item import ClassifyItemOptions, classify_item
from .normalize_merchant import normalize_merchant
from .types import (
    Category,
    ItemClassification,
    ReceiptBreakdown,
    ReceiptInput,
    TaxRateHint,
)


@dataclass(frozen=True)
class BreakdownOptions:
    additional_keyword_rules: Optional[dict[str, Category]] = None
    per_item_tax_rate_hints: Optional[list[Optional[TaxRateHint]]] = None


def classify_receipt_breakdown(
    input_: ReceiptInput,
    options: Optional[BreakdownOptions] = None,
) -> ReceiptBreakdown:
    opts = options or BreakdownOptions()
    merchant_normalized = normalize_merchant(input_.merchant_raw)
    raw_items = list(input_.items)

    if opts.per_item_tax_rate_hints is not None and len(opts.per_item_tax_rate_hints) != len(raw_items):
        raise ValueError(
            f"per_item_tax_rate_hints length ({len(opts.per_item_tax_rate_hints)}) "
            f"does not match items length ({len(raw_items)})"
        )

    classifications: list[ItemClassification] = []
    for index, text in enumerate(raw_items):
        hint = opts.per_item_tax_rate_hints[index] if opts.per_item_tax_rate_hints else None
        item_opts = ClassifyItemOptions(
            additional_keyword_rules=opts.additional_keyword_rules,
            tax_rate_hint=hint,
        )
        classifications.append(classify_item(text, item_opts))

    category_counts: Counter[Category] = Counter()
    for item in classifications:
        if item.category is not None:
            category_counts[item.category] += 1

    dominant_category = _pick_dominant_category(category_counts)
    is_mixed = len(category_counts) > 1
    has_unclassified = any(item.category is None for item in classifications)
    needs_review = len(classifications) == 0 or has_unclassified or is_mixed

    return ReceiptBreakdown(
        merchant_normalized=merchant_normalized,
        items=classifications,
        dominant_category=dominant_category,
        is_mixed=is_mixed,
        needs_review=needs_review,
    )


def _pick_dominant_category(counts: Counter[Category]) -> Optional[Category]:
    if not counts:
        return None
    most_common = counts.most_common()
    top_count = most_common[0][1]
    top_categories = [cat for cat, c in most_common if c == top_count]
    if len(top_categories) > 1:
        return None
    return top_categories[0]


def summarize_items_by_category(
    breakdown: ReceiptBreakdown,
) -> list[tuple[Optional[Category], list[str]]]:
    grouped: dict[Optional[Category], list[str]] = {}
    for item in breakdown.items:
        grouped.setdefault(item.category, []).append(item.text)
    return list(grouped.items())
