#!/usr/bin/env python3
import json
from pathlib import Path
from dataclasses import dataclass
from typing import Dict, List

from rapidfuzz.distance import Levenshtein


@dataclass
class Row:
    id: str
    merchant: str
    total: str
    date: str
    text: str


def load_jsonl(path: Path) -> List[Row]:
    rows: List[Row] = []
    with path.open("r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            obj = json.loads(line)
            rows.append(
                Row(
                    id=str(obj.get("id", "")),
                    merchant=str(obj.get("merchant", "")),
                    total=str(obj.get("total", "")),
                    date=str(obj.get("date", "")),
                    text=str(obj.get("text", "")),
                )
            )
    return rows


def cer(gt: str, pred: str) -> float:
    if len(gt) == 0:
        return 0.0 if len(pred) == 0 else 1.0
    dist = Levenshtein.distance(gt, pred)
    return dist / len(gt)


def exact_match(a: str, b: str) -> bool:
    return a.strip() == b.strip()


def evaluate(gt_rows: List[Row], pred_rows: List[Row]) -> Dict[str, float]:
    pred_map = {r.id: r for r in pred_rows}

    n = 0
    cer_sum = 0.0
    merchant_ok = 0
    total_ok = 0
    date_ok = 0
    missing = 0

    for gt in gt_rows:
        n += 1
        pred = pred_map.get(gt.id)
        if pred is None:
            missing += 1
            cer_sum += 1.0
            continue

        cer_sum += cer(gt.text, pred.text)
        merchant_ok += 1 if exact_match(gt.merchant, pred.merchant) else 0
        total_ok += 1 if exact_match(gt.total, pred.total) else 0
        date_ok += 1 if exact_match(gt.date, pred.date) else 0

    if n == 0:
        return {
            "count": 0,
            "text_cer": 0.0,
            "merchant_exact_match_rate": 0.0,
            "total_exact_match_rate": 0.0,
            "date_exact_match_rate": 0.0,
            "missing_prediction_rate": 0.0,
        }

    return {
        "count": n,
        "text_cer": cer_sum / n,
        "merchant_exact_match_rate": merchant_ok / n,
        "total_exact_match_rate": total_ok / n,
        "date_exact_match_rate": date_ok / n,
        "missing_prediction_rate": missing / n,
    }


def main():
    gt_path = Path("data/ground_truth.jsonl")
    pred_path = Path("data/predictions.jsonl")

    if not gt_path.exists():
        raise FileNotFoundError(f"ground truth not found: {gt_path}")
    if not pred_path.exists():
        raise FileNotFoundError(f"predictions not found: {pred_path}")

    gt_rows = load_jsonl(gt_path)
    pred_rows = load_jsonl(pred_path)

    result = evaluate(gt_rows, pred_rows)
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()