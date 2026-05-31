"""CSV import API — supports expense/income via signed amount."""
from __future__ import annotations

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session

from app.csv_import import (
    CsvRow, ValidationErrorCode, parse_csv, validate_all,
    VALID_CATEGORIES, INCOME_CATEGORIES,
)
from app.database import get_session
from app.models import CategoryMaster

router = APIRouter(prefix="/api/csv", tags=["csv"])

_MAX_BYTES = 5 * 1024 * 1024


class CsvPreviewRow(BaseModel):
    date: str
    amount: int | None
    tx_type: str
    category: str
    category_raw: str
    memo: str
    validation_error: ValidationErrorCode | None = None
    validation_message: str | None = None


class CsvPreviewResponse(BaseModel):
    total: int
    error_count: int
    rows: list[CsvPreviewRow]
    header_error: str | None = None


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
        rows=[CsvPreviewRow(
            date=r.date, amount=r.amount, tx_type=r.tx_type,
            category=r.category, category_raw=r.category_raw, memo=r.memo,
            validation_error=r.validation_error,
            validation_message=r.validation_message,
        ) for r in rows],
    )
