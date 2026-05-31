#!/usr/bin/env bash
# Gemini API による OCR (画像→構造化JSON). Tesseract フォールバック付き.
#
# 前提:
#   - backend/.env に GEMINI_API_KEY=xxx を設定済みであること
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_gemini_ocr.sh

set -u
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "Gemini API OCR セットアップ"
echo "============================================================"

# ===========================================================================
# 0. ネットワーク疎通確認
# ===========================================================================
echo "==> [0] Gemini API への疎通確認"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 10 \
  "https://generativelanguage.googleapis.com/v1beta/models" 2>&1 || echo "FAIL")
if [ "$HTTP_CODE" = "FAIL" ] || [ "$HTTP_CODE" = "000" ]; then
  echo "  ⚠ WARNING: generativelanguage.googleapis.com に到達できません"
  echo "  Codespaces のネットワーク設定でこのドメインを許可する必要があります"
  echo "  (このまま続行しますが、実行時に通信エラーになる可能性があります)"
else
  echo "  OK: 疎通確認 (HTTP $HTTP_CODE — 401/403でもドメイン到達はOK)"
fi
echo ""

# ===========================================================================
# 1. google-genai パッケージ追加
# ===========================================================================
echo "==> [1] google-genai パッケージインストール"
cd "$REPO/backend"
uv add google-genai 2>&1 | tail -5 || pip install google-genai --break-system-packages 2>&1 | tail -5
cd "$REPO"
echo ""

# ===========================================================================
# 2. .env テンプレート作成 (キー未設定なら)
# ===========================================================================
echo "==> [2] .env 確認"
if [ ! -f backend/.env ]; then
  cat > backend/.env <<'ENVEOF'
# Gemini API キー (https://aistudio.google.com/apikey で取得)
GEMINI_API_KEY=
ENVEOF
  echo "  backend/.env を作成しました"
  echo "  ⚠ GEMINI_API_KEY= の後にキーを記入してください"
else
  echo "  backend/.env 既存"
fi

# .gitignore に .env 追加
if [ -f .gitignore ] && ! grep -q "^\.env$\|backend/\.env" .gitignore; then
  echo "backend/.env" >> .gitignore
  echo "  .gitignore に backend/.env 追加"
fi
echo ""

# ===========================================================================
# 3. backend/app/ocr/gemini_extract.py 新規作成
# ===========================================================================
echo "==> [3] backend/app/ocr/gemini_extract.py"
cat > backend/app/ocr/gemini_extract.py <<'PYEOF'
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
PYEOF
echo ""

# ===========================================================================
# 4. backend/app/routers/receipts.py を Gemini優先 + Tesseractフォールバックに
# ===========================================================================
echo "==> [4] backend/app/routers/receipts.py"
cat > backend/app/routers/receipts.py <<'PYEOF'
"""Receipt upload: Gemini API OCR (Tesseract fallback) → auto-save + items."""
from __future__ import annotations
from datetime import date, datetime
from pathlib import Path
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from app.classifier import classify_line_items, classify_receipt, ReceiptInput
from app.database import get_session
from app.models import (
    CategoryMaster, Receipt, Transaction, TransactionItem,
    UserCategoryOverride, calc_tax_amount,
)
from app.ocr import extract_receipt_fields, load_image, preprocess_for_ocr, run_ocr
from app.ocr.gemini_extract import extract_with_gemini, is_gemini_available

router = APIRouter(prefix="/api/receipts", tags=["receipts"])

_BACKEND_ROOT = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = _BACKEND_ROOT / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

_ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}
_MAX_BYTES = 15 * 1024 * 1024

_MIME_MAP = {
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
    ".png": "image/png", ".webp": "image/webp",
    ".heic": "image/heic", ".heif": "image/heif",
}


class LineItemOut(BaseModel):
    item: str
    amount: int
    amount_extracted: bool
    category: str | None
    reason: str


class ReceiptUploadResponse(BaseModel):
    transaction_id: int
    filename: str
    ocr_engine: str  # "gemini" or "tesseract"
    raw_text: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None
    tax_amount: int
    classification: dict
    line_items: list[LineItemOut]
    items_created: int
    items_with_amount: int


def _load_overrides(session: Session) -> dict:
    rows = session.exec(select(UserCategoryOverride)).all()
    return {row.merchant_pattern: row.category for row in rows}


def _tax_rate_for(category: str | None, session: Session) -> int:
    if category is None:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


@router.post("/upload", response_model=ReceiptUploadResponse)
async def upload_receipt(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
) -> ReceiptUploadResponse:
    ext = Path(file.filename or "").suffix.lower()
    if ext not in _ALLOWED_EXT:
        raise HTTPException(status_code=400, detail=f"unsupported: {ext}")
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"too large: {len(data)}")

    stamp = datetime.utcnow().strftime("%Y%m%dT%H%M%S%f")
    safe_name = f"{stamp}{ext}"
    (UPLOAD_DIR / safe_name).write_bytes(data)

    overrides = _load_overrides(session)
    mime = _MIME_MAP.get(ext, "image/jpeg")

    # ===== OCR エンジン選択 =====
    ocr_engine = "tesseract"
    merchant_raw = ""
    raw_text = ""
    total_amount = None
    purchased_at_val = date.today()
    # (name, amount, category, amount_extracted)
    parsed_items: list[tuple[str, int, str | None, bool]] = []

    gemini_ok = False
    if is_gemini_available():
        try:
            g = extract_with_gemini(data, mime_type=mime)
            ocr_engine = "gemini"
            gemini_ok = True
            merchant_raw = g.merchant or "(不明)"
            raw_text = g.raw_json
            total_amount = g.total_amount
            if g.purchased_at:
                purchased_at_val = g.purchased_at
            for li in g.line_items:
                parsed_items.append((li.name, li.amount, li.category, li.amount > 0))
        except Exception as e:
            # フォールバック
            raw_text = f"[Gemini失敗→Tesseract] {e}"
            gemini_ok = False

    if not gemini_ok:
        # Tesseract フォールバック
        try:
            bgr = load_image(data)
        except Exception as e:
            raise HTTPException(status_code=400, detail=f"decode failed: {e}") from e
        preprocessed = preprocess_for_ocr(bgr)
        tess_text = run_ocr(preprocessed)
        fields = extract_receipt_fields(tess_text)
        ocr_engine = "tesseract"
        merchant_raw = fields.merchant_raw
        raw_text = tess_text
        total_amount = fields.total_amount
        if getattr(fields, "purchased_at", None):
            purchased_at_val = fields.purchased_at
        # Tesseract は明細分類を別途
        item_names = [li.name for li in fields.line_items]
        lcs = classify_line_items(item_names, fields.merchant_raw, overrides or None)
        for ocr_item, lc in zip(fields.line_items, lcs):
            amt = ocr_item.amount or 0
            parsed_items.append((ocr_item.name, amt, lc.category, ocr_item.amount is not None))

    # ===== Receipt レコード =====
    receipt_row = Receipt(filename=safe_name, ocr_text=raw_text, status="linked")
    session.add(receipt_row)
    session.flush()

    # ===== ヘッダ分類 =====
    item_name_list = [name for (name, _a, _c, _e) in parsed_items]
    classification = classify_receipt(ReceiptInput(
        merchantRaw=merchant_raw,
        items=item_name_list,
        totalAmount=total_amount,
        userCategoryOverrides=overrides if overrides else None,
    ))

    # Gemini が明細カテゴリを返している場合、ヘッダカテゴリは最大金額明細から
    header_category = classification.category
    if gemini_ok and parsed_items:
        by_cat: dict[str, int] = {}
        for (_n, amt, cat, _e) in parsed_items:
            if cat:
                by_cat[cat] = by_cat.get(cat, 0) + amt
        if by_cat:
            header_category = max(by_cat.items(), key=lambda x: x[1])[0]

    amount = total_amount or sum(a for (_n, a, _c, _e) in parsed_items) or 0
    tax_rate = _tax_rate_for(header_category, session)
    tax_amt = calc_tax_amount(amount, tax_rate)

    tx = Transaction(
        merchant_raw=merchant_raw,
        merchant_normalized=classification.merchantNormalized or merchant_raw,
        items_text="|".join(item_name_list),
        screening_category=header_category,
        needs_review=classification.needsReview,
        reason=f"{ocr_engine}: {classification.reason}",
        confidence=classification.confidence,
        amount=amount,
        tax_amount=tax_amt,
        purchased_at=purchased_at_val,
        status="auto_saved",
        ocr_raw_text=raw_text,
        receipt_image_id=receipt_row.id,
    )
    session.add(tx)
    session.flush()
    tx_id = tx.id

    # ===== 明細 INSERT =====
    items_created = 0
    items_with_amount = 0
    response_items: list[LineItemOut] = []
    for sort_idx, (name, amt, cat, extracted) in enumerate(parsed_items):
        item_rate = _tax_rate_for(cat, session)
        session.add(TransactionItem(
            transaction_id=tx_id, name=name, amount=amt,
            tax_amount=calc_tax_amount(amt, item_rate),
            category=cat, sort_order=sort_idx,
        ))
        items_created += 1
        if extracted and amt > 0:
            items_with_amount += 1
        response_items.append(LineItemOut(
            item=name, amount=amt, amount_extracted=extracted,
            category=cat, reason=f"{ocr_engine}_extract",
        ))

    session.commit()
    session.refresh(tx)

    return ReceiptUploadResponse(
        transaction_id=tx_id,
        filename=safe_name,
        ocr_engine=ocr_engine,
        raw_text=raw_text,
        merchant_raw=merchant_raw,
        items=item_name_list,
        total_amount=total_amount,
        tax_amount=tax_amt,
        classification=classification.model_dump(),
        line_items=response_items,
        items_created=items_created,
        items_with_amount=items_with_amount,
    )
PYEOF
echo ""

# ===========================================================================
# 5. 構文チェック
# ===========================================================================
echo "==> [5] 構文チェック"
python3 -c "import ast; ast.parse(open('backend/app/ocr/gemini_extract.py').read()); print('  gemini_extract.py OK')"
python3 -c "import ast; ast.parse(open('backend/app/routers/receipts.py').read()); print('  receipts.py OK')"
echo ""

# ===========================================================================
# 6. uvicorn 再起動
# ===========================================================================
echo "==> [6] uvicorn 再起動"
pkill -9 -f uvicorn 2>/dev/null || true
sleep 2
(cd "$REPO/backend" && nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 6
echo "  health:"
curl -s http://localhost:8000/api/health; echo
echo ""

# ===========================================================================
# 7. Gemini キー設定状況の確認
# ===========================================================================
echo "==> [7] GEMINI_API_KEY 設定確認"
if grep -q "^GEMINI_API_KEY=.\+" backend/.env 2>/dev/null; then
  echo "  ✓ キー設定済み"
  echo ""
  echo "==> 既存画像で Gemini OCR テスト"
  DUMMY=$(find backend/uploads -name "*.jpg" -o -name "*.png" 2>/dev/null | head -1)
  if [ -n "$DUMMY" ]; then
    curl -s -X POST -F "file=@$DUMMY" http://localhost:8000/api/receipts/upload | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  ocr_engine = {d[\"ocr_engine\"]}')
print(f'  merchant   = {d[\"merchant_raw\"]}')
print(f'  total      = {d[\"total_amount\"]}')
print(f'  items      = {d[\"items_created\"]}件 (金額付き {d[\"items_with_amount\"]}件)')
for li in d['line_items'][:10]:
    print(f'    - {li[\"item\"]} = {li[\"amount\"]}円 [{li[\"category\"]}]')
" 2>&1 | head -20
  fi
else
  echo "  ⚠ GEMINI_API_KEY が未設定です"
  echo "  以下を実行してキーを設定してください:"
  echo "    nano backend/.env"
  echo "  または:"
  echo "    echo 'GEMINI_API_KEY=取得したキー' > backend/.env"
  echo ""
  echo "  キー未設定の間は Tesseract で動作します (フォールバック)"
fi

cat <<EOM

============================================================
Gemini API OCR セットアップ完了.

動作:
  - GEMINI_API_KEY 設定あり → Gemini で画像→構造化抽出 (高精度)
  - キーなし or Gemini失敗 → Tesseract フォールバック
  - レスポンスの ocr_engine フィールドでどちらが使われたか分かる

キー設定 (未設定の場合):
  echo 'GEMINI_API_KEY=取得したキー' > backend/.env
  その後 uvicorn 再起動: bash scripts/start.sh

確認: ブラウザで Ctrl+Shift+R → 取込タブ → レシート画像アップロード
============================================================
EOM
