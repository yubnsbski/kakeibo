"""Tesseract OCR + field extraction (完全版: ペアリング + 日付抽出)."""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from datetime import date as date_type
from typing import Optional
import numpy as np
import pytesseract

_TESSERACT_CONFIG = r"-l jpn+eng --psm 6"

_AMOUNT_PATTERNS = [
    re.compile(r"(?:合計|計|お会計|総額|TOTAL)[^\d]{0,20}(\d{1,3}(?:,\d{3})*|\d+)\s*円?"),
    re.compile(r"¥\s*(\d{1,3}(?:,\d{3})*|\d+)"),
    re.compile(r"(\d{1,3}(?:,\d{3})*|\d+)\s*円"),
]

_LINE_AMOUNT_RE = re.compile(
    r"^(?P<name>.+?)[\s\u3000]+¥?(?P<amount>\d{1,3}(?:,\d{3})*|\d+)\s*円?\s*\*?\s*$"
)

_NUM_ONLY_RE = re.compile(
    r"^¥?\s*(?P<amount>\d{1,3}(?:,\d{3})*|\d+)\s*円?\s*\*?\s*$"
)

_DATE_PATTERNS = [
    re.compile(r"(\d{4})[-/年](\d{1,2})[-/月](\d{1,2})"),
]

_EXCLUDE_KEYWORDS = (
    "合計", "小計", "計", "お会計", "総額", "TOTAL",
    "税", "消費税", "内税", "外税",
    "釣り", "お預り", "預り", "おつり",
    "ポイント", "クレジット", "現金", "電子", "カード",
    "サイン", "領収", "レジ", "担当", "店員",
    "発行", "登録", "番号", "TEL", "FAX",
    "営業時間", "本日", "店舗", "住所",
)

_CJK_RE = re.compile(r"[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]")


@dataclass
class OcrLineItem:
    name: str
    amount: Optional[int] = None


@dataclass
class OcrFields:
    raw_text: str
    merchant_raw: str
    items: list[str] = field(default_factory=list)
    line_items: list[OcrLineItem] = field(default_factory=list)
    total_amount: Optional[int] = None
    purchased_at: Optional[date_type] = None


def run_ocr(image: np.ndarray) -> str:
    return pytesseract.image_to_string(image, config=_TESSERACT_CONFIG)


def _extract_total_amount(text: str) -> Optional[int]:
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


def _extract_purchased_date(text_str: str) -> Optional[date_type]:
    for pat in _DATE_PATTERNS:
        m = pat.search(text_str)
        if m:
            try:
                y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
                if 2000 <= y <= 2100 and 1 <= mo <= 12 and 1 <= d <= 31:
                    return date_type(y, mo, d)
            except (ValueError, OverflowError):
                continue
    return None


def _extract_merchant(lines: list[str]) -> str:
    for line in lines:
        stripped = line.strip()
        if len(stripped) >= 2 and not stripped.isdigit():
            return stripped
    return ""


def _is_excluded_line(text: str) -> bool:
    return any(kw in text for kw in _EXCLUDE_KEYWORDS)


def _try_num_only(text_line):
    m = _NUM_ONLY_RE.match(text_line)
    if not m:
        return None
    s = m.group("amount").replace(",", "")
    try:
        n = int(s)
        if 1 <= n < 100000:
            return n
    except ValueError:
        pass
    return None


def _try_line_amount(text_line):
    m = _LINE_AMOUNT_RE.match(text_line)
    if not m:
        return None
    name = m.group("name").strip()
    if not name or not _CJK_RE.search(name):
        return None
    s = m.group("amount").replace(",", "")
    try:
        n = int(s)
        if 1 <= n < 100000:
            return (name, n)
    except ValueError:
        pass
    return None


def _extract_line_items(lines: list[str]) -> list[OcrLineItem]:
    items: list[OcrLineItem] = []
    i = 0
    while i < len(lines):
        cur = lines[i].strip()
        i += 1
        if not cur or len(cur) < 2:
            continue
        if re.fullmatch(r"[\d,円¥\s\u3000\*]+", cur):
            continue
        if _is_excluded_line(cur):
            continue
        if not _CJK_RE.search(cur):
            continue
        same_line = _try_line_amount(cur)
        if same_line is not None:
            name, amount = same_line
            items.append(OcrLineItem(name=name, amount=amount))
            continue
        if i < len(lines):
            nxt = lines[i].strip()
            paired_amount = _try_num_only(nxt)
            if paired_amount is not None and not _is_excluded_line(nxt):
                items.append(OcrLineItem(name=cur, amount=paired_amount))
                i += 1
                continue
        items.append(OcrLineItem(name=cur, amount=None))
    return items[:20]


def _legacy_items_for_compat(line_items: list[OcrLineItem]) -> list[str]:
    return [it.name for it in line_items]


def extract_receipt_fields(raw_text: str) -> OcrFields:
    lines = [line for line in raw_text.splitlines() if line.strip()]
    merchant = _extract_merchant(lines)
    line_items = _extract_line_items(lines[1:])
    return OcrFields(
        raw_text=raw_text,
        merchant_raw=merchant,
        items=_legacy_items_for_compat(line_items),
        line_items=line_items,
        total_amount=_extract_total_amount(raw_text),
        purchased_at=_extract_purchased_date(raw_text),
    )
