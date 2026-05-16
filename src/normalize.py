"""Merchant name normalization — Python port of src/normalizeMerchant.ts.

Mirrors the TypeScript regex sequence exactly. Note:
- `re.sub` uses Python re engine (PCRE-like); the patterns here use only
  literal characters and the JS `\\s+` is equivalent to Python `\\s+` in
  this context (CJK whitespace handling).
- Order of replacements matters: half-width katakana variants must be
  caught before the full-width fallback patterns.
"""
from __future__ import annotations

import re


def normalize_merchant(raw: str) -> str:
    """Normalize a raw merchant string to its canonical form.

    Examples:
        >>> normalize_merchant("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店")
        'セブンイレブン渋谷店'
        >>> normalize_merchant("ファミマ 池袋")
        'ファミリーマート池袋'
    """
    text = raw.strip()
    text = re.sub(r"\s+", "", text)
    text = re.sub(r"ｾﾌﾞﾝ[-ー]?ｲﾚﾌﾞﾝ", "セブンイレブン", text)
    text = re.sub(r"セブン[-ー]?イレブン", "セブンイレブン", text)
    text = text.replace("ファミマ", "ファミリーマート")
    text = text.replace("ﾏﾂｷﾖ", "マツモトキヨシ")
    text = text.replace("ドン・キホーテ", "ドンキホーテ")
    return text
