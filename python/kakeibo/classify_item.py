"""Single item classification (mirror of classifyItem.ts)."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

from .rules import ITEM_KEYWORD_RULES
from .types import Category, ItemClassification, TaxRateHint


@dataclass(frozen=True)
class ClassifyItemOptions:
    additional_keyword_rules: Optional[dict[str, Category]] = None
    tax_rate_hint: Optional[TaxRateHint] = None


def classify_item(
    item_text: str,
    options: Optional[ClassifyItemOptions] = None,
) -> ItemClassification:
    opts = options or ClassifyItemOptions()
    text = item_text.strip()
    if text == "":
        return ItemClassification(
            text=text, category=None, reason="empty_item", matched_keyword=None
        )

    merged = _merged_keyword_rules(opts.additional_keyword_rules)

    best_keyword: Optional[str] = None
    best_category: Optional[Category] = None
    for keyword, category in merged.items():
        if keyword not in text:
            continue
        if best_keyword is None or len(keyword) > len(best_keyword):
            best_keyword = keyword
            best_category = category

    if best_keyword is not None and best_category is not None:
        return ItemClassification(
            text=text,
            category=best_category,
            reason=f"item_keyword: {best_keyword}",
            matched_keyword=best_keyword,
        )

    if opts.tax_rate_hint == "reduced":
        return ItemClassification(
            text=text,
            category="食費",
            reason="tax_rate_hint: reduced→食費",
            matched_keyword=None,
        )

    return ItemClassification(
        text=text, category=None, reason="no_keyword_matched", matched_keyword=None
    )


def _merged_keyword_rules(
    additional: Optional[dict[str, Category]],
) -> dict[str, Category]:
    merged: dict[str, Category] = dict(ITEM_KEYWORD_RULES)
    if additional:
        for keyword, category in additional.items():
            if keyword and category:
                merged[keyword] = category
    return merged
