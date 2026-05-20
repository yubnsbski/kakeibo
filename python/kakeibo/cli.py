"""Simple CLI for the Python implementation."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional

from .classify_item import ClassifyItemOptions
from .evaluate import (
    ItemEvaluationCase,
    evaluate_items,
    format_item_report,
)
from .keyword_miner import LabeledExample, LabeledItem, MineOptions, mine_keywords
from .rules import ITEM_KEYWORD_RULES

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
FIXTURES_DIR = REPO_ROOT / "fixtures"


def _load_labeled() -> list[LabeledExample]:
    raw = json.loads((FIXTURES_DIR / "training" / "labeled-items.json").read_text("utf-8"))
    return [
        LabeledExample(
            source=entry.get("source"),
            items=[LabeledItem(text=it["text"], category=it["category"]) for it in entry["items"]],
        )
        for entry in raw
    ]


def cmd_mine_keywords(_args: argparse.Namespace) -> int:
    examples = _load_labeled()
    candidates = mine_keywords(
        examples,
        MineOptions(
            min_support=2,
            min_purity=0.8,
            exclude_existing_keywords=tuple(ITEM_KEYWORD_RULES.keys()),
        ),
    )
    if not candidates:
        print("候補なし (minSupport/minPurityを緩めるか学習データを増やしてください)")
        return 0
    print("# 明細キーワード候補（rules.pyへの反映は人手レビュー後に手動で）")
    print("# keyword\tcategory\tsupport\tpurity\tscore")
    for c in candidates:
        print(f"{c.keyword}\t{c.category}\t{c.support}\t{c.purity:.2f}\t{c.score:.2f}")
    return 0


def cmd_evaluate(_args: argparse.Namespace) -> int:
    examples = _load_labeled()
    cases = [
        ItemEvaluationCase(text=item.text, expected_category=item.category)
        for ex in examples
        for item in ex.items
    ]

    baseline = evaluate_items(cases)
    print("## baseline (rules.py only)")
    print(format_item_report(baseline))

    mined = mine_keywords(
        examples,
        MineOptions(
            min_support=2,
            min_purity=0.8,
            exclude_existing_keywords=tuple(ITEM_KEYWORD_RULES.keys()),
        ),
    )
    additional = {c.keyword: c.category for c in mined}
    augmented = evaluate_items(cases, ClassifyItemOptions(additional_keyword_rules=additional))
    print("\n## with mined keywords")
    print(format_item_report(augmented))
    print(f"\ndelta accuracy: {(augmented.accuracy - baseline.accuracy) * 100:.1f}pt")

    if baseline.accuracy < 0.90:
        print(f"\nERROR: baseline accuracy {baseline.accuracy * 100:.1f}% < 90%", file=sys.stderr)
        return 1
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(prog="kakeibo")
    sub = parser.add_subparsers(dest="command", required=True)

    p_mine = sub.add_parser("mine-keywords", help="extract keyword candidates from labeled data")
    p_mine.set_defaults(func=cmd_mine_keywords)

    p_eval = sub.add_parser("evaluate", help="evaluate item-level accuracy (asserts >= 90%)")
    p_eval.set_defaults(func=cmd_evaluate)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
