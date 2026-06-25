"""Amount-expression calculation API.

The endpoint receives only the expression and tax rate. Merchant, category,
and memo remain in the browser-side encrypted payload.
"""
from __future__ import annotations

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.calculation import PriceExpressionError, calculate_amount

router = APIRouter(prefix="/api/calculations", tags=["calculations"])


class AmountCalculationIn(BaseModel):
    expression: str = Field(min_length=1, max_length=200)
    tax_rate: int = Field(ge=0, le=100)


class AmountCalculationOut(BaseModel):
    amount: int
    tax_rate: int
    tax_amount: int


@router.post("/amount", response_model=AmountCalculationOut)
def calculate_amount_endpoint(payload: AmountCalculationIn) -> AmountCalculationOut:
    try:
        result = calculate_amount(payload.expression, payload.tax_rate)
    except PriceExpressionError as exc:
        raise HTTPException(
            status_code=422,
            detail={
                "code": "invalid_amount_expression",
                "message": str(exc),
            },
        ) from exc

    return AmountCalculationOut(
        amount=result.amount,
        tax_rate=result.tax_rate,
        tax_amount=result.tax_amount,
    )
