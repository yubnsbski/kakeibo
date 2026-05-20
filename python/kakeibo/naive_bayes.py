"""Multinomial Naive Bayes classifier over character n-grams.

This module is intentionally standalone. It is intended to be wired into
``classify_item`` later as a third fallback layer, after the keyword rules
and the ``taxRateHint`` reduced→食費 short-circuit, when neither earlier
layer produces a category.

The implementation is pure stdlib (``math.log``, ``collections.Counter``) so
it satisfies the AGENTS.md no-external-dependencies rule.
"""
from __future__ import annotations

import math
from collections import Counter
from dataclasses import dataclass
from typing import Iterable, Optional

from .keyword_miner import LabeledExample, extract_ngrams
from .types import Category


@dataclass(frozen=True)
class NaiveBayesModel:
    category_log_priors: dict[Category, float]
    feature_log_likelihoods: dict[Category, dict[str, float]]
    vocabulary: tuple[str, ...]
    feature_min_length: int
    feature_max_length: int


def train_naive_bayes(
    examples: Iterable[LabeledExample],
    feature_min_length: int = 2,
    feature_max_length: int = 3,
    laplace_alpha: float = 1.0,
) -> NaiveBayesModel:
    """Train a Multinomial Naive Bayes model over character n-grams.

    Each labeled item contributes one document. Features are character
    n-grams of length ``feature_min_length`` … ``feature_max_length`` of
    the item text (whitespace stripped, deduplicated per document via the
    shared ``extract_ngrams`` helper).
    """
    category_doc_counts: Counter[Category] = Counter()
    category_feature_counts: dict[Category, Counter[str]] = {}
    vocabulary: set[str] = set()

    for example in examples:
        for item in example.items:
            ngrams = extract_ngrams(item.text, feature_min_length, feature_max_length)
            if not ngrams:
                continue
            category_doc_counts[item.category] += 1
            bucket = category_feature_counts.setdefault(item.category, Counter())
            for ngram in ngrams:
                bucket[ngram] += 1
                vocabulary.add(ngram)

    total_docs = sum(category_doc_counts.values())
    vocab_sorted: tuple[str, ...] = tuple(sorted(vocabulary))
    vocab_size = len(vocab_sorted)

    category_log_priors: dict[Category, float] = {}
    feature_log_likelihoods: dict[Category, dict[str, float]] = {}

    for category, doc_count in category_doc_counts.items():
        category_log_priors[category] = math.log(doc_count / total_docs)
        counts = category_feature_counts.get(category, Counter())
        total_count = sum(counts.values())
        denom = total_count + laplace_alpha * vocab_size
        per_feature: dict[str, float] = {}
        for feature in vocab_sorted:
            numer = counts.get(feature, 0) + laplace_alpha
            per_feature[feature] = math.log(numer / denom)
        feature_log_likelihoods[category] = per_feature

    return NaiveBayesModel(
        category_log_priors=category_log_priors,
        feature_log_likelihoods=feature_log_likelihoods,
        vocabulary=vocab_sorted,
        feature_min_length=feature_min_length,
        feature_max_length=feature_max_length,
    )


def predict_category(
    model: NaiveBayesModel, text: str
) -> tuple[Optional[Category], float]:
    """Return ``(best_category, log_prob_margin)`` for ``text``.

    ``margin`` is the difference between the log-posterior of the best
    category and that of the runner-up. With a single trained category the
    margin is reported as ``0.0``. Returns ``(None, 0.0)`` only when the
    text is empty, no features can be extracted from it, or the model has
    no trained categories.
    """
    if not text:
        return (None, 0.0)
    if not model.category_log_priors:
        return (None, 0.0)

    features = extract_ngrams(text, model.feature_min_length, model.feature_max_length)
    if not features:
        return (None, 0.0)

    scores: list[tuple[Category, float]] = []
    for category, log_prior in model.category_log_priors.items():
        likelihoods = model.feature_log_likelihoods.get(category, {})
        score = log_prior
        for feature in features:
            log_likelihood = likelihoods.get(feature)
            if log_likelihood is None:
                # Unseen feature: skip rather than zero-out the posterior.
                continue
            score += log_likelihood
        scores.append((category, score))

    if not scores:
        return (None, 0.0)

    scores.sort(key=lambda pair: pair[1], reverse=True)
    best_category, best_score = scores[0]
    if len(scores) == 1:
        return (best_category, 0.0)
    _, second_score = scores[1]
    return (best_category, best_score - second_score)
