"""Tesseract OCR + field extraction."""
from __future__ import annotations
import re
from dataclasses import dataclass
import numpy as np
import pytesseract

_TESSERACT_CONFIG = r"-l jpn+eng --psm 6"

_AMOUNT_PATTERNS = [
    re.compile(r"(?:合計|計|お会計|総額|TOTAL)[^\d]{0,5}(\d{1,3}(?:,\d{3})*|\d+)\s*円?"),
    re.compile(r"¥\s*(\d{1,3}(?:,\d{3})*|\d+)"),
    re.compile(r"(\d{1,3}(?:,\d{3})*|\d+)\s*円"),
]


@dataclass
class OcrFields:
    raw_text: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None


def run_ocr(image: np.ndarray) -> str:
    return pytesseract.image_to_string(image, config=_TESSERACT_CONFIG)


def _extract_amount(text: str) -> int | None:
    candidates: list[int] = []
    for pat in _AMOUNT_PATTERNS:
        for m in pat.finditer(text):
            digits = m.group(1).replace(",", "")
            try:
                candidates.append(int(digits))
            except ValueError:
                continue
        if candidates:
            return max(candidates)
    return None


def _extract_merchant(lines: list[str]) -> str:
    for line in lines:
        stripped = line.strip()
        if len(stripped) >= 2 and not stripped.isdigit():
            return stripped
    return ""


def _extract_items(lines: list[str]) -> list[str]:
    items: list[str] = []
    cjk = re.compile(r"[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]")
    for line in lines:
        stripped = line.strip()
        if not stripped or len(stripped) < 2:
            continue
        if not cjk.search(stripped):
            continue
        if re.fullmatch(r"[\d,円¥\s]+", stripped):
            continue
        if re.search(r"合計|小計|計|お会計|総額|税|釣り|お預り", stripped):
            continue
        items.append(stripped)
    return items[:10]


def extract_receipt_fields(raw_text: str) -> OcrFields:
    lines = [line for line in raw_text.splitlines() if line.strip()]
    return OcrFields(
        raw_text=raw_text,
        merchant_raw=_extract_merchant(lines),
        items=_extract_items(lines[1:]),
        total_amount=_extract_amount(raw_text),
    )
