"""Merchant name normalization."""
from __future__ import annotations
import re


def normalize_merchant(raw: str) -> str:
    text = raw.strip()
    text = re.sub(r"\s+", "", text)
    text = re.sub(r"ｾﾌﾞﾝ[-ー]?ｲﾚﾌﾞﾝ", "セブンイレブン", text)
    text = re.sub(r"セブン[-ー]?イレブン", "セブンイレブン", text)
    text = text.replace("ファミマ", "ファミリーマート")
    text = text.replace("ﾏﾂｷﾖ", "マツモトキヨシ")
    text = text.replace("ドン・キホーテ", "ドンキホーテ")
    return text
