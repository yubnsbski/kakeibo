"""Amount-expression calculation API.

The endpoint receives only the expression, tax rate, and tax interpretation.
Merchant, category, and memo remain in the browser-side encrypted payload.
"""
from __future__ import annotations

from typing import Literal

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from app.calculation import PriceExpressionError, calculate_amount

router = APIRouter(prefix="/api/calculations", tags=["calculations"])


class AmountCalculationIn(BaseModel):
    expression: str = Field(min_length=1, max_length=200)
    tax_rate: int = Field(ge=0, le=100)
    amount_mode: Literal["tax_included", "tax_excluded"] = "tax_included"


class AmountCalculationOut(BaseModel):
    amount: int
    net_amount: int
    tax_rate: int
    tax_amount: int
    input_amount: int
    amount_mode: Literal["tax_included", "tax_excluded"]


@router.post("/amount", response_model=AmountCalculationOut)
def calculate_amount_endpoint(payload: AmountCalculationIn) -> AmountCalculationOut:
    try:
        result = calculate_amount(
            payload.expression,
            payload.tax_rate,
            payload.amount_mode,
        )
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
        net_amount=result.net_amount,
        tax_rate=result.tax_rate,
        tax_amount=result.tax_amount,
        input_amount=result.input_amount,
        amount_mode=result.amount_mode,
    )
