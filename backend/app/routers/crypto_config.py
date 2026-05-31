"""暗号設定 API — 鍵導出パラメータ (salt) の保存・取得.

salt は秘密情報ではないため、サーバーに平文保存してよい。
パスフレーズ・鍵・リカバリーコードは一切サーバーに送られない。
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from app.crypto_models import AppCryptoConfig
from app.database import get_session

router = APIRouter(prefix="/api/crypto", tags=["crypto"])


class CryptoConfigOut(BaseModel):
    """salt 取得レスポンス."""

    salt: str
    iterations: int


class CryptoConfigIn(BaseModel):
    """salt 初回保存リクエスト."""

    salt: str
    iterations: int


@router.get("/config", response_model=CryptoConfigOut)
def get_crypto_config(session: Session = Depends(get_session)) -> CryptoConfigOut:
    """salt を取得する.

    未設定 (初回起動) なら 404。フロントはこれを見て初回セットアップ画面を出す。
    """
    row = session.exec(select(AppCryptoConfig)).first()
    if row is None:
        raise HTTPException(status_code=404, detail="crypto config not set up")
    return CryptoConfigOut(salt=row.salt, iterations=row.iterations)


@router.post("/config", response_model=CryptoConfigOut)
def create_crypto_config(
    payload: CryptoConfigIn,
    session: Session = Depends(get_session),
) -> CryptoConfigOut:
    """salt を初回保存する.

    既に設定済みの場合は 409 (salt を上書きすると既存データが復号不能になるため)。
    """
    existing = session.exec(select(AppCryptoConfig)).first()
    if existing is not None:
        raise HTTPException(
            status_code=409,
            detail="crypto config already exists (salt は上書き不可)",
        )
    if not payload.salt or payload.iterations <= 0:
        raise HTTPException(status_code=400, detail="invalid salt or iterations")

    row = AppCryptoConfig(salt=payload.salt, iterations=payload.iterations)
    session.add(row)
    session.commit()
    session.refresh(row)
    return CryptoConfigOut(salt=row.salt, iterations=row.iterations)
