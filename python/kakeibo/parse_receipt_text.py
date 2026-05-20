"""Parse raw receipt OCR text into a structured ParsedReceipt.

Pure stdlib parser. No OCR API calls happen here — input is text that has
already been extracted by an external OCR step.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Optional

from .types import ReceiptInput, TaxRateHint


# Lines that contain any of these keywords are receipt metadata (subtotals,
# tax-breakdown, payment, store-info) and must never be treated as items.
_META_KEYWORDS: tuple[str, ...] = (
    "合計",
    "合 計",
    "値引",
    "値下",
    "お預り",
    "お釣",
    "対象",
    "消費税",
    "領収",
    "領 収",
    "レジ",
    "責No",
    "登録番号",
    "電話",
)

_DATE_RE = re.compile(r"(\d{4})年\s*(\d{1,2})月\s*(\d{1,2})日")
_TOTAL_RE = re.compile(r"合\s*計\s*¥?\s*(\d+(?:[\.,]\d+)?)")
# An item line has a description followed by a ¥-prefixed price, optionally
# trailed by 軽 (reduced-rate marker) and incidental whitespace.
_ITEM_RE = re.compile(r"^(?P<desc>.+?)\s*¥(?P<amount>\d+(?:[\.,]\d+)?)\s*(?P<mark>軽)?\s*$")

# Lines that look like address/phone/store-info — used by merchant detection
# to skip past header noise.  We treat the first non-empty meaningful line
# that does not match any of these patterns as the merchant.
_MERCHANT_SKIP_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"^[\s=\-]+$"),                  # divider lines
    re.compile(r"電話"),
    re.compile(r"登録番号"),
    re.compile(r"レジ"),
    re.compile(r"責No"),
    re.compile(r"\d{4}年"),                      # date line
    re.compile(r"領\s*収"),
)


@dataclass(frozen=True)
class ParsedReceipt:
    receipt_input: ReceiptInput
    per_item_amounts: list[float] = field(default_factory=list)
    per_item_tax_rate_hints: list[Optional[TaxRateHint]] = field(default_factory=list)


def parse_receipt_text(raw_text: str) -> ParsedReceipt:
    """Parse a raw receipt text blob into a ParsedReceipt.

    Empty or whitespace-only input yields a ParsedReceipt with empty fields.
    Missing date and/or total simply result in None on the ReceiptInput.
    """
    lines = [line.rstrip() for line in (raw_text or "").splitlines()]

    merchant = _detect_merchant(lines)
    purchased_at = _detect_date(lines)
    total_amount = _detect_total(lines)

    items: list[str] = []
    per_item_amounts: list[float] = []
    per_item_tax_rate_hints: list[Optional[TaxRateHint]] = []

    for line in lines:
        stripped = line.strip()
        if not stripped:
            continue
        if _is_meta_line(stripped):
            continue
        match = _ITEM_RE.match(stripped)
        if not match:
            continue
        desc = match.group("desc").strip()
        if not desc:
            continue
        amount_str = match.group("amount").replace(",", "")
        try:
            amount = float(amount_str)
        except ValueError:
            continue
        hint: Optional[TaxRateHint] = "reduced" if match.group("mark") == "軽" else "standard"
        items.append(desc)
        per_item_amounts.append(amount)
        per_item_tax_rate_hints.append(hint)

    receipt_input = ReceiptInput(
        merchant_raw=merchant,
        items=items,
        total_amount=total_amount,
        purchased_at=purchased_at,
    )
    return ParsedReceipt(
        receipt_input=receipt_input,
        per_item_amounts=per_item_amounts,
        per_item_tax_rate_hints=per_item_tax_rate_hints,
    )


def _is_meta_line(stripped: str) -> bool:
    if stripped.startswith("("):
        return True
    for keyword in _META_KEYWORDS:
        if keyword in stripped:
            return True
    return False


def _detect_merchant(lines: list[str]) -> str:
    for raw in lines:
        candidate = raw.strip()
        if not candidate:
            continue
        if any(pat.search(candidate) for pat in _MERCHANT_SKIP_PATTERNS):
            continue
        return candidate
    return ""


def _detect_date(lines: list[str]) -> Optional[str]:
    for raw in lines:
        match = _DATE_RE.search(raw)
        if match:
            year, month, day = match.groups()
            return f"{int(year):04d}-{int(month):02d}-{int(day):02d}"
    return None


def _detect_total(lines: list[str]) -> Optional[float]:
    for raw in lines:
        stripped = raw.strip()
        if "合計" not in stripped and "合 計" not in stripped:
            continue
        # Skip subtotal/discount-total style lines that live inside parens
        # (e.g. "(商品合計 ¥428)" or "(値引合計 -20)").
        if stripped.startswith("("):
            continue
        if "値引" in stripped or "商品" in stripped:
            continue
        match = _TOTAL_RE.search(stripped)
        if match:
            try:
                return float(match.group(1).replace(",", ""))
            except ValueError:
                continue
    return None
