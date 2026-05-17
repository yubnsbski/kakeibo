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
