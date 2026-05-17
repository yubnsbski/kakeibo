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
