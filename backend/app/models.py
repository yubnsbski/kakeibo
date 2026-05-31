"""Shared SQLModel models for category metadata and user overrides."""
from __future__ import annotations

from datetime import datetime
from typing import Optional

from sqlmodel import Field, SQLModel


class UserCategoryOverride(SQLModel, table=True):
    __tablename__ = "user_category_overrides"

    id: Optional[int] = Field(default=None, primary_key=True)
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
    is_income: bool = False


class CategoryMasterRead(SQLModel):
    name: str
    description: str
    tax_rate: int
    sort_order: int
    is_income: bool


def calc_tax_amount(amount_incl_tax: int, tax_rate: int) -> int:
    if amount_incl_tax <= 0 or tax_rate <= 0:
        return 0
    return round(amount_incl_tax * tax_rate / (100 + tax_rate))
