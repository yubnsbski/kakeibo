"""暗号化取引 API — encrypted_payload の CRUD."""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from app.crypto_models import EncryptedTransaction
from app.database import get_session

router = APIRouter(prefix="/api/encrypted-tx", tags=["encrypted-tx"])


class EncryptedTxOut(BaseModel):
    id: int
    encrypted_payload: str
    payload_version: int
    created_at: datetime
    updated_at: datetime


class EncryptedTxIn(BaseModel):
    encrypted_payload: str
    payload_version: int = 1


def _to_out(row: EncryptedTransaction) -> EncryptedTxOut:
    return EncryptedTxOut(
        id=row.id,
        encrypted_payload=row.encrypted_payload,
        payload_version=row.payload_version,
        created_at=row.created_at,
        updated_at=row.updated_at,
    )


@router.get("", response_model=list[EncryptedTxOut])
def list_encrypted_tx(
    session: Session = Depends(get_session),
) -> list[EncryptedTxOut]:
    rows = session.exec(
        select(EncryptedTransaction).order_by(EncryptedTransaction.id.desc())
    ).all()
    return [_to_out(r) for r in rows]


@router.post("", response_model=EncryptedTxOut)
def create_encrypted_tx(
    payload: EncryptedTxIn,
    session: Session = Depends(get_session),
) -> EncryptedTxOut:
    if not payload.encrypted_payload:
        raise HTTPException(status_code=400, detail="empty encrypted_payload")
    row = EncryptedTransaction(
        encrypted_payload=payload.encrypted_payload,
        payload_version=payload.payload_version,
    )
    session.add(row)
    session.commit()
    session.refresh(row)
    return _to_out(row)


@router.patch("/{tx_id}", response_model=EncryptedTxOut)
def update_encrypted_tx(
    tx_id: int,
    payload: EncryptedTxIn,
    session: Session = Depends(get_session),
) -> EncryptedTxOut:
    row = session.get(EncryptedTransaction, tx_id)
    if row is None:
        raise HTTPException(status_code=404, detail="not found")
    if not payload.encrypted_payload:
        raise HTTPException(status_code=400, detail="empty encrypted_payload")
    row.encrypted_payload = payload.encrypted_payload
    row.payload_version = payload.payload_version
    row.updated_at = datetime.utcnow()
    session.add(row)
    session.commit()
    session.refresh(row)
    return _to_out(row)


@router.delete("/{tx_id}")
def delete_encrypted_tx(
    tx_id: int,
    session: Session = Depends(get_session),
) -> dict:
    row = session.get(EncryptedTransaction, tx_id)
    if row is None:
        raise HTTPException(status_code=404, detail="not found")
    session.delete(row)
    session.commit()
    return {"deleted": tx_id}
