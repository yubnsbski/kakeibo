#!/usr/bin/env bash
# kakeibo full setup: 全機能を一括配置.
#
# 含まれる機能:
#   - 分類エンジン (9カテゴリ, taxRate)
#   - OCR (Tesseract + OpenCV)
#   - 画像アップロード + 自動DB保存
#   - 取引CRUD API
#   - userCategoryOverrides CRUD
#   - フロントエンド (React + Vite, タブUI, 編集モーダル, 税率表示)
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_full.sh
#
# 冪等性: 既存ファイルがあっても上書きで配置.

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "kakeibo Full Setup (Phase A + C1+C2)"
echo "============================================================"

# ===========================================================================
# 0. ディレクトリ作成
# ===========================================================================
echo "==> mkdir -p"
mkdir -p backend/app/classifier backend/app/ocr backend/app/routers backend/app/static
mkdir -p backend/tests
mkdir -p frontend/src/components
touch backend/app/__init__.py backend/tests/__init__.py

# ===========================================================================
# 1. backend/app/classifier/types.py
# ===========================================================================
echo "==> backend/app/classifier/types.py"
cat > backend/app/classifier/types.py <<'EOF'
"""Classifier types — 9-category system with tax rate."""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict

Category = Literal[
    "食費", "酒類", "外食", "日用品",
    "交通費", "医療費", "娯楽費", "衣料費", "その他",
]
ScreeningLabel = Literal["recordable", "needs_review"]

CATEGORY_TAX_RATE: dict[Category, int] = {
    "食費": 8, "酒類": 10, "外食": 10, "日用品": 10,
    "交通費": 10, "医療費": 10, "娯楽費": 10, "衣料費": 10, "その他": 10,
}


class ReceiptInput(BaseModel):
    model_config = ConfigDict(populate_by_name=True, extra="ignore")
    merchantRaw: str
    items: list[str] | None = None
    totalAmount: int | None = None
    purchasedAt: str | None = None
    userCategoryOverrides: dict[str, Category] | None = None


class ClassificationResult(BaseModel):
    merchantNormalized: str
    category: Category | None
    confidence: float
    needsReview: bool
    reason: str
    reasons: list[str]
    screeningLabel: ScreeningLabel
EOF

# ===========================================================================
# 2. backend/app/classifier/normalize.py
# ===========================================================================
echo "==> backend/app/classifier/normalize.py"
cat > backend/app/classifier/normalize.py <<'EOF'
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
EOF

# ===========================================================================
# 3. backend/app/classifier/rules.py
# ===========================================================================
echo "==> backend/app/classifier/rules.py"
cat > backend/app/classifier/rules.py <<'EOF'
"""Classification rule tables — 9-category system."""
from __future__ import annotations
from .types import Category

merchant_rules: dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通費",
    "JR東日本": "交通費",
}

ambiguous_merchants: list[str] = [
    "Amazon", "楽天", "イオン", "ドンキホーテ", "メルカリ",
]

item_keyword_rules: dict[str, Category] = {
    "おにぎり": "食費",
    "弁当": "食費",
    "牛乳": "食費",
    "パン": "食費",
    "ビール": "酒類",
    "ワイン": "酒類",
    "日本酒": "酒類",
    "チューハイ": "酒類",
    "洗剤": "日用品",
    "シャンプー": "日用品",
    "歯ブラシ": "日用品",
    "薬": "医療費",
    "ガソリン": "交通費",
    "本": "娯楽費",
    "映画": "娯楽費",
    "シャツ": "衣料費",
    "靴": "衣料費",
}
EOF

# ===========================================================================
# 4. backend/app/classifier/classify.py
# ===========================================================================
echo "==> backend/app/classifier/classify.py"
cat > backend/app/classifier/classify.py <<'EOF'
"""Receipt classifier."""
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
EOF

# ===========================================================================
# 5. backend/app/classifier/__init__.py
# ===========================================================================
echo "==> backend/app/classifier/__init__.py"
cat > backend/app/classifier/__init__.py <<'EOF'
"""Classifier package."""
from __future__ import annotations
from .classify import (
    AUTO_CONFIDENCE, MANUAL_REVIEW_CONFIDENCE, REVIEW_CONFIDENCE, classify_receipt,
)
from .normalize import normalize_merchant
from .rules import ambiguous_merchants, item_keyword_rules, merchant_rules
from .types import (
    CATEGORY_TAX_RATE, Category, ClassificationResult, ReceiptInput, ScreeningLabel,
)

__all__ = [
    "AUTO_CONFIDENCE", "MANUAL_REVIEW_CONFIDENCE", "REVIEW_CONFIDENCE",
    "CATEGORY_TAX_RATE", "Category", "ClassificationResult", "ReceiptInput",
    "ScreeningLabel", "ambiguous_merchants", "classify_receipt",
    "item_keyword_rules", "merchant_rules", "normalize_merchant",
]
EOF

# ===========================================================================
# 6. backend/app/models.py
# ===========================================================================
echo "==> backend/app/models.py"
cat > backend/app/models.py <<'EOF'
"""SQLModel models — 9-category system with tax_amount."""
from __future__ import annotations
from datetime import date, datetime
from typing import Literal
from sqlmodel import Field, SQLModel

TxStatus = Literal["auto_saved", "user_confirmed", "manually_added"]


class TransactionBase(SQLModel):
    receipt_id: str | None = None
    merchant_raw: str
    merchant_normalized: str
    items_text: str = ""
    screening_category: str | None = None
    needs_review: bool = False
    reason: str = ""
    confidence: float = 0.0
    amount: int
    tax_amount: int = 0
    purchased_at: date
    memo: str | None = None
    receipt_image_id: int | None = Field(default=None, foreign_key="receipts.id")
    status: str = Field(default="manually_added")
    ocr_raw_text: str | None = None


class Transaction(TransactionBase, table=True):
    __tablename__ = "transactions"
    id: int | None = Field(default=None, primary_key=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class TransactionCreate(TransactionBase):
    pass


class TransactionRead(TransactionBase):
    id: int
    created_at: datetime
    updated_at: datetime


class TransactionUpdate(SQLModel):
    merchant_raw: str | None = None
    merchant_normalized: str | None = None
    items_text: str | None = None
    screening_category: str | None = None
    needs_review: bool | None = None
    reason: str | None = None
    confidence: float | None = None
    amount: int | None = None
    tax_amount: int | None = None
    purchased_at: date | None = None
    memo: str | None = None
    status: str | None = None


class Receipt(SQLModel, table=True):
    __tablename__ = "receipts"
    id: int | None = Field(default=None, primary_key=True)
    filename: str
    ocr_text: str | None = None
    status: str = "pending"
    created_at: datetime = Field(default_factory=datetime.utcnow)


class UserCategoryOverride(SQLModel, table=True):
    __tablename__ = "user_category_overrides"
    id: int | None = Field(default=None, primary_key=True)
    merchant_pattern: str = Field(unique=True)
    category: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class UserCategoryOverrideCreate(SQLModel):
    merchant_pattern: str
    category: str


class UserCategoryOverrideRead(SQLModel):
    id: int
    merchant_pattern: str
    category: str
    created_at: datetime


class CategoryMaster(SQLModel, table=True):
    __tablename__ = "category_master"
    name: str = Field(primary_key=True)
    description: str = ""
    tax_rate: int = 10
    sort_order: int = 0


class CategoryMasterRead(SQLModel):
    name: str
    description: str
    tax_rate: int
    sort_order: int


def calc_tax_amount(amount_incl_tax: int, tax_rate: int) -> int:
    if amount_incl_tax <= 0 or tax_rate <= 0:
        return 0
    return round(amount_incl_tax * tax_rate / (100 + tax_rate))
EOF

# ===========================================================================
# 7. backend/app/database.py
# ===========================================================================
echo "==> backend/app/database.py"
cat > backend/app/database.py <<'EOF'
"""SQLite + SQLModel database wiring with seeding."""
from __future__ import annotations
import os
from collections.abc import Generator
from pathlib import Path
from sqlmodel import Session, SQLModel, create_engine, select

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_DB_PATH = _BACKEND_ROOT / "data.db"
DB_PATH = os.getenv("KAKEIBO_DB_PATH", str(_DEFAULT_DB_PATH))
DB_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(DB_URL, echo=False, connect_args={"check_same_thread": False})

_INITIAL_CATEGORIES = [
    ("食費", "スーパー, コンビニ, 弁当, 食品", 8, 1),
    ("酒類", "ビール, ワイン, 日本酒, チューハイ", 10, 2),
    ("外食", "レストラン, カフェ, 居酒屋", 10, 3),
    ("日用品", "ドラッグストア, 洗剤, トイレ, キッチン", 10, 4),
    ("交通費", "電車, バス, タクシー, ガソリン, 駐車場", 10, 5),
    ("医療費", "病院, 薬局, 医薬品, 診察", 10, 6),
    ("娯楽費", "書店, 映画, ゲーム, 趣味, レジャー", 10, 7),
    ("衣料費", "アパレル, 靴, ファッション, クリーニング", 10, 8),
    ("その他", "判断できないもの", 10, 99),
]


def create_db_and_tables() -> None:
    from . import models  # noqa: F401
    SQLModel.metadata.create_all(engine)
    _seed_categories()


def _seed_categories() -> None:
    from .models import CategoryMaster
    with Session(engine) as session:
        existing = session.exec(select(CategoryMaster)).first()
        if existing is not None:
            return
        for name, desc, rate, order in _INITIAL_CATEGORIES:
            session.add(CategoryMaster(name=name, description=desc, tax_rate=rate, sort_order=order))
        session.commit()


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
EOF

# ===========================================================================
# 8. backend/app/ocr/__init__.py
# ===========================================================================
echo "==> backend/app/ocr/__init__.py"
cat > backend/app/ocr/__init__.py <<'EOF'
"""OCR package."""
from .extract import extract_receipt_fields, run_ocr
from .preprocess import load_image, preprocess_for_ocr

__all__ = ["extract_receipt_fields", "load_image", "preprocess_for_ocr", "run_ocr"]
EOF

# ===========================================================================
# 9. backend/app/ocr/preprocess.py
# ===========================================================================
echo "==> backend/app/ocr/preprocess.py"
cat > backend/app/ocr/preprocess.py <<'EOF'
"""Image loading + preprocessing."""
from __future__ import annotations
import io
import cv2
import numpy as np
import pillow_heif
from PIL import Image

pillow_heif.register_heif_opener()


def load_image(data: bytes) -> np.ndarray:
    pil = Image.open(io.BytesIO(data))
    if pil.mode != "RGB":
        pil = pil.convert("RGB")
    rgb = np.array(pil)
    bgr = cv2.cvtColor(rgb, cv2.COLOR_RGB2BGR)
    return bgr


def preprocess_for_ocr(bgr: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(bgr, cv2.COLOR_BGR2GRAY)
    gray = cv2.fastNlMeansDenoising(gray, h=10)
    binarized = cv2.adaptiveThreshold(
        gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY,
        blockSize=31, C=10,
    )
    return binarized
EOF

# ===========================================================================
# 10. backend/app/ocr/extract.py
# ===========================================================================
echo "==> backend/app/ocr/extract.py"
cat > backend/app/ocr/extract.py <<'EOF'
"""Tesseract OCR + field extraction."""
from __future__ import annotations
import re
from dataclasses import dataclass
import numpy as np
import pytesseract

_TESSERACT_CONFIG = r"-l jpn+eng --psm 6"

_AMOUNT_PATTERNS = [
    re.compile(r"(?:合計|計|お会計|総額|TOTAL)[^\d]{0,5}(\d{1,3}(?:,\d{3})*|\d+)\s*円?"),
    re.compile(r"¥\s*(\d{1,3}(?:,\d{3})*|\d+)"),
    re.compile(r"(\d{1,3}(?:,\d{3})*|\d+)\s*円"),
]


@dataclass
class OcrFields:
    raw_text: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None


def run_ocr(image: np.ndarray) -> str:
    return pytesseract.image_to_string(image, config=_TESSERACT_CONFIG)


def _extract_amount(text: str) -> int | None:
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


def _extract_items(lines: list[str]) -> list[str]:
    items: list[str] = []
    cjk = re.compile(r"[\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]")
    for line in lines:
        stripped = line.strip()
        if not stripped or len(stripped) < 2:
            continue
        if not cjk.search(stripped):
            continue
        if re.fullmatch(r"[\d,円¥\s]+", stripped):
            continue
        if re.search(r"合計|小計|計|お会計|総額|税|釣り|お預り", stripped):
            continue
        items.append(stripped)
    return items[:10]


def extract_receipt_fields(raw_text: str) -> OcrFields:
    lines = [line for line in raw_text.splitlines() if line.strip()]
    return OcrFields(
        raw_text=raw_text,
        merchant_raw=_extract_merchant(lines),
        items=_extract_items(lines[1:]),
        total_amount=_extract_amount(raw_text),
    )
EOF

# ===========================================================================
# 11. backend/app/routers/__init__.py
# ===========================================================================
echo "==> backend/app/routers/__init__.py"
cat > backend/app/routers/__init__.py <<'EOF'
"""FastAPI routers package."""
EOF

# ===========================================================================
# 12. backend/app/routers/categories.py
# ===========================================================================
echo "==> backend/app/routers/categories.py"
cat > backend/app/routers/categories.py <<'EOF'
"""カテゴリマスタAPI."""
from __future__ import annotations
from fastapi import APIRouter, Depends
from sqlmodel import Session, select
from app.database import get_session
from app.models import CategoryMaster, CategoryMasterRead

router = APIRouter(prefix="/api/categories", tags=["categories"])


@router.get("", response_model=list[CategoryMasterRead])
def list_categories(session: Session = Depends(get_session)):
    stmt = select(CategoryMaster).order_by(CategoryMaster.sort_order)  # type: ignore
    return list(session.exec(stmt).all())
EOF

# ===========================================================================
# 13. backend/app/routers/transactions.py
# ===========================================================================
echo "==> backend/app/routers/transactions.py"
cat > backend/app/routers/transactions.py <<'EOF'
"""Transactions CRUD."""
from __future__ import annotations
from datetime import date, datetime
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, select
from app.database import get_session
from app.models import (
    CategoryMaster, Transaction, TransactionCreate, TransactionRead,
    TransactionUpdate, calc_tax_amount,
)

router = APIRouter(prefix="/api/transactions", tags=["transactions"])


def _tax_rate_for(category: str | None, session: Session) -> int:
    if category is None:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


@router.get("", response_model=list[TransactionRead])
def list_transactions(
    status: str | None = Query(None),
    needs_review: bool | None = None,
    merchant: str | None = None,
    start_date: date | None = None,
    end_date: date | None = None,
    limit: int = Query(100, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    session: Session = Depends(get_session),
) -> list[Transaction]:
    stmt = select(Transaction)
    if status:
        statuses = [s.strip() for s in status.split(",") if s.strip()]
        stmt = stmt.where(Transaction.status.in_(statuses))  # type: ignore
    if needs_review is not None:
        stmt = stmt.where(Transaction.needs_review == needs_review)
    if merchant:
        stmt = stmt.where(Transaction.merchant_normalized.contains(merchant))  # type: ignore
    if start_date:
        stmt = stmt.where(Transaction.purchased_at >= start_date)
    if end_date:
        stmt = stmt.where(Transaction.purchased_at <= end_date)
    stmt = stmt.order_by(Transaction.purchased_at.desc(), Transaction.id.desc())  # type: ignore
    stmt = stmt.offset(offset).limit(limit)
    return list(session.exec(stmt).all())


@router.get("/{tx_id}", response_model=TransactionRead)
def get_transaction(tx_id: int, session: Session = Depends(get_session)) -> Transaction:
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    return tx


@router.post("", response_model=TransactionRead, status_code=201)
def create_transaction(payload: TransactionCreate, session: Session = Depends(get_session)) -> Transaction:
    data = payload.model_dump()
    if data.get("tax_amount", 0) == 0 and data.get("amount", 0) > 0:
        rate = _tax_rate_for(data.get("screening_category"), session)
        data["tax_amount"] = calc_tax_amount(data["amount"], rate)
    tx = Transaction(**data)
    session.add(tx)
    session.commit()
    session.refresh(tx)
    return tx


@router.patch("/{tx_id}", response_model=TransactionRead)
def update_transaction(tx_id: int, payload: TransactionUpdate, session: Session = Depends(get_session)) -> Transaction:
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    data = payload.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(tx, k, v)
    if ("screening_category" in data or "amount" in data) and "tax_amount" not in data:
        rate = _tax_rate_for(tx.screening_category, session)
        tx.tax_amount = calc_tax_amount(tx.amount, rate)
    tx.updated_at = datetime.utcnow()
    session.add(tx)
    session.commit()
    session.refresh(tx)
    return tx


@router.delete("/{tx_id}", status_code=204)
def delete_transaction(tx_id: int, session: Session = Depends(get_session)) -> None:
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    session.delete(tx)
    session.commit()
EOF

# ===========================================================================
# 14. backend/app/routers/overrides.py
# ===========================================================================
echo "==> backend/app/routers/overrides.py"
cat > backend/app/routers/overrides.py <<'EOF'
"""User category overrides CRUD."""
from __future__ import annotations
from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import Session, select
from app.database import get_session
from app.models import (
    UserCategoryOverride, UserCategoryOverrideCreate, UserCategoryOverrideRead,
)

router = APIRouter(prefix="/api/overrides", tags=["overrides"])


@router.get("", response_model=list[UserCategoryOverrideRead])
def list_overrides(session: Session = Depends(get_session)):
    return list(session.exec(select(UserCategoryOverride)).all())


@router.post("", response_model=UserCategoryOverrideRead, status_code=201)
def create_override(payload: UserCategoryOverrideCreate, session: Session = Depends(get_session)):
    existing = session.exec(
        select(UserCategoryOverride).where(
            UserCategoryOverride.merchant_pattern == payload.merchant_pattern
        )
    ).first()
    if existing:
        existing.category = payload.category
        session.add(existing)
        session.commit()
        session.refresh(existing)
        return existing
    row = UserCategoryOverride(**payload.model_dump())
    session.add(row)
    session.commit()
    session.refresh(row)
    return row


@router.delete("/{override_id}", status_code=204)
def delete_override(override_id: int, session: Session = Depends(get_session)):
    row = session.get(UserCategoryOverride, override_id)
    if row is None:
        raise HTTPException(status_code=404, detail="not found")
    session.delete(row)
    session.commit()
EOF

# ===========================================================================
# 15. backend/app/routers/receipts.py
# ===========================================================================
echo "==> backend/app/routers/receipts.py"
cat > backend/app/routers/receipts.py <<'EOF'
"""Receipt upload: image → OCR → classify → auto-save."""
from __future__ import annotations
from datetime import date, datetime
from pathlib import Path
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from app.classifier import ReceiptInput, classify_receipt
from app.database import get_session
from app.models import (
    CategoryMaster, Receipt, Transaction, UserCategoryOverride, calc_tax_amount,
)
from app.ocr import extract_receipt_fields, load_image, preprocess_for_ocr, run_ocr

router = APIRouter(prefix="/api/receipts", tags=["receipts"])

_BACKEND_ROOT = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = _BACKEND_ROOT / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

_ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}
_MAX_BYTES = 15 * 1024 * 1024


class ReceiptUploadResponse(BaseModel):
    transaction_id: int
    filename: str
    raw_text: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None
    tax_amount: int
    classification: dict


def _load_overrides(session: Session) -> dict:
    rows = session.exec(select(UserCategoryOverride)).all()
    return {row.merchant_pattern: row.category for row in rows}  # type: ignore


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
    session.commit()
    session.refresh(tx)

    return ReceiptUploadResponse(
        transaction_id=tx.id,  # type: ignore
        filename=safe_name,
        raw_text=raw_text,
        merchant_raw=fields.merchant_raw,
        items=fields.items,
        total_amount=fields.total_amount,
        tax_amount=tax_amt,
        classification=classification.model_dump(),
    )
EOF

# ===========================================================================
# 16. backend/app/main.py
# ===========================================================================
echo "==> backend/app/main.py"
cat > backend/app/main.py <<'EOF'
"""FastAPI entry point."""
from __future__ import annotations
from contextlib import asynccontextmanager
from pathlib import Path
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from .database import create_db_and_tables
from .routers import categories, overrides, receipts, transactions


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(title="kakeibo API", version="0.3.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:5173", "http://127.0.0.1:5173"],
    allow_credentials=False,
    allow_methods=["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["*"],
)


@app.get("/api/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(receipts.router)
app.include_router(transactions.router)
app.include_router(overrides.router)
app.include_router(categories.router)

_STATIC_DIR = Path(__file__).resolve().parent / "static"
if _STATIC_DIR.exists():
    app.mount("/", StaticFiles(directory=str(_STATIC_DIR), html=True), name="static")
EOF

# ===========================================================================
# 17. backend/tests/conftest.py + test_classify.py + test_tax.py
# ===========================================================================
echo "==> backend/tests/conftest.py"
cat > backend/tests/conftest.py <<'EOF'
"""Shared pytest fixtures."""
from __future__ import annotations
import json
from pathlib import Path
import pytest

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_REPO_ROOT = _BACKEND_ROOT.parent
FIXTURES_DIR = _REPO_ROOT / "fixtures" / "receipts"


def load_fixture_cases(filename: str) -> list[dict]:
    path = FIXTURES_DIR / filename
    return json.loads(path.read_text(encoding="utf-8"))
EOF

echo "==> backend/tests/test_classify.py"
cat > backend/tests/test_classify.py <<'EOF'
"""Tests for classify_receipt."""
from __future__ import annotations
from app.classifier import ReceiptInput, classify_receipt


def test_seven_eleven_classified_as_food():
    r = classify_receipt(ReceiptInput(merchantRaw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
                                        items=["おにぎり", "牛乳"], totalAmount=620))
    assert r.category == "食費"
    assert r.needsReview is False


def test_amazon_without_items_needs_review():
    r = classify_receipt(ReceiptInput(merchantRaw="Amazon.co.jp", items=[], totalAmount=3000))
    assert r.category is None
    assert r.needsReview is True


def test_beer_classified_as_liquor():
    r = classify_receipt(ReceiptInput(merchantRaw="酒屋", items=["ビール"], totalAmount=500))
    assert r.category == "酒類"


def test_shirt_classified_as_clothing():
    r = classify_receipt(ReceiptInput(merchantRaw="アパレル店", items=["シャツ"], totalAmount=3000))
    assert r.category == "衣料費"


def test_no_rule_match_needs_review():
    r = classify_receipt(ReceiptInput(merchantRaw="未知の店舗", items=["未知"], totalAmount=1000))
    assert r.category is None
    assert r.needsReview is True
EOF

echo "==> backend/tests/test_tax.py"
cat > backend/tests/test_tax.py <<'EOF'
"""Tax calculation tests."""
import pytest
from app.models import calc_tax_amount


@pytest.mark.parametrize("amount, rate, expected", [
    (620, 8, 46), (1080, 8, 80), (1100, 10, 100), (550, 10, 50),
    (0, 10, 0), (-100, 10, 0), (1000, 0, 0), (1000, -5, 0),
])
def test_calc_tax_amount(amount, rate, expected):
    assert calc_tax_amount(amount, rate) == expected
EOF

# ===========================================================================
# 18. fixtures (9-category 期待値)
# ===========================================================================
echo "==> fixtures/receipts/basic.json"
mkdir -p fixtures/receipts
cat > fixtures/receipts/basic.json <<'EOF'
[
  {
    "name": "convenience_food",
    "input": {"merchantRaw": "ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店", "items": ["おにぎり", "牛乳"], "totalAmount": 620},
    "expected": {"category": "食費", "needsReview": false}
  },
  {
    "name": "ambiguous_amazon_no_items",
    "input": {"merchantRaw": "Amazon.co.jp", "items": [], "totalAmount": 3000},
    "expected": {"category": null, "needsReview": true}
  },
  {
    "name": "drugstore_daily_goods",
    "input": {"merchantRaw": "マツモトキヨシ 新宿店", "items": ["洗剤"], "totalAmount": 480},
    "expected": {"category": "日用品", "needsReview": false}
  }
]
EOF

cat > fixtures/receipts/evaluation.json <<'EOF'
[
  {
    "name": "seven_food",
    "input": {"merchantRaw": "ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店", "items": ["おにぎり", "牛乳"], "totalAmount": 620},
    "expected": {"category": "食費", "needsReview": false}
  },
  {
    "name": "liquor_beer",
    "input": {"merchantRaw": "酒屋A", "items": ["ビール"], "totalAmount": 850},
    "expected": {"category": "酒類", "needsReview": false}
  },
  {
    "name": "gas_station",
    "input": {"merchantRaw": "ENEOS 渋谷", "items": ["ガソリン"], "totalAmount": 5000},
    "expected": {"category": "交通費", "needsReview": false}
  }
]
EOF

# ===========================================================================
# 19. frontend/vite.config.ts
# ===========================================================================
echo "==> frontend/vite.config.ts"
cat > frontend/vite.config.ts <<'EOF'
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  server: {
    host: "0.0.0.0",
    port: 5173,
    proxy: {
      "/api": { target: "http://localhost:8000", changeOrigin: true },
    },
  },
});
EOF

# ===========================================================================
# 20. frontend/src/types.ts
# ===========================================================================
echo "==> frontend/src/types.ts"
cat > frontend/src/types.ts <<'EOF'
export type Category =
  | "食費" | "酒類" | "外食" | "日用品"
  | "交通費" | "医療費" | "娯楽費" | "衣料費" | "その他";

export const CATEGORIES: Category[] = [
  "食費", "酒類", "外食", "日用品",
  "交通費", "医療費", "娯楽費", "衣料費", "その他",
];

export const DEFAULT_TAX_RATE: Record<Category, number> = {
  "食費": 8, "酒類": 10, "外食": 10, "日用品": 10,
  "交通費": 10, "医療費": 10, "娯楽費": 10, "衣料費": 10, "その他": 10,
};

export interface CategoryMaster {
  name: Category;
  description: string;
  tax_rate: number;
  sort_order: number;
}

export type TxStatus = "auto_saved" | "user_confirmed" | "manually_added";

export interface Transaction {
  id: number;
  receipt_id: string | null;
  merchant_raw: string;
  merchant_normalized: string;
  items_text: string;
  screening_category: string | null;
  needs_review: boolean;
  reason: string;
  confidence: number;
  amount: number;
  tax_amount: number;
  purchased_at: string;
  memo: string | null;
  receipt_image_id: number | null;
  status: TxStatus;
  ocr_raw_text: string | null;
  created_at: string;
  updated_at: string;
}

export interface ReceiptUploadResponse {
  transaction_id: number;
  filename: string;
  raw_text: string;
  merchant_raw: string;
  items: string[];
  total_amount: number | null;
  tax_amount: number;
  classification: {
    merchantNormalized: string;
    category: Category | null;
    confidence: number;
    needsReview: boolean;
    reason: string;
    reasons: string[];
    screeningLabel: "recordable" | "needs_review";
  };
}

export interface UserCategoryOverride {
  id: number;
  merchant_pattern: string;
  category: string;
  created_at: string;
}
EOF

# ===========================================================================
# 21. frontend/src/api.ts
# ===========================================================================
echo "==> frontend/src/api.ts"
cat > frontend/src/api.ts <<'EOF'
import type {
  CategoryMaster, ReceiptUploadResponse, Transaction, UserCategoryOverride,
} from "./types";

const BASE = "/api";

async function handle<T>(r: Response): Promise<T> {
  if (!r.ok) { throw new Error(`${r.status}: ${await r.text()}`); }
  return r.json() as Promise<T>;
}

export async function uploadReceipt(file: File): Promise<ReceiptUploadResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/receipts/upload`, { method: "POST", body: fd });
  return handle<ReceiptUploadResponse>(r);
}

export interface ListParams {
  status?: string;
  needs_review?: boolean;
  merchant?: string;
  start_date?: string;
  end_date?: string;
  limit?: number;
  offset?: number;
}

export async function listTransactions(p: ListParams = {}): Promise<Transaction[]> {
  const sp = new URLSearchParams();
  Object.entries(p).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== "") sp.set(k, String(v));
  });
  const q = sp.toString() ? `?${sp.toString()}` : "";
  const r = await fetch(`${BASE}/transactions${q}`);
  return handle<Transaction[]>(r);
}

export async function updateTransaction(id: number, patch: Partial<Transaction>): Promise<Transaction> {
  const r = await fetch(`${BASE}/transactions/${id}`, {
    method: "PATCH", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  return handle<Transaction>(r);
}

export async function deleteTransaction(id: number): Promise<void> {
  const r = await fetch(`${BASE}/transactions/${id}`, { method: "DELETE" });
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
}

export async function listOverrides(): Promise<UserCategoryOverride[]> {
  const r = await fetch(`${BASE}/overrides`);
  return handle<UserCategoryOverride[]>(r);
}

export async function createOverride(merchant_pattern: string, category: string): Promise<UserCategoryOverride> {
  const r = await fetch(`${BASE}/overrides`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ merchant_pattern, category }),
  });
  return handle<UserCategoryOverride>(r);
}

export async function listCategories(): Promise<CategoryMaster[]> {
  const r = await fetch(`${BASE}/categories`);
  return handle<CategoryMaster[]>(r);
}
EOF

# ===========================================================================
# 22. frontend/src/App.tsx
# ===========================================================================
echo "==> frontend/src/App.tsx"
cat > frontend/src/App.tsx <<'EOF'
import { useState } from "react";
import "./App.css";
import { UploadView } from "./components/UploadView";
import { ListView } from "./components/ListView";

type Tab = "upload" | "list";

export default function App() {
  const [tab, setTab] = useState<Tab>("upload");
  const [refreshKey, setRefreshKey] = useState(0);

  return (
    <div className="app">
      <header className="app-header">
        <h1>家計簿</h1>
        <nav className="tabs">
          <button className={tab === "upload" ? "active" : ""}
                  onClick={() => setTab("upload")}>画像アップロード</button>
          <button className={tab === "list" ? "active" : ""}
                  onClick={() => setTab("list")}>一覧</button>
        </nav>
      </header>
      <main>
        {tab === "upload" && (
          <UploadView onUploaded={() => {
            setRefreshKey((k) => k + 1);
            setTab("list");
          }} />
        )}
        {tab === "list" && <ListView refreshKey={refreshKey} />}
      </main>
    </div>
  );
}
EOF

# ===========================================================================
# 23. frontend/src/components/UploadView.tsx
# ===========================================================================
echo "==> frontend/src/components/UploadView.tsx"
cat > frontend/src/components/UploadView.tsx <<'EOF'
import { useState } from "react";
import { uploadReceipt } from "../api";
import type { ReceiptUploadResponse } from "../types";

interface Props { onUploaded: () => void; }

export function UploadView({ onUploaded }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<ReceiptUploadResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    if (!file) { setError("ファイル未選択"); return; }
    setError(null); setBusy(true);
    try {
      const r = await uploadReceipt(file);
      setResult(r);
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>レシート画像アップロード</h2>
      <p className="hint">送信すると OCR・分類・DB保存まで自動です。確認は「一覧」タブから。</p>
      <input type="file" accept="image/*" onChange={(e) => {
        setFile(e.target.files?.[0] || null); setResult(null);
      }} />
      <button onClick={handleSubmit} disabled={busy || !file}>
        {busy ? "処理中..." : "送信"}
      </button>
      {error && <p className="err">{error}</p>}
      {result && (
        <div className="result">
          <h3>保存完了 (取引ID: {result.transaction_id})</h3>
          <table>
            <tbody>
              <tr><th>店舗名</th><td>{result.merchant_raw || "(空)"}</td></tr>
              <tr><th>明細</th><td>{result.items.join(" / ") || "(空)"}</td></tr>
              <tr><th>合計(税込)</th><td>{result.total_amount?.toLocaleString() || "(検出失敗)"}円</td></tr>
              <tr><th>税額</th><td>{result.tax_amount.toLocaleString()}円</td></tr>
              <tr><th>カテゴリ</th><td>{result.classification.category || "(未分類)"}</td></tr>
              <tr><th>needs_review</th><td>{String(result.classification.needsReview)}</td></tr>
              <tr><th>理由</th><td>{result.classification.reason}</td></tr>
            </tbody>
          </table>
          <details>
            <summary>OCR raw text</summary>
            <pre>{result.raw_text}</pre>
          </details>
          <button onClick={onUploaded}>一覧で確認・編集する</button>
        </div>
      )}
    </div>
  );
}
EOF

# ===========================================================================
# 24. frontend/src/components/ListView.tsx
# ===========================================================================
echo "==> frontend/src/components/ListView.tsx"
cat > frontend/src/components/ListView.tsx <<'EOF'
import { useEffect, useState, useCallback } from "react";
import { listTransactions, deleteTransaction } from "../api";
import type { Transaction } from "../types";
import { EditView } from "./EditView";

interface Props { refreshKey: number; }
type FilterMode = "unconfirmed" | "all";

export function ListView({ refreshKey }: Props) {
  const [items, setItems] = useState<Transaction[]>([]);
  const [mode, setMode] = useState<FilterMode>("unconfirmed");
  const [merchantQ, setMerchantQ] = useState("");
  const [editing, setEditing] = useState<Transaction | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const data = await listTransactions({
        status: mode === "unconfirmed" ? "auto_saved" : undefined,
        merchant: merchantQ || undefined,
        limit: 200,
      });
      setItems(data);
    } catch (e) { setError(String(e)); }
    finally { setLoading(false); }
  }, [mode, merchantQ]);

  useEffect(() => { load(); }, [load, refreshKey]);

  async function handleDelete(id: number) {
    if (!confirm(`取引ID ${id} を削除しますか?`)) return;
    try { await deleteTransaction(id); await load(); }
    catch (e) { setError(String(e)); }
  }

  return (
    <div className="card">
      <h2>取引一覧</h2>
      <div className="filters">
        <label><input type="radio" checked={mode === "unconfirmed"}
                       onChange={() => setMode("unconfirmed")} />未確認のみ</label>
        <label><input type="radio" checked={mode === "all"}
                       onChange={() => setMode("all")} />すべて</label>
        <input type="text" placeholder="店舗名で検索" value={merchantQ}
               onChange={(e) => setMerchantQ(e.target.value)} />
        <button onClick={load}>再読込</button>
      </div>
      {error && <p className="err">{error}</p>}
      {loading && <p>読込中...</p>}
      {!loading && items.length === 0 && <p>該当する取引なし</p>}
      {items.length > 0 && (
        <table className="tx-table">
          <thead>
            <tr>
              <th>日付</th><th>店舗</th><th>カテゴリ</th>
              <th style={{ textAlign: "right" }}>金額(税込)</th>
              <th style={{ textAlign: "right" }}>税額</th>
              <th>状態</th><th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((t) => (
              <tr key={t.id} className={t.needs_review ? "needs-review" : ""}>
                <td>{t.purchased_at}</td>
                <td>{t.merchant_normalized || t.merchant_raw}</td>
                <td>{t.screening_category || "(未分類)"}</td>
                <td style={{ textAlign: "right" }}>{t.amount.toLocaleString()}</td>
                <td style={{ textAlign: "right" }}>{t.tax_amount.toLocaleString()}</td>
                <td>
                  {t.status === "auto_saved" && <span className="badge auto">未確認</span>}
                  {t.status === "user_confirmed" && <span className="badge ok">確認済</span>}
                  {t.status === "manually_added" && <span className="badge ok">手動</span>}
                  {t.needs_review && <span className="badge review">要確認</span>}
                </td>
                <td>
                  <button onClick={() => setEditing(t)}>編集</button>
                  <button onClick={() => handleDelete(t.id)} className="danger">削除</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {editing && (
        <EditView tx={editing} onClose={() => setEditing(null)}
                  onSaved={() => { setEditing(null); load(); }} />
      )}
    </div>
  );
}
EOF

# ===========================================================================
# 25. frontend/src/components/EditView.tsx
# ===========================================================================
echo "==> frontend/src/components/EditView.tsx"
cat > frontend/src/components/EditView.tsx <<'EOF'
import { useEffect, useState } from "react";
import { updateTransaction, createOverride, listCategories } from "../api";
import type { Transaction, CategoryMaster } from "../types";
import { CATEGORIES, DEFAULT_TAX_RATE } from "../types";

interface Props {
  tx: Transaction;
  onClose: () => void;
  onSaved: () => void;
}

export function EditView({ tx, onClose, onSaved }: Props) {
  const [merchantNormalized, setMerchantNormalized] = useState(tx.merchant_normalized);
  const [category, setCategory] = useState<string>(tx.screening_category || "");
  const [amount, setAmount] = useState(String(tx.amount));
  const [purchasedAt, setPurchasedAt] = useState(tx.purchased_at);
  const [itemsText, setItemsText] = useState(tx.items_text);
  const [memo, setMemo] = useState(tx.memo || "");
  const [needsReview, setNeedsReview] = useState(tx.needs_review);
  const [registerOverride, setRegisterOverride] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [catMaster, setCatMaster] = useState<CategoryMaster[]>([]);

  useEffect(() => {
    listCategories().then(setCatMaster).catch(() => {});
  }, []);

  const taxRate = (() => {
    const found = catMaster.find((c) => c.name === category);
    if (found) return found.tax_rate;
    return DEFAULT_TAX_RATE[category as keyof typeof DEFAULT_TAX_RATE] ?? 10;
  })();

  const amountNum = parseInt(amount, 10) || 0;
  const taxAmount = amountNum > 0 && taxRate > 0
    ? Math.round((amountNum * taxRate) / (100 + taxRate))
    : 0;
  const exTax = amountNum - taxAmount;

  async function handleSave() {
    setBusy(true); setError(null);
    try {
      await updateTransaction(tx.id, {
        merchant_normalized: merchantNormalized,
        screening_category: category || null,
        amount: amountNum,
        purchased_at: purchasedAt,
        items_text: itemsText,
        memo: memo || null,
        needs_review: needsReview,
        status: "user_confirmed",
      });
      if (registerOverride && category && merchantNormalized) {
        await createOverride(merchantNormalized, category);
      }
      onSaved();
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>取引編集 (ID: {tx.id})</h3>
        <div className="form-grid">
          <label>日付</label>
          <input type="date" value={purchasedAt}
                 onChange={(e) => setPurchasedAt(e.target.value)} />
          <label>店舗(正規化)</label>
          <input type="text" value={merchantNormalized}
                 onChange={(e) => setMerchantNormalized(e.target.value)} />
          <label>カテゴリ</label>
          <select value={category} onChange={(e) => setCategory(e.target.value)}>
            <option value="">(未分類)</option>
            {CATEGORIES.map((c) => (<option key={c} value={c}>{c}</option>))}
          </select>
          <label>税率</label>
          <div className="tax-info">{category ? `${taxRate}%` : "(カテゴリ未選択)"}</div>
          <label>金額 (税込)</label>
          <input type="number" value={amount}
                 onChange={(e) => setAmount(e.target.value)} />
          <label>税抜換算</label>
          <div className="tax-info">
            {amountNum > 0 ? `${exTax.toLocaleString()}円 (税額 ${taxAmount.toLocaleString()}円)` : "-"}
          </div>
          <label>明細 (| 区切り)</label>
          <input type="text" value={itemsText}
                 onChange={(e) => setItemsText(e.target.value)} />
          <label>メモ</label>
          <input type="text" value={memo}
                 onChange={(e) => setMemo(e.target.value)} />
          <label>要確認</label>
          <input type="checkbox" checked={needsReview}
                 onChange={(e) => setNeedsReview(e.target.checked)} />
          <label>この店舗→カテゴリを記憶</label>
          <input type="checkbox" checked={registerOverride}
                 onChange={(e) => setRegisterOverride(e.target.checked)}
                 disabled={!category || !merchantNormalized} />
        </div>
        {tx.ocr_raw_text && (
          <details>
            <summary>OCR raw text (参考)</summary>
            <pre>{tx.ocr_raw_text}</pre>
          </details>
        )}
        {error && <p className="err">{error}</p>}
        <div className="actions">
          <button onClick={handleSave} disabled={busy}>保存(確認済にする)</button>
          <button onClick={onClose}>キャンセル</button>
        </div>
      </div>
    </div>
  );
}
EOF

# ===========================================================================
# 26. frontend/src/App.css
# ===========================================================================
echo "==> frontend/src/App.css"
cat > frontend/src/App.css <<'EOF'
* { box-sizing: border-box; }
body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
       background: #f8f9fa; color: #1f2328; }
.app { max-width: 960px; margin: 0 auto; padding: 16px; }
.app-header { display: flex; align-items: center; justify-content: space-between; }
.app-header h1 { margin: 0; font-size: 1.4em; }
.tabs button { background: transparent; border: 1px solid #d0d7de; padding: 8px 16px;
              margin-left: 8px; border-radius: 6px; cursor: pointer; font-size: 0.95em; }
.tabs button.active { background: #1f6feb; color: #fff; border-color: #1f6feb; }
.card { background: #fff; border: 1px solid #d0d7de; border-radius: 8px;
        padding: 20px; margin: 16px 0; }
.card h2 { margin-top: 0; }
.hint { color: #57606a; font-size: 0.9em; }
button { background: #1f6feb; color: #fff; border: 0; padding: 8px 16px;
         border-radius: 6px; cursor: pointer; font-size: 0.95em; }
button:disabled { background: #888; cursor: not-allowed; }
button.danger { background: #cf222e; margin-left: 4px; }
.err { color: #cf222e; }
.result { margin-top: 16px; padding-top: 16px; border-top: 1px solid #eee; }
.result table { width: 100%; border-collapse: collapse; }
.result table th { text-align: left; padding: 4px 8px; color: #57606a; width: 140px; }
.result table td { padding: 4px 8px; }
pre { background: #f6f8fa; padding: 12px; border-radius: 6px; overflow-x: auto;
      font-size: 0.85em; white-space: pre-wrap; }
.filters { display: flex; gap: 12px; align-items: center; margin-bottom: 12px;
           flex-wrap: wrap; }
.filters input[type=text] { padding: 6px 10px; border: 1px solid #d0d7de; border-radius: 6px; }
.tx-table { width: 100%; border-collapse: collapse; font-size: 0.92em; }
.tx-table th, .tx-table td { padding: 6px 10px; border-bottom: 1px solid #eee; text-align: left; }
.tx-table tr.needs-review { background: #fff8e6; }
.badge { display: inline-block; padding: 2px 6px; border-radius: 4px;
         font-size: 0.78em; margin-right: 4px; }
.badge.auto { background: #ddf4ff; color: #0969da; }
.badge.ok { background: #dafbe1; color: #1a7f37; }
.badge.review { background: #fff1c2; color: #9a6700; }
.modal-backdrop { position: fixed; inset: 0; background: rgba(0,0,0,0.5);
                  display: flex; align-items: center; justify-content: center; z-index: 100; }
.modal { background: #fff; padding: 24px; border-radius: 8px;
         max-width: 560px; width: 95%; max-height: 90vh; overflow-y: auto; }
.form-grid { display: grid; grid-template-columns: 160px 1fr; gap: 8px 12px;
             margin: 16px 0; align-items: center; }
.form-grid input[type=text], .form-grid input[type=number], .form-grid input[type=date],
.form-grid select { padding: 6px 10px; border: 1px solid #d0d7de; border-radius: 6px; }
.actions { margin-top: 16px; display: flex; gap: 8px; justify-content: flex-end; }
.tax-info { padding: 6px 10px; color: #57606a; font-size: 0.9em; }
EOF

# ===========================================================================
# 27. frontend/src/main.tsx
# ===========================================================================
if [ ! -f frontend/src/main.tsx ]; then
  echo "==> frontend/src/main.tsx (create)"
  cat > frontend/src/main.tsx <<'EOF'
import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import "./index.css";
import App from "./App";

createRoot(document.getElementById("root")!).render(
  <StrictMode><App /></StrictMode>
);
EOF
fi

# ===========================================================================
# 28. data.db リセット
# ===========================================================================
echo ""
echo "==> reset data.db"
rm -f backend/data.db backend/data.db-journal backend/data.db-wal backend/data.db-shm

# ===========================================================================
# 29. backend pytest
# ===========================================================================
echo ""
echo "==> backend pytest"
cd backend && uv run pytest -v 2>&1 | tail -30 || echo "WARN: tests failed"
cd "$REPO"

# ===========================================================================
# 30. server restart
# ===========================================================================
echo ""
echo "==> restart servers"
pkill -f uvicorn 2>/dev/null || true
pkill -f vite 2>/dev/null || true
sleep 2

cd backend
nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &
sleep 4
cd "$REPO"

cd frontend
if [ ! -d node_modules ]; then
  npm install 2>&1 | tail -5
fi
nohup npm run dev > /tmp/vite.log 2>&1 &
sleep 5
cd "$REPO"

echo ""
echo "==> backend health"
curl -s http://localhost:8000/api/health && echo

echo ""
echo "==> categories API"
curl -s http://localhost:8000/api/categories | python3 -m json.tool 2>&1 | head -20

cat <<EOM

============================================================
Full Setup 完了.

サーバー状況:
  backend  : http://localhost:8000  (ログ: /tmp/uvicorn.log)
  frontend : http://localhost:5173  (ログ: /tmp/vite.log)

動作確認:
  VS Code PORTS タブで 5173 を開く
  → 「画像アップロード」タブで receipt_01_seven.jpg を送信
  → 「一覧」タブで「未確認」バッジ確認、編集モーダルで税率表示確認

停止:
  pkill -f uvicorn ; pkill -f vite
============================================================
EOM
