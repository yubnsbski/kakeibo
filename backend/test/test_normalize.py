"""Tests for normalize_merchant.

These exercise the regex sequence in src/normalizeMerchant.ts.
"""
from __future__ import annotations

import pytest

from app.classifier import normalize_merchant


@pytest.mark.parametrize(
    "raw, expected",
    [
        # half-width katakana → full-width
        ("ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店", "セブンイレブン渋谷店"),
        ("ｾﾌﾞﾝｲﾚﾌﾞﾝ 池袋", "セブンイレブン池袋"),
        # full-width hyphen / dash variants
        ("セブン-イレブン 新宿", "セブンイレブン新宿"),
        ("セブンーイレブン 横浜", "セブンイレブン横浜"),
        ("セブンイレブン 大宮", "セブンイレブン大宮"),
        # other normalizations
        ("ファミマ 池袋", "ファミリーマート池袋"),
        ("ﾏﾂｷﾖ 渋谷", "マツモトキヨシ渋谷"),
        ("ドン・キホーテ 新宿", "ドンキホーテ新宿"),
        # whitespace collapsing
        ("  サンプル  店  ", "サンプル店"),
        # no-op cases
        ("ローソン 本店", "ローソン本店"),
        ("Amazon.co.jp", "Amazon.co.jp"),
    ],
)
def test_normalize_merchant(raw: str, expected: str):
    assert normalize_merchant(raw) == expected
