#!/usr/bin/env bash
# OCR → 明細自動振り分け 機能追加.
#
# 動作:
#   - OCR で抽出した items を classify_line_items で個別分類
#   - 各明細を transaction_items に自動INSERT (金額0、カテゴリ付与)
#   - ユーザーは編集モーダルで金額のみ補完
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_line_classify.sh

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "OCR → 明細自動振り分け"
echo "============================================================"

# ===========================================================================
# 1. backend/app/classifier/classify.py に classify_line_items 追加
# ===========================================================================
echo "==> backend/app/classifier/classify.py"
cat > backend/app/classifier/classify.py <<'EOF'
"""Receipt classifier + line-item classifier."""
from __future__ import annotations
from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import Category, ClassificationResult, ReceiptInput

AUTO_CONFIDENCE = 0.9
MANUAL_REVIEW_CONFIDENCE = 0.4
REVIEW_CONFIDENCE = 0.0


def _find_user_override(merchant_normalized: str, overrides: dict[str, Category] | None) -> Category | None:
    if not overrides:
        return None
    for merchant, category in overrides.items():
        normalized_key = normalize_merchant(merchant)
        if normalized_key and normalized_key in merchant_normalized:
            return category
    return None


def _match_merchant_rule(merchant_normalized: str) -> dict | None:
    for merchant, category in merchant_rules.items():
        if merchant in merchant_normalized:
            return {"category": category, "reason": f"merchant_rule: {merchant}"}
    return None


def _match_item_rule(items: list[str]) -> dict | None:
    for item in items:
        for keyword, category in item_keyword_rules.items():
            if keyword in item:
                return {"category": category, "reason": f"item_keyword: {keyword}"}
    return None


def classify_receipt(input_data: ReceiptInput) -> ClassificationResult:
    """ヘッダ単位の分類 (レシート全体に1カテゴリ)."""
    merchant_normalized = normalize_merchant(input_data.merchantRaw)
    items = input_data.items or []
    is_ambiguous = any(m in merchant_normalized for m in ambiguous_merchants)

    override = _find_user_override(merchant_normalized, input_data.userCategoryOverrides)
    if override is not None:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=override,
            confidence=1.0, needsReview=False,
            reason=f"user_override: {override}",
            reasons=["user_override"], screeningLabel="recordable",
        )

    if is_ambiguous and len(items) == 0:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=None,
            confidence=REVIEW_CONFIDENCE, needsReview=True,
            reason="ambiguous merchant without items",
            reasons=["ambiguous_merchant_no_items"], screeningLabel="needs_review",
        )

    merchant_match = _match_merchant_rule(merchant_normalized)
    item_match = None if merchant_match else _match_item_rule(items)
    match = merchant_match or item_match

    if match is None:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=None,
            confidence=REVIEW_CONFIDENCE, needsReview=True,
            reason="no rule matched", reasons=["no_rule"], screeningLabel="needs_review",
        )

    if is_ambiguous:
        return ClassificationResult(
            merchantNormalized=merchant_normalized, category=None,
            confidence=REVIEW_CONFIDENCE, needsReview=True,
            reason="ambiguous merchant requires manual category",
            reasons=["ambiguous_merchant_with_items"], screeningLabel="needs_review",
        )

    return ClassificationResult(
        merchantNormalized=merchant_normalized, category=match["category"],
        confidence=AUTO_CONFIDENCE, needsReview=False,
        reason=f"rule_match: {match['category']}",
        reasons=[match["reason"]], screeningLabel="recordable",
    )


# ===== 明細単位分類 (新規) =====

class LineItemClassification:
    """明細1行の分類結果."""
    def __init__(self, item: str, category: Category | None, reason: str):
        self.item = item
        self.category = category
        self.reason = reason

    def dict(self) -> dict:
        return {"item": self.item, "category": self.category, "reason": self.reason}


def _find_merchant_category(merchant_normalized: str) -> Category | None:
    """店舗ルール一致なら返す (理由不要)."""
    for merchant, category in merchant_rules.items():
        if merchant in merchant_normalized:
            return category
    return None


def _find_item_category(item: str) -> tuple[Category, str] | None:
    """品目キーワード一致なら (category, keyword) を返す."""
    for keyword, category in item_keyword_rules.items():
        if keyword in item:
            return (category, keyword)
    return None


def classify_line_items(
    items: list[str], merchant_raw: str,
    user_overrides: dict[str, Category] | None = None,
) -> list[LineItemClassification]:
    """各明細品目を分類.

    優先順位:
        1. ユーザー修正ルール (店舗名一致 → 全明細を override カテゴリ)
        2. アイテムキーワード一致 → そのカテゴリ
        3. 通常店舗 (非曖昧) なら 店舗カテゴリにフォールバック
        4. 曖昧店舗 or 未一致 → None (要確認)

    Returns: 各明細の分類結果リスト
    """
    merchant_normalized = normalize_merchant(merchant_raw)
    is_ambiguous = any(m in merchant_normalized for m in ambiguous_merchants)

    # ユーザー override 優先
    override = _find_user_override(merchant_normalized, user_overrides)

    merchant_category = None if is_ambiguous else _find_merchant_category(merchant_normalized)

    results: list[LineItemClassification] = []
    for item_text in items:
        item_text = item_text.strip()
        if not item_text:
            continue

        # 1. user_override 最優先 (店舗単位なので明細全部に適用)
        if override is not None:
            results.append(LineItemClassification(
                item=item_text, category=override,
                reason=f"user_override: {override}",
            ))
            continue

        # 2. アイテムキーワード判定
        item_match = _find_item_category(item_text)
        if item_match is not None:
            cat, keyword = item_match
            results.append(LineItemClassification(
                item=item_text, category=cat,
                reason=f"item_keyword: {keyword}",
            ))
            continue

        # 3. 通常店舗のフォールバック
        if merchant_category is not None:
            results.append(LineItemClassification(
                item=item_text, category=merchant_category,
                reason=f"merchant_fallback: {merchant_category}",
            ))
            continue

        # 4. 曖昧店舗 or 全く未一致 → None
        results.append(LineItemClassification(
            item=item_text, category=None,
            reason="no_match (要確認)",
        ))
    return results
EOF

# ===========================================================================
# 2. backend/app/classifier/__init__.py に classify_line_items を export
# ===========================================================================
echo "==> backend/app/classifier/__init__.py"
cat > backend/app/classifier/__init__.py <<'EOF'
"""Classifier package."""
from __future__ import annotations
from .classify import (
    AUTO_CONFIDENCE, MANUAL_REVIEW_CONFIDENCE, REVIEW_CONFIDENCE,
    LineItemClassification, classify_line_items, classify_receipt,
)
from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import (
    CATEGORY_TAX_RATE, Category, ClassificationResult, ReceiptInput, ScreeningLabel,
)

__all__ = [
    "AUTO_CONFIDENCE", "MANUAL_REVIEW_CONFIDENCE", "REVIEW_CONFIDENCE",
    "CATEGORY_TAX_RATE", "Category", "ClassificationResult",
    "LineItemClassification", "ReceiptInput", "ScreeningLabel",
    "ambiguous_merchants", "classify_line_items", "classify_receipt",
    "item_keyword_rules", "merchant_rules", "normalize_merchant",
]
EOF

# ===========================================================================
# 3. backend/app/routers/receipts.py 改修 (OCR後に明細自動INSERT)
# ===========================================================================
echo "==> backend/app/routers/receipts.py (明細自動INSERT)"
cat > backend/app/routers/receipts.py <<'EOF'
"""Receipt upload: image → OCR → classify → auto-save + auto-create items."""
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
    items_created: int  # transaction_items に追加した件数


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

    # 明細単位分類 + 自動 INSERT
    line_classifications = classify_line_items(
        items=fields.items,
        merchant_raw=fields.merchant_raw,
        user_overrides=overrides if overrides else None,
    )
    items_created = 0
    for sort_idx, lc in enumerate(line_classifications):
        # 明細を amount=0 で作成 (ユーザーが後で金額補完)
        item_rate = _tax_rate_for(lc.category, session)
        item = TransactionItem(
            transaction_id=tx_id,
            name=lc.item,
            amount=0,  # OCRでは個別金額抽出しない、ユーザー補完
            tax_amount=0,
            category=lc.category,
            sort_order=sort_idx,
        )
        session.add(item)
        items_created += 1

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
        line_items=[
            LineItemClassificationOut(
                item=lc.item, category=lc.category, reason=lc.reason,
            ) for lc in line_classifications
        ],
        items_created=items_created,
    )
EOF

# ===========================================================================
# 4. backend/tests/test_classify_line_items.py
# ===========================================================================
echo "==> backend/tests/test_classify_line_items.py"
cat > backend/tests/test_classify_line_items.py <<'EOF'
"""明細単位分類のテスト."""
from __future__ import annotations
from app.classifier import classify_line_items


def test_item_keyword_priority():
    """明細キーワード一致が最優先."""
    results = classify_line_items(
        items=["おにぎり", "ビール", "ティッシュ"],
        merchant_raw="不明店舗",
    )
    assert results[0].category == "食費"
    assert results[1].category == "酒類"
    assert results[2].category == "日用品"


def test_merchant_fallback_for_unmatched_items():
    """通常店舗の未一致明細は merchant カテゴリでフォールバック."""
    results = classify_line_items(
        items=["会計調整"],  # キーワード一致なし
        merchant_raw="セブンイレブン渋谷店",
    )
    assert results[0].category == "食費"
    assert "merchant_fallback" in results[0].reason


def test_ambiguous_merchant_no_fallback():
    """危険店舗の未一致明細は None."""
    results = classify_line_items(
        items=["会計調整"],
        merchant_raw="Amazon.co.jp",
    )
    assert results[0].category is None
    assert "no_match" in results[0].reason


def test_ambiguous_merchant_with_keyword_match():
    """危険店舗でも品目キーワード一致は分類成功."""
    results = classify_line_items(
        items=["シャツ"],
        merchant_raw="Amazon.co.jp",
    )
    assert results[0].category == "衣料費"


def test_user_override_applies_all_items():
    """ユーザー修正ルールは全明細に適用."""
    results = classify_line_items(
        items=["不明品目1", "不明品目2"],
        merchant_raw="Amazon.co.jp",
        user_overrides={"Amazon": "娯楽費"},
    )
    assert results[0].category == "娯楽費"
    assert results[1].category == "娯楽費"


def test_mixed_categories_in_one_receipt():
    """1レシート複数カテゴリの混在."""
    results = classify_line_items(
        items=["おにぎり", "ビール", "シャンプー", "シャツ"],
        merchant_raw="イオン",  # 危険店舗
    )
    assert results[0].category == "食費"
    assert results[1].category == "酒類"
    assert results[2].category == "日用品"
    assert results[3].category == "衣料費"


def test_empty_items():
    """明細空."""
    results = classify_line_items(items=[], merchant_raw="セブンイレブン")
    assert results == []


def test_blank_item_strings_skipped():
    """空文字明細はスキップ."""
    results = classify_line_items(
        items=["", "  ", "おにぎり"],
        merchant_raw="不明",
    )
    assert len(results) == 1
    assert results[0].item == "おにぎり"
EOF

# ===========================================================================
# 5. uvicorn 再起動 + テスト
# ===========================================================================
echo ""
echo "==> pytest"
cd backend && uv run pytest tests/test_classify_line_items.py -v 2>&1 | tail -20
cd "$REPO"

echo ""
echo "==> uvicorn 再起動"
pkill -9 -f uvicorn 2>/dev/null; sleep 2
(cd /workspaces/kakeibo/backend && nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 5

echo ""
echo "==> health"
curl -s http://localhost:8000/api/health; echo

echo ""
echo "==> 動作確認 (既存ダミー画像でテスト)"
DUMMY=$(find backend/uploads -name "*.jpg" -o -name "*.png" 2>/dev/null | head -1)
if [ -n "$DUMMY" ]; then
  echo "--- 既存画像 $DUMMY をアップロードして明細自動分類テスト ---"
  curl -s -X POST -F "file=@$DUMMY" http://localhost:8000/api/receipts/upload | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(f'  transaction_id={d[\"transaction_id\"]}')
print(f'  merchant_raw={d[\"merchant_raw\"]}')
print(f'  total_amount={d[\"total_amount\"]}')
print(f'  items_created={d[\"items_created\"]}件')
print(f'  line_items:')
for li in d['line_items']:
    print(f'    - {li[\"item\"]} → {li[\"category\"]} ({li[\"reason\"]})')
"
else
  echo "  uploads ディレクトリに画像なし、スキップ"
fi

cat <<EOM

============================================================
OCR → 明細自動振り分け 完了.

動作:
  - 画像アップロード時に OCR で抽出した品目を classify_line_items で個別分類
  - 各明細を amount=0 で transaction_items に自動INSERT
  - カテゴリは品目キーワード優先 → 店舗ルール → None (要確認)
  - 編集モーダルで明細セクションに自動分類済みカテゴリが表示
  - ユーザーは金額のみ補完すれば完了

確認:
  ブラウザで Ctrl+Shift+R → 「取込」タブ → 画像アップロード
  → 「一覧」タブで該当取引の「編集」→ 明細セクションに自動分類された明細表示
============================================================
EOM
