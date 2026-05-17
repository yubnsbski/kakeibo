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
