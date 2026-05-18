"""CSV import API — new contract: date,amount,category,memo."""
from __future__ import annotations

from datetime import date as date_type
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session

from app.csv_import import (
    CsvRow, ValidationErrorCode, parse_csv, validate_all, VALID_CATEGORIES,
)
from app.database import get_session
from app.models import (
    CategoryMaster, Transaction, calc_tax_amount,
)

router = APIRouter(prefix="/api/csv", tags=["csv"])

_MAX_BYTES = 5 * 1024 * 1024


class CsvPreviewRow(BaseModel):
    date: str
    amount: int | None
    category: str
    memo: str
    validation_error: ValidationErrorCode | None = None
    validation_message: str | None = None


class CsvPreviewResponse(BaseModel):
    total: int
    error_count: int
    rows: list[CsvPreviewRow]
    header_error: str | None = None


class CsvCommitResponse(BaseModel):
    inserted: int
    skipped: int
    error_count: int


def _tax_rate_for(category: str | None, session: Session) -> int:
    if category is None or not category:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


async def _read_csv(file: UploadFile) -> str:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"too large: {len(data)} bytes")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        try:
            return data.decode("cp932")
        except UnicodeDecodeError as e:
            raise HTTPException(status_code=400, detail=f"decode failed: {e}") from e


@router.post("/preview", response_model=CsvPreviewResponse)
async def preview_csv(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    text = await _read_csv(file)
    parsed = parse_csv(text)
    if parsed.header_error:
        return CsvPreviewResponse(
            total=0, error_count=0, rows=[], header_error=parsed.header_error,
        )
    rows = validate_all(parsed.rows)
    err_count = sum(1 for r in rows if r.validation_error)
    return CsvPreviewResponse(
        total=len(rows),
        error_count=err_count,
        rows=[CsvPreviewRow(**{
            "date": r.date, "amount": r.amount, "category": r.category, "memo": r.memo,
            "validation_error": r.validation_error,
            "validation_message": r.validation_message,
        }) for r in rows],
    )


@router.post("/commit", response_model=CsvCommitResponse)
async def commit_csv(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    text = await _read_csv(file)
    parsed = parse_csv(text)
    if parsed.header_error:
        raise HTTPException(status_code=400, detail=parsed.header_error)

    rows = validate_all(parsed.rows)
    inserted = 0
    err_count = 0
    for row in rows:
        if row.validation_error == "missing_date":
            # 日付エラーは取込不能
            err_count += 1
            continue
        if row.validation_error == "invalid_amount":
            err_count += 1
            continue
        # unknown_category は needs_review=True で取込
        category = row.category if row.category in VALID_CATEGORIES else None
        needs_review = (
            row.validation_error == "unknown_category"
            or not row.category
        )
        if row.validation_error == "unknown_category":
            err_count += 1

        rate = _tax_rate_for(category, session)
        merchant = row.memo or "(空)"
        tx = Transaction(
            merchant_raw=merchant,
            merchant_normalized=merchant,
            items_text="",
            screening_category=category,
            needs_review=needs_review,
            reason=row.validation_error or ("category empty" if not row.category else "csv_import"),
            confidence=1.0 if not needs_review else 0.0,
            amount=row.amount or 0,
            tax_amount=calc_tax_amount(row.amount or 0, rate),
            purchased_at=date_type.fromisoformat(row.date),
            memo=row.memo or None,
            status="manually_added",
        )
        session.add(tx)
        inserted += 1
    session.commit()
    return CsvCommitResponse(inserted=inserted, skipped=0, error_count=err_count)
