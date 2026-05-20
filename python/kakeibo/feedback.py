"""Feedback loop helpers (mirror of feedback.ts)."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Iterable

from .keyword_miner import LabeledExample, LabeledItem
from .types import Category


@dataclass(frozen=True)
class ConfirmedItem:
    text: str
    confirmed_category: Category


@dataclass(frozen=True)
class ManualReviewEntry:
    source: str
    confirmed_items: list[ConfirmedItem]


def to_labeled_examples(reviews: Iterable[ManualReviewEntry]) -> list[LabeledExample]:
    examples: list[LabeledExample] = []
    for review in reviews:
        items = [
            LabeledItem(text=item.text.strip(), category=item.confirmed_category)
            for item in review.confirmed_items
            if item.text.strip() != ""
        ]
        if items:
            examples.append(LabeledExample(source=review.source, items=items))
    return examples


def merge_labeled_examples(
    existing: Iterable[LabeledExample],
    additions: Iterable[LabeledExample],
) -> list[LabeledExample]:
    by_source: dict[str, LabeledExample] = {}
    sourceless: list[LabeledExample] = []

    for example in existing:
        if example.source:
            by_source[example.source] = LabeledExample(
                source=example.source, items=list(example.items)
            )
        else:
            sourceless.append(LabeledExample(source=None, items=list(example.items)))

    for addition in additions:
        if addition.source is None:
            sourceless.append(LabeledExample(source=None, items=list(addition.items)))
            continue
        previous = by_source.get(addition.source)
        if previous is None:
            by_source[addition.source] = LabeledExample(
                source=addition.source, items=list(addition.items)
            )
            continue
        by_source[addition.source] = LabeledExample(
            source=addition.source,
            items=_dedupe_items(list(previous.items) + list(addition.items)),
        )

    return list(by_source.values()) + sourceless


def _dedupe_items(items: Iterable[LabeledItem]) -> list[LabeledItem]:
    seen: dict[str, LabeledItem] = {}
    for item in items:
        key = f"{item.text}{item.category}"
        if key not in seen:
            seen[key] = item
    return list(seen.values())
