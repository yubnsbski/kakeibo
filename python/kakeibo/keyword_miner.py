"""Keyword mining via character n-grams (mirror of keywordMiner.ts)."""
from __future__ import annotations

import re
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Iterable, Optional

from .types import Category


@dataclass(frozen=True)
class LabeledItem:
    text: str
    category: Category


@dataclass(frozen=True)
class LabeledExample:
    items: list[LabeledItem]
    source: Optional[str] = None


@dataclass(frozen=True)
class KeywordCandidate:
    keyword: str
    category: Category
    support: int
    purity: float
    score: float


@dataclass(frozen=True)
class MineOptions:
    min_length: int = 2
    max_length: int = 3
    min_support: int = 2
    min_purity: float = 0.8
    exclude_existing_keywords: tuple[str, ...] = field(default_factory=tuple)


_WHITESPACE_RE = re.compile(r"\s+")


def extract_ngrams(text: str, min_length: int, max_length: int) -> list[str]:
    cleaned = _WHITESPACE_RE.sub("", text)
    ngrams: list[str] = []
    seen: set[str] = set()
    for length in range(min_length, max_length + 1):
        if len(cleaned) < length:
            continue
        for i in range(len(cleaned) - length + 1):
            ngram = cleaned[i : i + length]
            if ngram not in seen:
                seen.add(ngram)
                ngrams.append(ngram)
    return ngrams


def mine_keywords(
    examples: Iterable[LabeledExample],
    options: Optional[MineOptions] = None,
) -> list[KeywordCandidate]:
    opts = options or MineOptions()
    excluded = set(opts.exclude_existing_keywords)

    ngram_category_counts: dict[str, dict[Category, int]] = defaultdict(lambda: defaultdict(int))

    for example in examples:
        for item in example.items:
            for ngram in extract_ngrams(item.text, opts.min_length, opts.max_length):
                if ngram in excluded:
                    continue
                ngram_category_counts[ngram][item.category] += 1

    candidates: list[KeywordCandidate] = []
    for ngram, counts in ngram_category_counts.items():
        total = sum(counts.values())
        best_category: Optional[Category] = None
        best_count = 0
        for category, count in counts.items():
            if count > best_count:
                best_count = count
                best_category = category
        if best_category is None:
            continue
        support = best_count
        purity = best_count / total
        if support < opts.min_support or purity < opts.min_purity:
            continue
        candidates.append(
            KeywordCandidate(
                keyword=ngram,
                category=best_category,
                support=support,
                purity=purity,
                score=support * purity,
            )
        )

    candidates.sort(key=lambda c: (-c.score, -c.support, c.keyword))
    return _remove_substring_redundancy(candidates)


def _remove_substring_redundancy(
    candidates: list[KeywordCandidate],
) -> list[KeywordCandidate]:
    kept: list[KeywordCandidate] = []
    for candidate in candidates:
        covered = any(
            existing.category == candidate.category
            and candidate.keyword in existing.keyword
            and existing.keyword != candidate.keyword
            and existing.support >= candidate.support
            for existing in kept
        )
        if covered:
            continue
        kept.append(candidate)
    return kept
