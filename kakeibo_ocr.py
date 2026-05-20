"""kakeibo OCR - Single-file Streamlit + Gemini receipt parser.

仕様書（改訂版）に基づく最小実装。
- OCR本体: Google Gemini (Vision)
- 入力: レシート画像（JPEG/PNG/HEIC）
- 出力: 構造化 JSON（店名・日時・合計・税・明細・信頼度）

Run:
    pip install streamlit google-genai pillow pydantic
    export GEMINI_API_KEY=...
    streamlit run kakeibo_ocr.py
"""

from __future__ import annotations

import io
import json
import os
from datetime import datetime
from typing import Optional

import streamlit as st
from google import genai
from google.genai import types
from PIL import Image
from pydantic import BaseModel, Field, ValidationError

try:
    from pillow_heif import register_heif_opener

    register_heif_opener()
except ImportError:
    pass


# ---------- Data models ----------
class Item(BaseModel):
    name: str
    price: float
    qty: int = 1


class Receipt(BaseModel):
    store_name: Optional[str] = None
    purchased_at: Optional[str] = None
    total: Optional[float] = None
    tax: Optional[float] = None
    items: list[Item] = Field(default_factory=list)
    confidence: float = 0.0


# ---------- Prompt ----------
SYSTEM_PROMPT = """\
You are a receipt OCR engine for a Japanese household budget app (kakeibo).
Extract fields from the receipt image and return ONLY valid JSON with this schema:
{
  "store_name": string | null,
  "purchased_at": ISO8601 string | null,
  "total": number | null,
  "tax": number | null,
  "items": [{"name": string, "price": number, "qty": number}],
  "confidence": number between 0 and 1
}
Rules:
- Amounts are JPY (integers usually).
- purchased_at: use the date printed on the receipt; assume JST if no timezone is shown.
- Use null when a field cannot be read with confidence.
- Output JSON only. No prose, no markdown fences.
"""


# ---------- Core ----------
def preprocess(image: Image.Image, max_side: int = 2000) -> Image.Image:
    """Convert to RGB and downscale to keep API payload reasonable."""
    img = image.convert("RGB")
    w, h = img.size
    if max(w, h) > max_side:
        scale = max_side / max(w, h)
        img = img.resize((int(w * scale), int(h * scale)))
    return img


def image_to_png_bytes(image: Image.Image) -> bytes:
    buf = io.BytesIO()
    image.save(buf, format="PNG")
    return buf.getvalue()


def call_vlm(image: Image.Image, model: str, api_key: str) -> Receipt:
    client = genai.Client(api_key=api_key)
    png_bytes = image_to_png_bytes(image)

    response = client.models.generate_content(
        model=model,
        contents=[
            types.Part.from_bytes(data=png_bytes, mime_type="image/png"),
            "このレシート画像を解析して JSON を返してください。",
        ],
        config=types.GenerateContentConfig(
            system_instruction=SYSTEM_PROMPT,
            response_mime_type="application/json",
            temperature=0.0,
        ),
    )

    raw = response.text or "{}"
    data = json.loads(raw)
    return Receipt(**data)


# ---------- UI ----------
def main() -> None:
    st.set_page_config(page_title="kakeibo OCR", page_icon="🧾", layout="wide")
    st.title("🧾 kakeibo OCR")
    st.caption("Gemini Vision でレシートを解析して家計簿用 JSON を生成します。")

    with st.sidebar:
        st.header("設定")
        api_key = st.text_input(
            "Gemini API Key",
            type="password",
            value=os.getenv("GEMINI_API_KEY", "") or os.getenv("GOOGLE_API_KEY", ""),
            help="環境変数 GEMINI_API_KEY / GOOGLE_API_KEY からも読み込みます。",
        )
        model = st.selectbox(
            "モデル",
            ["gemini-2.5-flash", "gemini-2.5-pro", "gemini-2.0-flash"],
            index=0,
        )
        st.markdown("---")
        st.markdown("**仕様**：2 週間スプリント / Codex 駆動")

    uploaded = st.file_uploader(
        "レシート画像をアップロード", type=["jpg", "jpeg", "png", "heic", "webp"]
    )

    if not uploaded:
        st.info("画像をアップロードしてください。")
        return

    try:
        image = preprocess(Image.open(uploaded))
    except Exception as e:
        st.error(f"画像を読み込めませんでした: {e}")
        return

    col1, col2 = st.columns([1, 1])

    with col1:
        st.subheader("入力画像")
        st.image(image, use_container_width=True)

    with col2:
        st.subheader("解析結果")
        if not st.button("解析する", type="primary", use_container_width=True):
            return
        if not api_key:
            st.error("Gemini API Key が必要です。")
            return

        with st.spinner("Gemini に問い合わせ中..."):
            try:
                receipt = call_vlm(image, model, api_key)
            except (json.JSONDecodeError, ValidationError) as e:
                st.error(f"JSON の解析に失敗しました: {e}")
                return
            except Exception as e:
                st.error(f"API 呼び出しに失敗しました: {e}")
                return

        st.success("解析完了")

        m1, m2, m3 = st.columns(3)
        m1.metric("合計", f"¥{receipt.total:,.0f}" if receipt.total is not None else "—")
        m2.metric("税額", f"¥{receipt.tax:,.0f}" if receipt.tax is not None else "—")
        m3.metric("信頼度", f"{receipt.confidence:.2f}")

        st.write(f"**店名**：{receipt.store_name or '—'}")
        st.write(f"**日時**：{receipt.purchased_at or '—'}")

        if receipt.items:
            st.subheader("明細")
            st.dataframe(
                [item.model_dump() for item in receipt.items],
                use_container_width=True,
                hide_index=True,
            )

        st.subheader("JSON")
        json_str = receipt.model_dump_json(indent=2)
        st.code(json_str, language="json")
        st.download_button(
            "JSON をダウンロード",
            json_str,
            file_name=f"receipt_{datetime.now().strftime('%Y%m%d_%H%M%S')}.json",
            mime="application/json",
        )


if __name__ == "__main__":
    main()
