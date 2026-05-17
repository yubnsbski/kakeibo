#!/usr/bin/env bash
# kakeibo C1+C2: カテゴリ体系を 9 + taxRate へ更新.
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_c1_c2.sh
#
# 動作:
#   1. backend/app/classifier/{types,rules}.py 更新 (9カテゴリ)
#   2. backend/app/models.py に tax_amount + category_master 追加
#   3. backend/app/routers/categories.py 新規 (カテゴリ一覧API)
#   4. backend/app/main.py 更新 (初期データ投入)
#   5. backend/app/routers/receipts.py 更新 (tax_amount 自動計算)
#   6. fixtures/receipts/*.json 期待値更新
#   7. backend/tests/test_classify.py 更新
#   8. frontend/src/types.ts 更新 (CATEGORIES + taxRate)
#   9. frontend/src/components/EditView.tsx 更新 (taxRate表示)
#   10. docs/classification-policy.md 更新
#   11. AGENTS.md カテゴリ表更新
#   12. data.db 削除 + pytest + uvicorn 再起動

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "C1+C2 setup: 9 categories + taxRate"
echo "============================================================"

# ===========================================================================
# 1. backend/app/classifier/types.py
# ===========================================================================
echo "==> backend/app/classifier/types.py"
cat > backend/app/classifier/types.py <<'EOF'
"""Classifier types.

9-category system (C1) with tax rate attribute (C2).
Tax rate is *not* part of the classifier output; it lives in category_master
table and is joined at the persistence layer.
"""
from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict

Category = Literal[
    "食費",
    "酒類",
    "外食",
    "日用品",
    "交通費",
    "医療費",
    "娯楽費",
    "衣料費",
    "その他",
]

ScreeningLabel = Literal["recordable", "needs_review"]

# Tax rate map (single source of truth for the classifier package).
# DB側 category_master が運用上のマスタだが、テスト・初期データ用にここでも定義.
CATEGORY_TAX_RATE: dict[Category, int] = {
    "食費": 8,
    "酒類": 10,
    "外食": 10,
    "日用品": 10,
    "交通費": 10,
    "医療費": 10,
    "娯楽費": 10,
    "衣料費": 10,
    "その他": 10,
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
# 2. backend/app/classifier/rules.py
# ===========================================================================
echo "==> backend/app/classifier/rules.py"
cat > backend/app/classifier/rules.py <<'EOF'
"""Classification rule tables — updated for 9-category system."""
from __future__ import annotations

from .types import Category

# Merchant name → category. Substring match; first hit wins.
merchant_rules: dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通費",
    "JR東日本": "交通費",
}

# Ambiguous merchants: never classified by merchant name alone.
ambiguous_merchants: list[str] = [
    "Amazon",
    "楽天",
    "イオン",
    "ドンキホーテ",
    "メルカリ",
]

# Item keyword → category.
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
# 3. backend/app/models.py (tax_amount + category_master)
# ===========================================================================
echo "==> backend/app/models.py"
cat > backend/app/models.py <<'EOF'
"""SQLModel database models.

C1+C2 additions:
    - Transaction.tax_amount: 表示用税額 (税込amountから逆算保存)
    - CategoryMaster: カテゴリ名→税率の正書テーブル
"""
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
    amount: int  # 税込総額
    tax_amount: int = 0  # 表示用税額 (amount - tax_amount で税抜)
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
    """カテゴリマスタ (税率を含む正書)."""
    __tablename__ = "category_master"
    name: str = Field(primary_key=True)
    description: str = ""
    tax_rate: int = 10  # %
    sort_order: int = 0


class CategoryMasterRead(SQLModel):
    name: str
    description: str
    tax_rate: int
    sort_order: int


def calc_tax_amount(amount_incl_tax: int, tax_rate: int) -> int:
    """税込金額から税額を逆算 (四捨五入).

    例: amount=620, tax_rate=8 → 46
        amount=1100, tax_rate=10 → 100
    """
    if amount_incl_tax <= 0 or tax_rate <= 0:
        return 0
    return round(amount_incl_tax * tax_rate / (100 + tax_rate))
EOF

# ===========================================================================
# 4. backend/app/routers/categories.py (新規)
# ===========================================================================
echo "==> backend/app/routers/categories.py"
cat > backend/app/routers/categories.py <<'EOF'
"""カテゴリマスタ API."""
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
# 5. backend/app/database.py の seed 関数
# ===========================================================================
echo "==> backend/app/database.py (seed 追加)"
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

engine = create_engine(
    DB_URL,
    echo=False,
    connect_args={"check_same_thread": False},
)


# Initial categories matching docs/classification-policy.md.
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
    """カテゴリマスタが空なら初期データを投入."""
    from .models import CategoryMaster
    with Session(engine) as session:
        existing = session.exec(select(CategoryMaster)).first()
        if existing is not None:
            return
        for name, desc, rate, order in _INITIAL_CATEGORIES:
            session.add(CategoryMaster(
                name=name, description=desc, tax_rate=rate, sort_order=order,
            ))
        session.commit()


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
EOF

# ===========================================================================
# 6. backend/app/routers/receipts.py (tax_amount 自動計算)
# ===========================================================================
echo "==> backend/app/routers/receipts.py"
cat > backend/app/routers/receipts.py <<'EOF'
"""Receipt upload: image → OCR → classify → auto-save with tax calculation."""
from __future__ import annotations

from datetime import date, datetime
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from app.classifier import ReceiptInput, classify_receipt
from app.database import get_session
from app.models import (
    CategoryMaster,
    Receipt,
    Transaction,
    UserCategoryOverride,
    calc_tax_amount,
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
    classification = classify_receipt(
        ReceiptInput(
            merchantRaw=fields.merchant_raw,
            items=fields.items,
            totalAmount=fields.total_amount,
            userCategoryOverrides=overrides if overrides else None,
        )
    )

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
# 7. backend/app/routers/transactions.py に tax_amount 自動再計算ロジック
# ===========================================================================
echo "==> backend/app/routers/transactions.py (PATCH時のtax_amount再計算)"
cat > backend/app/routers/transactions.py <<'EOF'
"""Transactions CRUD endpoints.

PATCH時、screening_category または amount が変わった場合、tax_amount を自動再計算.
"""
from __future__ import annotations

from datetime import date, datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlmodel import Session, select

from app.database import get_session
from app.models import (
    CategoryMaster,
    Transaction,
    TransactionCreate,
    TransactionRead,
    TransactionUpdate,
    calc_tax_amount,
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
def create_transaction(
    payload: TransactionCreate, session: Session = Depends(get_session)
) -> Transaction:
    data = payload.model_dump()
    # tax_amount が 0 のままなら自動計算
    if data.get("tax_amount", 0) == 0 and data.get("amount", 0) > 0:
        rate = _tax_rate_for(data.get("screening_category"), session)
        data["tax_amount"] = calc_tax_amount(data["amount"], rate)
    tx = Transaction(**data)
    session.add(tx)
    session.commit()
    session.refresh(tx)
    return tx


@router.patch("/{tx_id}", response_model=TransactionRead)
def update_transaction(
    tx_id: int,
    payload: TransactionUpdate,
    session: Session = Depends(get_session),
) -> Transaction:
    tx = session.get(Transaction, tx_id)
    if tx is None:
        raise HTTPException(status_code=404, detail="not found")
    data = payload.model_dump(exclude_unset=True)
    for k, v in data.items():
        setattr(tx, k, v)
    # category or amount が変更された & tax_amount が明示更新されていない場合は再計算
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
# 8. backend/app/main.py (categories router 登録)
# ===========================================================================
echo "==> backend/app/main.py"
cat > backend/app/main.py <<'EOF'
"""FastAPI entry point — C1+C2."""
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


app = FastAPI(
    title="kakeibo API",
    version="0.3.0",
    description="C1+C2: 9-category system with tax rates",
    lifespan=lifespan,
)

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
# 9. fixtures/receipts/*.json 更新 (期待カテゴリを新体系へ)
# ===========================================================================
echo "==> fixtures/receipts/basic.json"
cat > fixtures/receipts/basic.json <<'EOF'
[
  {
    "name": "convenience_food",
    "input": {
      "merchantRaw": "ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
      "items": ["おにぎり", "牛乳"],
      "totalAmount": 620
    },
    "expected": { "category": "食費", "needsReview": false }
  },
  {
    "name": "ambiguous_amazon_no_items",
    "input": {
      "merchantRaw": "Amazon.co.jp",
      "items": [],
      "totalAmount": 3000
    },
    "expected": { "category": null, "needsReview": true }
  },
  {
    "name": "drugstore_daily_goods",
    "input": {
      "merchantRaw": "マツモトキヨシ 新宿店",
      "items": ["洗剤"],
      "totalAmount": 480
    },
    "expected": { "category": "日用品", "needsReview": false }
  }
]
EOF

echo "==> fixtures/receipts/evaluation.json"
cat > fixtures/receipts/evaluation.json <<'EOF'
[
  {
    "name": "seven_food",
    "input": {
      "merchantRaw": "ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
      "items": ["おにぎり", "牛乳"],
      "totalAmount": 620
    },
    "expected": { "category": "食費", "needsReview": false }
  },
  {
    "name": "amazon_no_items",
    "input": {
      "merchantRaw": "Amazon.co.jp",
      "items": [],
      "totalAmount": 3000
    },
    "expected": { "category": null, "needsReview": true }
  },
  {
    "name": "aeon_mixed_items",
    "input": {
      "merchantRaw": "イオン",
      "items": ["牛乳", "洗剤"],
      "totalAmount": 980
    },
    "expected": { "category": null, "needsReview": true }
  },
  {
    "name": "liquor_beer",
    "input": {
      "merchantRaw": "酒屋A",
      "items": ["ビール"],
      "totalAmount": 850
    },
    "expected": { "category": "酒類", "needsReview": false }
  },
  {
    "name": "gas_station",
    "input": {
      "merchantRaw": "ENEOS 渋谷",
      "items": ["ガソリン"],
      "totalAmount": 5000
    },
    "expected": { "category": "交通費", "needsReview": false }
  }
]
EOF

# ===========================================================================
# 10. backend/tests/test_classify.py 更新
# ===========================================================================
echo "==> backend/tests/test_classify.py"
cat > backend/tests/test_classify.py <<'EOF'
"""Tests for classify_receipt — updated for 9-category system."""
from __future__ import annotations

from app.classifier import ReceiptInput, classify_receipt


def test_seven_eleven_classified_as_food():
    r = classify_receipt(ReceiptInput(
        merchantRaw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
        items=["おにぎり", "牛乳"],
        totalAmount=620,
    ))
    assert r.category == "食費"
    assert r.needsReview is False
    assert "merchant_rule: セブンイレブン" in r.reasons
    assert r.screeningLabel == "recordable"


def test_merchant_rule_takes_priority_over_item_keyword():
    r = classify_receipt(ReceiptInput(
        merchantRaw="マツモトキヨシ 新宿店",
        items=["おにぎり"],
        totalAmount=480,
    ))
    assert r.category == "日用品"
    assert r.reason == "rule_match: 日用品"
    assert r.reasons == ["merchant_rule: マツモトキヨシ"]


def test_user_override_has_highest_priority():
    r = classify_receipt(ReceiptInput(
        merchantRaw="Amazon.co.jp",
        items=[],
        userCategoryOverrides={"Amazon": "娯楽費"},
        totalAmount=3000,
    ))
    assert r.category == "娯楽費"
    assert r.needsReview is False
    assert r.reason == "user_override: 娯楽費"


def test_item_keyword_classification_when_no_merchant_rule():
    r = classify_receipt(ReceiptInput(
        merchantRaw="不明店舗",
        items=["ガソリン"],
        totalAmount=3000,
    ))
    assert r.category == "交通費"
    assert r.needsReview is False
    assert r.reasons == ["item_keyword: ガソリン"]


def test_amazon_without_items_needs_review():
    r = classify_receipt(ReceiptInput(
        merchantRaw="Amazon.co.jp",
        items=[],
        totalAmount=3000,
    ))
    assert r.category is None
    assert r.needsReview is True
    assert r.reasons == ["ambiguous_merchant_no_items"]
    assert r.screeningLabel == "needs_review"


def test_amazon_with_items_still_needs_review():
    r = classify_receipt(ReceiptInput(
        merchantRaw="Amazon.co.jp",
        items=["シャツ"],
        totalAmount=3000,
    ))
    assert r.category is None
    assert r.needsReview is True
    assert r.reason == "ambiguous merchant requires manual category"


def test_no_rule_match_needs_review():
    r = classify_receipt(ReceiptInput(
        merchantRaw="未知の店舗",
        items=["未知の品目"],
        totalAmount=1000,
    ))
    assert r.category is None
    assert r.needsReview is True
    assert r.reason == "no rule matched"


def test_beer_classified_as_liquor():
    r = classify_receipt(ReceiptInput(
        merchantRaw="酒屋",
        items=["ビール"],
        totalAmount=500,
    ))
    assert r.category == "酒類"
    assert r.needsReview is False
    assert r.reasons == ["item_keyword: ビール"]


def test_shirt_classified_as_clothing():
    r = classify_receipt(ReceiptInput(
        merchantRaw="アパレル店",
        items=["シャツ"],
        totalAmount=3000,
    ))
    assert r.category == "衣料費"
    assert r.needsReview is False
EOF

# ===========================================================================
# 11. backend/tests/test_tax.py (新規: tax計算テスト)
# ===========================================================================
echo "==> backend/tests/test_tax.py"
cat > backend/tests/test_tax.py <<'EOF'
"""Tests for tax amount calculation."""
from __future__ import annotations

import pytest

from app.models import calc_tax_amount


@pytest.mark.parametrize("amount, rate, expected", [
    (620, 8, 46),       # 620 * 8/108 = 45.92 → 46
    (1080, 8, 80),      # 1080 * 8/108 = 80
    (1100, 10, 100),    # 1100 * 10/110 = 100
    (550, 10, 50),
    (0, 10, 0),
    (-100, 10, 0),
    (1000, 0, 0),
    (1000, -5, 0),
])
def test_calc_tax_amount(amount: int, rate: int, expected: int):
    assert calc_tax_amount(amount, rate) == expected
EOF

# ===========================================================================
# 12. frontend/src/types.ts
# ===========================================================================
echo "==> frontend/src/types.ts"
cat > frontend/src/types.ts <<'EOF'
// 9-category system with tax rate.

export type Category =
  | "食費"
  | "酒類"
  | "外食"
  | "日用品"
  | "交通費"
  | "医療費"
  | "娯楽費"
  | "衣料費"
  | "その他";

export const CATEGORIES: Category[] = [
  "食費", "酒類", "外食", "日用品",
  "交通費", "医療費", "娯楽費", "衣料費", "その他",
];

// Fallback when /api/categories is not yet loaded.
export const DEFAULT_TAX_RATE: Record<Category, number> = {
  "食費": 8,
  "酒類": 10,
  "外食": 10,
  "日用品": 10,
  "交通費": 10,
  "医療費": 10,
  "娯楽費": 10,
  "衣料費": 10,
  "その他": 10,
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
# 13. frontend/src/api.ts (categories追加)
# ===========================================================================
echo "==> frontend/src/api.ts"
cat > frontend/src/api.ts <<'EOF'
import type {
  CategoryMaster,
  ReceiptUploadResponse,
  Transaction,
  UserCategoryOverride,
} from "./types";

const BASE = "/api";

async function handle<T>(r: Response): Promise<T> {
  if (!r.ok) {
    const text = await r.text();
    throw new Error(`${r.status}: ${text}`);
  }
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

export async function updateTransaction(
  id: number,
  patch: Partial<Transaction>
): Promise<Transaction> {
  const r = await fetch(`${BASE}/transactions/${id}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json" },
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

export async function createOverride(
  merchant_pattern: string,
  category: string
): Promise<UserCategoryOverride> {
  const r = await fetch(`${BASE}/overrides`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
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
# 14. frontend/src/components/EditView.tsx (taxRate表示追加)
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
    listCategories().then(setCatMaster).catch(() => {
      // fallback to constants
    });
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
    setBusy(true);
    setError(null);
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
    } catch (e) {
      setError(String(e));
    } finally {
      setBusy(false);
    }
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
            {CATEGORIES.map((c) => (
              <option key={c} value={c}>{c}</option>
            ))}
          </select>

          <label>税率</label>
          <div className="tax-info">
            {category ? `${taxRate}%` : "(カテゴリ未選択)"}
          </div>

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
# 15. frontend/src/App.css に tax-info スタイル追加
# ===========================================================================
echo "==> frontend/src/App.css (tax-info追加)"
if ! grep -q "tax-info" frontend/src/App.css; then
  cat >> frontend/src/App.css <<'EOF'

.tax-info { padding: 6px 10px; color: #57606a; font-size: 0.9em; }
EOF
fi

# ===========================================================================
# 16. docs/classification-policy.md
# ===========================================================================
echo "==> docs/classification-policy.md"
cat > docs/classification-policy.md <<'EOF'
# Classification Policy

## 目的
家計簿アプリ向けに、レシート情報をカテゴリ分類する.

## カテゴリ一覧 (9種、税率付き)
| カテゴリ | 税率 | 説明 |
|---|---|---|
| 食費 | 8% | スーパー, コンビニ, 弁当, 食品 |
| 酒類 | 10% | ビール, ワイン, 日本酒, チューハイ |
| 外食 | 10% | レストラン, カフェ, 居酒屋 |
| 日用品 | 10% | ドラッグストア, 洗剤, トイレ, キッチン |
| 交通費 | 10% | 電車, バス, タクシー, ガソリン, 駐車場 |
| 医療費 | 10% | 病院, 薬局, 医薬品, 診察 |
| 娯楽費 | 10% | 書店, 映画, ゲーム, 趣味, レジャー |
| 衣料費 | 10% | アパレル, 靴, ファッション, クリーニング |
| その他 | 10% | 判断できないもの |

カテゴリと税率の正書: `backend/app/database.py` の `_INITIAL_CATEGORIES`、DB `category_master` テーブル.

## 現在の対象
- 店舗名正規化
- 店舗単位分類
- 明細キーワード分類
- needsReview 判定
- confidence 算出
- 税額算出 (税込金額 → 表示用税額)

## 次フェーズ対象
- 明細単位カテゴリ分け (C4)
- 税込/税抜の表示切替UI (C5)

## 危険店舗
以下は店舗名だけで分類確定しない:
Amazon / 楽天 / イオン / ドンキホーテ / メルカリ

## 基本ルール
1. ユーザー修正ルールを最優先
2. 店舗名ルール
3. 明細キーワードルール
4. 曖昧店舗は needsReview=true
5. 分類不能も needsReview=true

## 金額保存方式
- レシート印字の金額 = 税込総額 → そのまま `amount` に保存
- `tax_amount` は表示参考用に逆算保存 (`amount - tax_amount` で税抜)
- カテゴリ変更時は PATCH API が自動再計算
EOF

# ===========================================================================
# 17. AGENTS.md カテゴリ表更新
# ===========================================================================
echo "==> AGENTS.md (カテゴリ表更新)"
python3 <<'PY'
import re
from pathlib import Path

agents = Path("AGENTS.md")
text = agents.read_text(encoding="utf-8")

new_categories = "### カテゴリ (9種、税率付き)\n食費(8%) / 酒類(10%) / 外食(10%) / 日用品(10%) / 交通費(10%) / 医療費(10%) / 娯楽費(10%) / 衣料費(10%) / その他(10%)\n\n税率の正書は backend/app/database.py の `_INITIAL_CATEGORIES` および DB `category_master` テーブル."

# 旧「### カテゴリ（固定）」セクションを置換
pattern = r"### カテゴリ.*?(?=\n###|\n##|\Z)"
if re.search(pattern, text, re.DOTALL):
    text = re.sub(pattern, new_categories + "\n", text, count=1, flags=re.DOTALL)
    agents.write_text(text, encoding="utf-8")
    print("  AGENTS.md updated")
else:
    # 該当セクションなし、末尾に追加
    if "### カテゴリ (9種" not in text:
        with agents.open("a", encoding="utf-8") as f:
            f.write("\n\n" + new_categories + "\n")
        print("  AGENTS.md appended")
    else:
        print("  AGENTS.md already updated")
PY

# ===========================================================================
# 18. DB 削除
# ===========================================================================
echo ""
echo "==> reset data.db (カテゴリ体系変更のため)"
rm -f backend/data.db backend/data.db-journal backend/data.db-wal backend/data.db-shm

# ===========================================================================
# 19. pytest
# ===========================================================================
echo ""
echo "==> backend pytest"
cd backend && uv run pytest -v 2>&1 | tail -40
cd "$REPO"

# ===========================================================================
# 20. uvicorn / vite 再起動
# ===========================================================================
echo ""
echo "==> restart servers"
pkill -f uvicorn 2>/dev/null || true
pkill -f vite 2>/dev/null || true
sleep 1

cd backend
nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &
sleep 4
cd "$REPO"

cd frontend
nohup npm run dev > /tmp/vite.log 2>&1 &
sleep 5
cd "$REPO"

echo ""
echo "==> backend health"
curl -s http://localhost:8000/api/health && echo

echo ""
echo "==> categories API"
curl -s http://localhost:8000/api/categories | python3 -m json.tool | head -20

cat <<EOM

============================================================
C1+C2 セットアップ完了.

変更点:
  - カテゴリ: 8 -> 9 (酒類・外食 新設, 通信・教育 削除, 交通/医療/娯楽 リネーム)
  - tax_rate: カテゴリマスタテーブルで管理 (食費のみ8%, 他10%)
  - tax_amount: 税込金額から逆算保存 (表示用)
  - GET /api/categories で取得可能

確認: http://localhost:5173 (家計簿UI)
  編集モーダルで「税率」「税抜換算」が表示されます.

次回 C3 (CSV取込+グラフ+同時画面) は別ターンで.
============================================================
EOM
