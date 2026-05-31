"""Gemini API による レシート画像 → 構造化データ抽出."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from datetime import date as date_type
from pathlib import Path
from typing import Optional

# .env 読み込み (python-dotenv 不要の簡易版)
def _load_env() -> None:
    env_path = Path(__file__).resolve().parent.parent.parent / ".env"
    if env_path.exists():
        for line in env_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, _, v = line.partition("=")
            k, v = k.strip(), v.strip()
            if k and k not in os.environ:
                os.environ[k] = v


_load_env()

GEMINI_MODEL = "gemini-2.5-flash"

# 支出カテゴリ (Gemini に判定させる)
_EXPENSE_CATEGORIES = [
    "食費", "酒類", "外食", "日用品", "交通費",
    "医療費", "娯楽費", "衣料費", "家賃", "光熱費", "通信費", "その他",
]


@dataclass
class GeminiLineItem:
    name: str
    amount: int = 0
    category: Optional[str] = None


@dataclass
class GeminiReceiptData:
    merchant: str = ""
    purchased_at: Optional[date_type] = None
    total_amount: Optional[int] = None
    line_items: list[GeminiLineItem] = field(default_factory=list)
    raw_json: str = ""


def is_gemini_available() -> bool:
    """GEMINI_API_KEY が設定されているか."""
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    return bool(key)


_PROMPT = """この画像は日本の買い物レシートです。以下の情報をJSONで抽出してください。

抽出する項目:
- merchant: 店舗名 (文字列)
- date: 購入日 (YYYY-MM-DD形式の文字列、不明なら空文字)
- total_amount: 合計金額 (整数、税込)
- items: 明細の配列。各要素は {name: 品目名, amount: 金額(整数), category: カテゴリ}

categoryは以下のいずれかを選択:
食費, 酒類, 外食, 日用品, 交通費, 医療費, 娯楽費, 衣料費, 家賃, 光熱費, 通信費, その他

注意:
- 合計・小計・税・釣り銭・ポイントの行は items に含めない
- 金額は数値のみ (円記号やカンマは除く)
- 判断できない項目は空文字または0
- JSON以外の文字 (説明やマークダウン) は一切出力しない

出力例:
{"merchant":"セブンイレブン","date":"2026-05-15","total_amount":620,"items":[{"name":"おにぎり","amount":130,"category":"食費"},{"name":"ビール","amount":350,"category":"酒類"}]}
"""


def extract_with_gemini(image_bytes: bytes, mime_type: str = "image/jpeg") -> GeminiReceiptData:
    """Gemini API でレシート画像を構造化抽出.

    Raises:
        RuntimeError: API キー未設定、API エラー時
    """
    api_key = os.environ.get("GEMINI_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY が未設定です")

    try:
        from google import genai
        from google.genai import types
    except ImportError as e:
        raise RuntimeError(f"google-genai パッケージが未インストール: {e}") from e

    client = genai.Client(api_key=api_key)

    try:
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=[
                types.Part.from_bytes(data=image_bytes, mime_type=mime_type),
                _PROMPT,
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                temperature=0.0,
            ),
        )
    except Exception as e:
        raise RuntimeError(f"Gemini API 呼び出し失敗: {e}") from e

    raw = (response.text or "").strip()
    # マークダウンコードフェンス除去 (念のため)
    if raw.startswith("```"):
        raw = raw.split("```", 2)[1] if "```" in raw[3:] else raw
        raw = raw.replace("json", "", 1).strip("`").strip()

    try:
        data = json.loads(raw)
    except json.JSONDecodeError as e:
        raise RuntimeError(f"Gemini 応答のJSON解析失敗: {e} / raw={raw[:200]}") from e

    # date パース
    purchased = None
    date_str = (data.get("date") or "").strip()
    if date_str:
        try:
            y, m, d = date_str.split("-")
            purchased = date_type(int(y), int(m), int(d))
        except (ValueError, AttributeError):
            purchased = None

    # items パース
    items: list[GeminiLineItem] = []
    for it in data.get("items", []):
        if not isinstance(it, dict):
            continue
        name = str(it.get("name", "")).strip()
        if not name:
            continue
        try:
            amount = int(it.get("amount", 0) or 0)
        except (ValueError, TypeError):
            amount = 0
        category = it.get("category")
        if category not in _EXPENSE_CATEGORIES:
            category = None
        items.append(GeminiLineItem(name=name, amount=amount, category=category))

    # total_amount
    try:
        total = int(data.get("total_amount", 0) or 0)
        total = total if total > 0 else None
    except (ValueError, TypeError):
        total = None

    return GeminiReceiptData(
        merchant=str(data.get("merchant", "")).strip(),
        purchased_at=purchased,
        total_amount=total,
        line_items=items,
        raw_json=raw,
    )
