#!/usr/bin/env bash
# OCR から明細別金額を自動抽出 + 明細自動振り分け強化.
#
# 動作:
#   - OCR で「品目名 + 金額」が同じ行にある明細を抽出
#   - 抽出失敗した明細は amount=0 で作成 (ユーザー補完)
#   - 抽出できた明細は金額+カテゴリ自動付与
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_line_amount.sh

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "OCR → 明細別金額自動抽出"
echo "============================================================"

# ===========================================================================
# 1. backend/app/ocr/extract.py を line_items 抽出対応に拡張
# ===========================================================================
echo "==> backend/app/ocr/extract.py"
cat > backend/app/ocr/extract.py <<'EOF'
"""Tesseract OCR + field extraction with per-line item amount extraction."""
from __future__ import annotations
import re
from dataclasses import dataclass, field
from typing import Optional
import numpy as np
import pytesseract

_TESSERACT_CONFIG = r"-l jpn+eng --psm 6"

# レシート全体の合計金額抽出パターン
_AMOUNT_PATTERNS = [
    re.compile(r"(?:合計|計|お会計|総額|TOTAL)[^\d]{0,5}(\d{1,3}(?:,\d{3})*|\d+)\s*円?"),
    re.compile(r"¥\s*(\d{1,3}(?:,\d{3})*|\d+)"),
    re.compile(r"(\d{1,3}(?:,\d{3})*|\d+)\s*円"),
]

# 明細行の「品目名 末尾に金額」抽出パターン
# 例: "おにぎり       130"  / "牛乳 ¥180" / "弁当 580円"
_LINE_AMOUNT_RE = re.compile(
    r"^(?P<name>.+?)[\s\u3000]+¥?(?P<amount>\d{1,3}(?:,\d{3})*|\d+)\s*円?\s*\*?\s*$"
)

# 除外キーワード (これらの単語を含む行は明細扱いしない)
_EXCLUDE_KEYWORDS = (
    "合計", "小計", "計", "お会計", "総額", "TOTAL",
    "税", "消費税", "内税", "外税",
    "釣り", "お預り", "預り", "おつり",
    "ポイント", "クレジット", "現金", "電子", "カード",
    "サイン", "領収", "レジ", "担当", "店員",
    "発行", "登録", "番号", "TEL", "FAX",
    "営業時間", "本日", "店舗", "住所",
)

# CJK 文字 (品目名は CJK を含むことを期待)
_CJK_RE = re.compile(r"[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]")


@dataclass
class OcrLineItem:
    """OCRから抽出した明細1行."""
    name: str
    amount: Optional[int] = None  # 抽出できなければ None


@dataclass
class OcrFields:
    raw_text: str
    merchant_raw: str
    items: list[str] = field(default_factory=list)            # 互換: 品目名のみ
    line_items: list[OcrLineItem] = field(default_factory=list)  # 新: name+amount
    total_amount: int | None = None


def run_ocr(image: np.ndarray) -> str:
    return pytesseract.image_to_string(image, config=_TESSERACT_CONFIG)


def _extract_total_amount(text: str) -> int | None:
    """レシート全体の合計金額を抽出."""
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


def _is_excluded_line(text: str) -> bool:
    """合計・税等の行は明細扱いしない."""
    return any(kw in text for kw in _EXCLUDE_KEYWORDS)


def _extract_line_items(lines: list[str]) -> list[OcrLineItem]:
    """各行から「品目名 + 末尾金額」を抽出.

    マッチしない場合は名前のみ (amount=None).
    """
    items: list[OcrLineItem] = []
    for line in lines:
        stripped = line.strip()
        if not stripped or len(stripped) < 2:
            continue
        # 全数値行はスキップ
        if re.fullmatch(r"[\d,円¥\s\u3000\*]+", stripped):
            continue
        # 除外キーワード行はスキップ
        if _is_excluded_line(stripped):
            continue
        # CJK 文字を含まない行はスキップ (例: "JAN1234567890")
        if not _CJK_RE.search(stripped):
            continue

        # 末尾金額抽出
        m = _LINE_AMOUNT_RE.match(stripped)
        if m:
            name = m.group("name").strip()
            amount_str = m.group("amount").replace(",", "")
            try:
                amount = int(amount_str)
                # 1円〜10万円が妥当な明細金額
                if 1 <= amount < 100000 and name:
                    items.append(OcrLineItem(name=name, amount=amount))
                    continue
            except ValueError:
                pass

        # 金額抽出失敗 → 名前のみ (amount=None)
        items.append(OcrLineItem(name=stripped, amount=None))

    return items[:20]


def _legacy_items_for_compat(line_items: list[OcrLineItem]) -> list[str]:
    """互換性のため、品目名のリストを返す."""
    return [it.name for it in line_items]


def extract_receipt_fields(raw_text: str) -> OcrFields:
    lines = [line for line in raw_text.splitlines() if line.strip()]
    merchant = _extract_merchant(lines)
    # 1行目（店舗名）以降を明細抽出対象に
    line_items = _extract_line_items(lines[1:])
    return OcrFields(
        raw_text=raw_text,
        merchant_raw=merchant,
        items=_legacy_items_for_compat(line_items),
        line_items=line_items,
        total_amount=_extract_total_amount(raw_text),
    )
EOF

# ===========================================================================
# 2. backend/app/routers/receipts.py を line_items.amount 対応に改修
# ===========================================================================
echo "==> backend/app/routers/receipts.py"
cat > backend/app/routers/receipts.py <<'EOF'
"""Receipt upload: image → OCR → classify → auto-save + auto-create items with amount."""
from __future__ import annotations
from datetime import date, datetime
from pathlib import Path
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from app.classifier import (
    ReceiptInput, classify_line_items, classify_receipt,
)
from app.database import get_session
from app.models import (
    CategoryMaster, Receipt, Transaction, TransactionItem,
    UserCategoryOverride, calc_tax_amount,
)
from app.ocr import extract_receipt_fields, load_image, preprocess_for_ocr, run_ocr

router = APIRouter(prefix="/api/receipts", tags=["receipts"])

_BACKEND_ROOT = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = _BACKEND_ROOT / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

_ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}
_MAX_BYTES = 15 * 1024 * 1024


class LineItemClassificationOut(BaseModel):
    item: str
    amount: int  # OCR抽出値 (失敗時 0)
    amount_extracted: bool  # OCR で金額抽出できたか
    category: str | None
    reason: str


class ReceiptUploadResponse(BaseModel):
    transaction_id: int
    filename: str
    raw_text: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None
    tax_amount: int
    classification: dict
    line_items: list[LineItemClassificationOut]
    items_created: int
    items_with_amount: int  # OCR金額抽出成功数


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
    saved_path = UPLOAD_DIR / safe_name
    saved_path.write_bytes(data)

    try:
        bgr = load_image(data)
    except Exception as e:
        raise HTTPException(status_code=400, detail=f"decode failed: {e}") from e

    preprocessed = preprocess_for_ocr(bgr)
    raw_text = run_ocr(preprocessed)
    fields = extract_receipt_fields(raw_text)

    receipt_row = Receipt(filename=safe_name, ocr_text=raw_text, status="linked")
    session.add(receipt_row)
    session.flush()

    overrides = _load_overrides(session)

    # ヘッダ分類
    classification = classify_receipt(ReceiptInput(
        merchantRaw=fields.merchant_raw,
        items=fields.items,
        totalAmount=fields.total_amount,
        userCategoryOverrides=overrides if overrides else None,
    ))

    amount = fields.total_amount or 0
    tax_rate = _tax_rate_for(classification.category, session)
    tax_amt = calc_tax_amount(amount, tax_rate)

    tx = Transaction(
        merchant_raw=fields.merchant_raw,
        merchant_normalized=classification.merchantNormalized,
        items_text="|".join(fields.items),
        screening_category=classification.category,
        needs_review=classification.needsReview,
        reason=classification.reason,
        confidence=classification.confidence,
        amount=amount,
        tax_amount=tax_amt,
        purchased_at=date.today(),
        status="auto_saved",
        ocr_raw_text=raw_text,
        receipt_image_id=receipt_row.id,
    )
    session.add(tx)
    session.flush()
    tx_id = tx.id

    # 明細単位分類
    item_names = [li.name for li in fields.line_items]
    line_classifications = classify_line_items(
        items=item_names,
        merchant_raw=fields.merchant_raw,
        user_overrides=overrides if overrides else None,
    )

    # 明細を transaction_items に INSERT (金額付き)
    items_created = 0
    items_with_amount = 0
    response_line_items: list[LineItemClassificationOut] = []

    for sort_idx, (ocr_item, lc) in enumerate(zip(fields.line_items, line_classifications)):
        ocr_amount = ocr_item.amount or 0
        amount_extracted = ocr_item.amount is not None
        item_rate = _tax_rate_for(lc.category, session)
        item = TransactionItem(
            transaction_id=tx_id,
            name=ocr_item.name,
            amount=ocr_amount,
            tax_amount=calc_tax_amount(ocr_amount, item_rate),
            category=lc.category,
            sort_order=sort_idx,
        )
        session.add(item)
        items_created += 1
        if amount_extracted:
            items_with_amount += 1
        response_line_items.append(LineItemClassificationOut(
            item=ocr_item.name,
            amount=ocr_amount,
            amount_extracted=amount_extracted,
            category=lc.category,
            reason=lc.reason,
        ))

    session.commit()
    session.refresh(tx)

    return ReceiptUploadResponse(
        transaction_id=tx_id,
        filename=safe_name,
        raw_text=raw_text,
        merchant_raw=fields.merchant_raw,
        items=fields.items,
        total_amount=fields.total_amount,
        tax_amount=tax_amt,
        classification=classification.model_dump(),
        line_items=response_line_items,
        items_created=items_created,
        items_with_amount=items_with_amount,
    )
EOF

# ===========================================================================
# 3. backend/tests/test_ocr_extract.py 追加 (明細抽出ロジックの単体テスト)
# ===========================================================================
echo "==> backend/tests/test_ocr_extract.py"
cat > backend/tests/test_ocr_extract.py <<'EOF'
"""OCR 明細抽出ロジックのテスト."""
from __future__ import annotations
from app.ocr.extract import extract_receipt_fields


def test_extract_line_items_with_amounts():
    raw = """セブンイレブン渋谷店
2026/05/15
おにぎり        130
パン            150
牛乳            180
ティッシュ      250
小計           710
税             56
合計           766
"""
    fields = extract_receipt_fields(raw)
    assert fields.total_amount == 766
    # 明細4件、すべて金額付き
    amounts = {it.name.split()[0] if it.name else "": it.amount for it in fields.line_items}
    # 一部だけ確認 (正規化やスペースは曖昧)
    line_amounts = [it.amount for it in fields.line_items if it.amount is not None]
    assert 130 in line_amounts
    assert 180 in line_amounts


def test_excludes_total_and_tax_lines():
    raw = """店名
おにぎり 100
小計 100
税 8
合計 108
"""
    fields = extract_receipt_fields(raw)
    # 小計/税/合計は明細から除外される
    names = [it.name for it in fields.line_items]
    assert not any("合計" in n for n in names)
    assert not any("小計" in n for n in names)
    assert not any(n == "税" for n in names)
    # おにぎり 100 は残る
    found = any("おにぎり" in it.name and it.amount == 100 for it in fields.line_items)
    assert found, f"おにぎり 100 が見つからない: {[(it.name, it.amount) for it in fields.line_items]}"


def test_line_without_amount_kept_as_name_only():
    raw = """店名
おにぎり
パン 150
"""
    fields = extract_receipt_fields(raw)
    # 「おにぎり」は金額なし、None で残る
    no_amount = [it for it in fields.line_items if it.amount is None]
    assert any("おにぎり" in it.name for it in no_amount)
    # 「パン 150」は金額あり
    with_amount = [it for it in fields.line_items if it.amount == 150]
    assert any("パン" in it.name for it in with_amount)


def test_amount_with_yen_symbol():
    raw = """店名
ビール ¥350
ワイン ¥1,200
"""
    fields = extract_receipt_fields(raw)
    amounts = [it.amount for it in fields.line_items if it.amount is not None]
    assert 350 in amounts
    assert 1200 in amounts


def test_compat_items_list_returns_names():
    raw = """店名
おにぎり 130
牛乳 180
"""
    fields = extract_receipt_fields(raw)
    # items (互換) は品目名のみ
    assert "おにぎり" in " ".join(fields.items)
    assert "牛乳" in " ".join(fields.items)
EOF

# ===========================================================================
# 4. backend pytest
# ===========================================================================
echo ""
echo "==> pytest"
cd backend && uv run pytest tests/test_ocr_extract.py tests/test_classify_line_items.py -v 2>&1 | tail -25
cd "$REPO"

# ===========================================================================
# 5. uvicorn 再起動 + 既存画像で動作確認
# ===========================================================================
echo ""
echo "==> uvicorn 再起動"
pkill -9 -f uvicorn 2>/dev/null; sleep 2
(cd /workspaces/kakeibo/backend && nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 5

echo ""
echo "==> health"
curl -s http://localhost:8000/api/health; echo

echo ""
echo "==> 既存画像で動作確認"
DUMMY=$(find backend/uploads -name "*.jpg" -o -name "*.png" 2>/dev/null | head -1)
if [ -n "$DUMMY" ]; then
  echo "  $DUMMY をアップロード"
  curl -s -X POST -F "file=@$DUMMY" http://localhost:8000/api/receipts/upload | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  transaction_id={d[\"transaction_id\"]}')
print(f'  merchant_raw={d[\"merchant_raw\"]}')
print(f'  total_amount={d[\"total_amount\"]}')
print(f'  items_created={d[\"items_created\"]}件')
print(f'  items_with_amount={d[\"items_with_amount\"]}件 (OCR金額抽出成功)')
print(f'  line_items:')
for li in d['line_items']:
    mark = '✓' if li['amount_extracted'] else '×'
    print(f'    {mark} {li[\"item\"]} = {li[\"amount\"]}円 [{li[\"category\"]}]')
"
fi

cat <<EOM

============================================================
OCR → 明細別金額自動抽出 完了.

動作:
  - 「品目名 + 末尾金額」パターンの行を検出 (例: "おにぎり 130")
  - 抽出できた明細: amount + tax_amount + category 自動セット
  - 抽出失敗の明細: amount=0 で作成 (ユーザー補完)
  - レスポンスに items_with_amount = OCR成功数

確認: ブラウザで Ctrl+Shift+R → 画像アップロード → 一覧 → 編集 → 明細セクション
============================================================
EOM
