"""E2E暗号化関連の DB モデル.

設計方針:
  - 既存 models.py には手を加えず、暗号化関連のテーブルをこのファイルに集約する。
  - サーバーは encrypted_payload の中身を一切解釈しない。保存・返却するだけ。
  - salt は秘密情報ではないため、サーバー保存して問題ない
    (salt が漏れても、パスフレーズが分からなければ鍵は導出できない)。
"""
from __future__ import annotations

from datetime import datetime

from sqlmodel import Field, SQLModel


class AppCryptoConfig(SQLModel, table=True):
    """アプリ全体の暗号設定 (鍵導出パラメータ).

    単一パスフレーズ運用のため、レコードは基本的に1行のみ。
    salt は初回セットアップ時に生成され、以降不変。
    """

    __tablename__ = "app_crypto_config"

    id: int | None = Field(default=None, primary_key=True)
    # PBKDF2 ソルト (base64 文字列)。
    salt: str
    # PBKDF2 反復回数。
    iterations: int
    created_at: datetime = Field(default_factory=datetime.utcnow)


class EncryptedTransaction(SQLModel, table=True):
    """暗号化された取引レコード.

    encrypted_payload には、フロントで暗号化された JSON 文字列が入る。
    中身の例 (復号後): {"amount":1200,"merchant":"...","category":"食費",...}
    サーバーはこの中身を解釈しない。
    """

    __tablename__ = "encrypted_transactions"

    id: int | None = Field(default=None, primary_key=True)
    # フロントで暗号化された payload (EncryptedRecord を JSON 文字列化したもの)。
    encrypted_payload: str
    # payload スキーマのバージョン。将来の移行用。
    payload_version: int = Field(default=1)
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)
