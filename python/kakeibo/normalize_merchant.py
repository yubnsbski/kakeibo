"""Normalize merchant strings (mirror of TS implementation)."""
from __future__ import annotations

import re

_WHITESPACE_RE = re.compile(r"\s+")
_HALF_WIDTH_SEVEN = re.compile(r"ｾﾌﾞﾝ[-ー]?ｲﾚﾌﾞﾝ")
_FULL_WIDTH_SEVEN = re.compile(r"セブン[-ー]?イレブン")


def normalize_merchant(raw: str) -> str:
    text = _WHITESPACE_RE.sub("", raw.strip())
    text = _HALF_WIDTH_SEVEN.sub("セブンイレブン", text)
    text = _FULL_WIDTH_SEVEN.sub("セブンイレブン", text)
    text = text.replace("ファミマ", "ファミリーマート")
    text = text.replace("ﾏﾂｷﾖ", "マツモトキヨシ")
    text = text.replace("ドン・キホーテ", "ドンキホーテ")
    return text
