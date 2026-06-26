"""Receipt OCR API.

    Existing compatibility endpoint.

- /api/receipts/preview:
    E2E encryption-oriented endpoint.
    Runs OCR/classification only.
    Does NOT save uploaded image.
    Does NOT save Receipt / Transaction / TransactionItem records.
    Frontend should encrypt the returned payload and save it to /api/encrypted-tx.
"""

from __future__ import annotations

from datetime import date
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from app.classifier import ReceiptInput, classify_line_items, classify_receipt
from app.database import get_session
from app.models import (
    CategoryMaster,
    UserCategoryOverride,
    calc_tax_amount,
)
from app.ocr.gemini_extract import extract_with_gemini, is_gemini_available

router = APIRouter(prefix="/api/receipts", tags=["receipts"])

_BACKEND_ROOT = Path(__file__).resolve().parent.parent.parent
UPLOAD_DIR = _BACKEND_ROOT / "uploads"
UPLOAD_DIR.mkdir(parents=True, exist_ok=True)

_ALLOWED_EXT = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}
_MAX_BYTES = 15 * 1024 * 1024

_MIME_MAP = {
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
    ".heic": "image/heic",
    ".heif": "image/heif",
}


class LineItemOut(BaseModel):
    item: str
    amount: int
    amount_extracted: bool
    category: str | None
    reason: str


class ReceiptPreviewResponse(BaseModel):
    """OCR/classification response without any plaintext persistence."""

    ocr_engine: str
    raw_text: str
    merchant_raw: str
    items: list[str]
    total_amount: int | None
    amount: int
    tax_rate: int
    tax_amount: int
    purchased_at: date
    classification: dict
    line_items: list[LineItemOut]
    category: str | None
    needs_review: bool
    confidence: float
    reason: str


def _load_overrides(session: Session) -> dict[str, str]:
    rows = session.exec(select(UserCategoryOverride)).all()
    return {row.merchant_pattern: row.category for row in rows}


def _tax_rate_for(category: str | None, session: Session) -> int:
    if category is None:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


def _load_tesseract_runtime():
    """Import image and OCR libraries only when receipt OCR is requested."""
    try:
        from app.ocr.extract import extract_receipt_fields, run_ocr
        from app.ocr.preprocess import load_image, preprocess_for_ocr
    except (ImportError, OSError) as exc:
        raise HTTPException(
            status_code=503,
            detail={
                "code": "ocr_runtime_unavailable",
                "message": (
                    "OCR実行環境がありません。OpenCV、Pillow、pillow-heif、"
                    "pytesseractとTesseract本体を追加するか、Gemini OCRを設定してください。"
                ),
            },
        ) from exc

    return extract_receipt_fields, load_image, preprocess_for_ocr, run_ocr


async def _read_upload_file(file: UploadFile) -> tuple[str, bytes]:
    ext = Path(file.filename or "").suffix.lower()
    if ext not in _ALLOWED_EXT:
        raise HTTPException(status_code=400, detail=f"unsupported: {ext}")

    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"too large: {len(data)}")

    return ext, data


def _analyze_receipt(
    *,
    data: bytes,
    ext: str,
    session: Session,
) -> ReceiptPreviewResponse:
    """Run OCR/classification without writing image or OCR result to DB."""

    overrides = _load_overrides(session)
    mime = _MIME_MAP.get(ext, "image/jpeg")

    ocr_engine = "tesseract"
    merchant_raw = ""
    raw_text = ""
    total_amount: int | None = None
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
                parsed_items.append(
                    (
                        li.name,
                        li.amount,
                        li.category,
                        li.amount > 0,
                    )
                )
        except Exception as e:
            # Fall back to Tesseract. The fallback result will become raw_text.
            raw_text = f"[Gemini失敗→Tesseract] {e}"
            gemini_ok = False

    if not gemini_ok:
        (
            extract_receipt_fields,
            load_image,
            preprocess_for_ocr,
            run_ocr,
        ) = _load_tesseract_runtime()

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

        item_names = [li.name for li in fields.line_items]
        line_classifications = classify_line_items(
            item_names,
            fields.merchant_raw,
            overrides or None,
        )

        for ocr_item, line_classification in zip(fields.line_items, line_classifications):
            amount = ocr_item.amount or 0
            parsed_items.append(
                (
                    ocr_item.name,
                    amount,
                    line_classification.category,
                    ocr_item.amount is not None,
                )
            )

    item_name_list = [name for (name, _amount, _category, _extracted) in parsed_items]

    classification = classify_receipt(
        ReceiptInput(
            merchantRaw=merchant_raw,
            items=item_name_list,
            totalAmount=total_amount,
            userCategoryOverrides=overrides if overrides else None,
        )
    )

    header_category = classification.category

    # If Gemini returned line item categories, prefer the category with largest amount.
    if gemini_ok and parsed_items:
        by_cat: dict[str, int] = {}
        for (_name, amount, category, _extracted) in parsed_items:
            if category:
                by_cat[category] = by_cat.get(category, 0) + amount
        if by_cat:
            header_category = max(by_cat.items(), key=lambda item: item[1])[0]

    amount = (
        total_amount
        or sum(item_amount for (_name, item_amount, _category, _extracted) in parsed_items)
        or 0
    )
    tax_rate = _tax_rate_for(header_category, session)
    tax_amount = calc_tax_amount(amount, tax_rate)

    response_items = [
        LineItemOut(
            item=name,
            amount=item_amount,
            amount_extracted=extracted,
            category=category,
            reason=f"{ocr_engine}_extract",
        )
        for (name, item_amount, category, extracted) in parsed_items
    ]

    return ReceiptPreviewResponse(
        ocr_engine=ocr_engine,
        raw_text=raw_text,
        merchant_raw=merchant_raw,
        items=item_name_list,
        total_amount=total_amount,
        amount=amount,
        tax_rate=tax_rate,
        tax_amount=tax_amount,
        purchased_at=purchased_at_val,
        classification=classification.model_dump(),
        line_items=response_items,
        category=header_category,
        needs_review=classification.needsReview,
        confidence=classification.confidence,
        reason=f"{ocr_engine}: {classification.reason}",
    )


@router.post("/preview", response_model=ReceiptPreviewResponse)
async def preview_receipt(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
) -> ReceiptPreviewResponse:
    """Run OCR/classification without saving image or plaintext records.

    This endpoint is intended for E2E encryption flow:
      frontend uploads image -> backend previews OCR -> frontend encrypts result
      -> frontend stores encrypted payload via /api/encrypted-tx.
    """

    ext, data = await _read_upload_file(file)
    return _analyze_receipt(data=data, ext=ext, session=session)
