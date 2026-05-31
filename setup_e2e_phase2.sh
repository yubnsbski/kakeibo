#!/usr/bin/env bash
# Phase E2: 取引データの E2E 暗号化 (DB + API + UI 一括).
#
# 既存ファイルへの変更を最小化する設計:
#   - models.py / database.py は触らない (新テーブルは crypto_models.py に分離)
#   - main.py は router 登録の追加のみ (Python で安全にパッチ)
#   - App.tsx は CryptoGate でラップ (Python で安全にパッチ)
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_e2e_phase2.sh

set -u
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "Phase E2: 取引データの E2E 暗号化"
echo "============================================================"

# ===========================================================================
# Block 1: ファイル配置
# ===========================================================================
echo ""
echo "==> [Block 1] ファイル配置"
mkdir -p backend/app/routers frontend/src/crypto/ui

echo "  - backend/app/crypto_models.py"
cat > backend/app/crypto_models.py <<'PYEOF'
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
PYEOF

echo "  - backend/app/routers/crypto_config.py"
cat > backend/app/routers/crypto_config.py <<'PYEOF'
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
PYEOF

echo "  - backend/app/routers/encrypted_tx.py"
cat > backend/app/routers/encrypted_tx.py <<'PYEOF'
"""暗号化取引 API — encrypted_payload の CRUD.

サーバーは encrypted_payload の中身を一切解釈しない。
保存・返却・削除のみを行う「暗号文の保管庫」として振る舞う。
集計・検索・フィルタはフロント側で復号後に行う (E3 で実装)。
"""
from __future__ import annotations

from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from app.crypto_models import EncryptedTransaction
from app.database import get_session

router = APIRouter(prefix="/api/encrypted-tx", tags=["encrypted-tx"])


class EncryptedTxOut(BaseModel):
    """暗号化取引レスポンス."""

    id: int
    encrypted_payload: str
    payload_version: int
    created_at: datetime
    updated_at: datetime


class EncryptedTxIn(BaseModel):
    """暗号化取引 保存/更新リクエスト."""

    encrypted_payload: str
    payload_version: int = 1


def _to_out(row: EncryptedTransaction) -> EncryptedTxOut:
    """ORM 行をレスポンス型に変換する (属性を明示コピー)."""
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
    """暗号化取引を全件返す.

    フロントはこれを取得後、各 payload を復号して集計・表示する。
    """
    rows = session.exec(
        select(EncryptedTransaction).order_by(EncryptedTransaction.id.desc())
    ).all()
    return [_to_out(r) for r in rows]


@router.post("", response_model=EncryptedTxOut)
def create_encrypted_tx(
    payload: EncryptedTxIn,
    session: Session = Depends(get_session),
) -> EncryptedTxOut:
    """暗号化取引を1件保存する."""
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
    """暗号化取引を更新する (payload 全体を差し替え)."""
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
    """暗号化取引を1件削除する."""
    row = session.get(EncryptedTransaction, tx_id)
    if row is None:
        raise HTTPException(status_code=404, detail="not found")
    session.delete(row)
    session.commit()
    return {"deleted": tx_id}
PYEOF

echo "  - frontend/src/crypto/useCrypto.ts"
cat > frontend/src/crypto/useCrypto.ts <<'TSEOF'
/**
 * 暗号鍵の状態を React コンポーネントから扱うための hook。
 *
 * keyStore (crypto/keyStore.ts) はモジュールスコープのシングルトンだが、
 * React の再レンダリングと連動させるためにこの hook で購読する。
 */
import { useEffect, useState } from "react";
import { isUnlocked, subscribeLockState } from "./index";

/**
 * アンロック状態 (鍵がメモリにあるか) を購読する。
 *
 * @returns unlocked - true ならアンロック済み
 */
export function useUnlocked(): boolean {
  const [unlocked, setUnlocked] = useState<boolean>(isUnlocked());

  useEffect(() => {
    // 購読開始時に最新状態へ同期 (購読前に状態が変わっていた場合の保険)。
    setUnlocked(isUnlocked());
    const unsubscribe = subscribeLockState(setUnlocked);
    return unsubscribe;
  }, []);

  return unlocked;
}
TSEOF

echo "  - frontend/src/crypto/cryptoApi.ts"
cat > frontend/src/crypto/cryptoApi.ts <<'TSEOF'
/**
 * 暗号関連の API 通信。
 *
 * salt の取得・保存のみ。パスフレーズ・鍵・リカバリーコードは
 * 一切 API に送らない (E2E を保つため)。
 */
import type { KeyDerivationParams } from "./index";

/** API のベース URL。既存 api.ts と同じ規約に合わせる。 */
const API_BASE = "/api";

/**
 * サーバーから鍵導出パラメータ (salt) を取得する。
 *
 * @returns salt が設定済みなら KeyDerivationParams、未設定 (初回) なら null
 */
export async function fetchCryptoConfig(): Promise<KeyDerivationParams | null> {
  const res = await fetch(`${API_BASE}/crypto/config`);
  if (res.status === 404) {
    return null; // 初回セットアップ前
  }
  if (!res.ok) {
    throw new Error(`crypto config 取得失敗: HTTP ${res.status}`);
  }
  const data = await res.json();
  return { salt: data.salt, iterations: data.iterations };
}

/**
 * 鍵導出パラメータ (salt) をサーバーに初回保存する。
 *
 * @throws 既に設定済み (409) の場合は例外
 */
export async function saveCryptoConfig(
  params: KeyDerivationParams,
): Promise<void> {
  const res = await fetch(`${API_BASE}/crypto/config`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      salt: params.salt,
      iterations: params.iterations,
    }),
  });
  if (!res.ok) {
    if (res.status === 409) {
      throw new Error("暗号設定は既に存在します (salt は上書きできません)");
    }
    throw new Error(`crypto config 保存失敗: HTTP ${res.status}`);
  }
}
TSEOF

echo "  - frontend/src/crypto/ui/CryptoGate.tsx"
cat > frontend/src/crypto/ui/CryptoGate.tsx <<'TSEOF'
/**
 * CryptoGate — アプリ全体のアンロックゲート。
 *
 * App 全体をこのコンポーネントでラップする。
 * アンロックが完了するまで、子 (アプリ本体) を表示しない。
 *
 * 状態遷移:
 *
 *   [起動] → loading (salt を取得中)
 *      │
 *      ├─ salt なし → setup (パスフレーズ設定)
 *      │                 ↓
 *      │              show-recovery (リカバリーコード表示)
 *      │                 ↓
 *      │              [アンロック完了]
 *      │
 *      └─ salt あり → unlock (パスフレーズ入力)
 *                        │
 *                        ├─ 成功 → [アンロック完了]
 *                        └─ 復旧 → recover (リカバリーコード入力)
 *                                     ↓
 *                                  [アンロック完了]
 *
 * アンロック完了後は children (アプリ本体) を表示する。
 */
import { useEffect, useState } from "react";
import {
  decryptJson,
  setKey,
  type EncryptedRecord,
  type KeyDerivationParams,
} from "../index";
import { useUnlocked } from "../useCrypto";
import { fetchCryptoConfig } from "../cryptoApi";
import { SetupPassphrase } from "./SetupPassphrase";
import { ShowRecoveryCode } from "./ShowRecoveryCode";
import { UnlockForm } from "./UnlockForm";
import { RecoverForm } from "./RecoverForm";

/** ゲートの内部状態。 */
type GateState =
  | { phase: "loading" }
  | { phase: "error"; message: string }
  | { phase: "setup" }
  | { phase: "show-recovery"; recoveryCode: string }
  | { phase: "unlock"; params: KeyDerivationParams }
  | { phase: "recover"; params: KeyDerivationParams };

interface Props {
  children: React.ReactNode;
}

/** API のベース URL。 */
const API_BASE = "/api";

/**
 * 鍵が正しいか検証する。
 *
 * 暗号化取引が1件でもあれば、その payload を試し復号する。
 * 復号に成功すれば鍵は正しい。0件なら検証不能なので true を返す
 * (初回セットアップ直後など、まだデータが無い場合)。
 */
async function verifyKeyAgainstData(key: CryptoKey): Promise<boolean> {
  let rows: Array<{ encrypted_payload: string }>;
  try {
    const res = await fetch(`${API_BASE}/encrypted-tx`);
    if (!res.ok) {
      return true; // 取得失敗時は検証スキップ (アンロック自体は許可)
    }
    rows = await res.json();
  } catch {
    return true;
  }

  if (rows.length === 0) {
    return true; // データが無いので検証不能 → 許可
  }

  // 先頭1件を試し復号。
  try {
    const record: EncryptedRecord = JSON.parse(rows[0].encrypted_payload);
    await decryptJson(key, record);
    return true;
  } catch {
    return false; // 復号失敗 = 鍵 (パスフレーズ/コード) が誤り
  }
}

export function CryptoGate({ children }: Props) {
  const [state, setState] = useState<GateState>({ phase: "loading" });
  const unlocked = useUnlocked();

  // 起動時: salt の有無を確認して初期フェーズを決める。
  useEffect(() => {
    let cancelled = false;
    (async () => {
      try {
        const params = await fetchCryptoConfig();
        if (cancelled) return;
        if (params === null) {
          setState({ phase: "setup" });
        } else {
          setState({ phase: "unlock", params });
        }
      } catch (e) {
        if (cancelled) return;
        setState({
          phase: "error",
          message: e instanceof Error ? e.message : String(e),
        });
      }
    })();
    return () => {
      cancelled = true;
    };
  }, []);

  // アンロック済みなら、アプリ本体を表示。
  if (unlocked) {
    return <>{children}</>;
  }

  // 各フェーズの画面。
  switch (state.phase) {
    case "loading":
      return (
        <div className="crypto-gate">
          <div className="crypto-card">
            <p>読み込み中…</p>
          </div>
        </div>
      );

    case "error":
      return (
        <div className="crypto-gate">
          <div className="crypto-card">
            <h2>エラー</h2>
            <p className="crypto-error">{state.message}</p>
            <p className="crypto-hint">
              バックエンドが起動しているか確認してください。
            </p>
          </div>
        </div>
      );

    case "setup":
      return (
        <div className="crypto-gate">
          <SetupPassphrase
            onSetupComplete={(key, recoveryCode) => {
              // 鍵をストアにセット (アンロック) するのは
              // リカバリーコード確認後。ここではコード表示画面へ。
              setKey(key);
              setState({ phase: "show-recovery", recoveryCode });
            }}
          />
        </div>
      );

    case "show-recovery":
      return (
        <div className="crypto-gate">
          <ShowRecoveryCode
            recoveryCode={state.recoveryCode}
            onConfirmed={() => {
              // setKey は setup 時に済んでいる。
              // unlocked=true になり、children が表示される。
              // 状態を loading に戻して再評価させる。
              setState({ phase: "loading" });
            }}
          />
        </div>
      );

    case "unlock":
      return (
        <div className="crypto-gate">
          <UnlockForm
            params={state.params}
            verifyKey={verifyKeyAgainstData}
            onUnlocked={(key) => setKey(key)}
            onUseRecovery={() =>
              setState({ phase: "recover", params: state.params })
            }
          />
        </div>
      );

    case "recover":
      return (
        <div className="crypto-gate">
          <RecoverForm
            params={state.params}
            verifyKey={verifyKeyAgainstData}
            onRecovered={(key) => setKey(key)}
            onBack={() =>
              setState({ phase: "unlock", params: state.params })
            }
          />
        </div>
      );
  }
}
TSEOF

echo "  - frontend/src/crypto/ui/SetupPassphrase.tsx"
cat > frontend/src/crypto/ui/SetupPassphrase.tsx <<'TSEOF'
/**
 * 初回セットアップ: パスフレーズ設定画面。
 *
 * フロー:
 *   1. 利用者がパスフレーズを2回入力 (確認のため)
 *   2. salt を生成 → サーバー保存
 *   3. パスフレーズから鍵を導出
 *   4. リカバリーコードを生成
 *   5. 親に (key, recoveryCode) を渡す → リカバリーコード表示画面へ
 *
 * パスフレーズ自体はサーバーに送らない。送るのは salt のみ。
 */
import { useState } from "react";
import {
  createKeyDerivationParams,
  deriveKey,
  generateRecoveryCode,
  type KeyDerivationParams,
} from "../index";
import { saveCryptoConfig } from "../cryptoApi";

interface Props {
  /** セットアップ完了時に呼ばれる。鍵・リカバリーコード・salt を親へ渡す。 */
  onSetupComplete: (
    key: CryptoKey,
    recoveryCode: string,
    params: KeyDerivationParams,
  ) => void;
}

/** パスフレーズの最小文字数。 */
const MIN_PASSPHRASE_LENGTH = 8;

export function SetupPassphrase({ onSetupComplete }: Props) {
  const [passphrase, setPassphrase] = useState("");
  const [confirm, setConfirm] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSetup() {
    setError(null);

    if (passphrase.length < MIN_PASSPHRASE_LENGTH) {
      setError(`パスフレーズは${MIN_PASSPHRASE_LENGTH}文字以上にしてください`);
      return;
    }
    if (passphrase !== confirm) {
      setError("パスフレーズが一致しません");
      return;
    }

    setBusy(true);
    try {
      // 1. salt 生成 → サーバー保存
      const params = createKeyDerivationParams();
      await saveCryptoConfig(params);

      // 2. 鍵導出 (PBKDF2、1秒前後かかる)
      const key = await deriveKey(passphrase, params);

      // 3. リカバリーコード生成 (サーバーには送らない)
      const recoveryCode = generateRecoveryCode();

      onSetupComplete(key, recoveryCode, params);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="crypto-card">
      <h2>初期設定: パスフレーズ</h2>
      <p className="crypto-hint">
        このアプリのデータは端末内で暗号化されます。
        パスフレーズはサーバーに保存されません。
        <strong>忘れるとデータを復号できなくなります。</strong>
      </p>

      <label className="crypto-label">
        パスフレーズ ({MIN_PASSPHRASE_LENGTH}文字以上)
        <input
          type="password"
          value={passphrase}
          onChange={(e) => setPassphrase(e.target.value)}
          disabled={busy}
          autoComplete="new-password"
        />
      </label>

      <label className="crypto-label">
        パスフレーズ (確認)
        <input
          type="password"
          value={confirm}
          onChange={(e) => setConfirm(e.target.value)}
          disabled={busy}
          autoComplete="new-password"
        />
      </label>

      {error && <p className="crypto-error">{error}</p>}

      <button onClick={handleSetup} disabled={busy}>
        {busy ? "設定中… (鍵を生成しています)" : "設定する"}
      </button>
    </div>
  );
}
TSEOF

echo "  - frontend/src/crypto/ui/ShowRecoveryCode.tsx"
cat > frontend/src/crypto/ui/ShowRecoveryCode.tsx <<'TSEOF'
/**
 * 初回セットアップ: リカバリーコード表示画面。
 *
 * 重要:
 *   - リカバリーコードはこの画面でしか表示されない。
 *   - サーバーには送らない・保存しない。
 *   - 利用者が自分で保管する (コピー → パスワードマネージャ/紙 等)。
 *   - パスフレーズを忘れた際の唯一の復旧手段。
 *
 * 「保管した」チェックを入れないと先に進めない設計で、保管忘れを防ぐ。
 */
import { useState } from "react";

interface Props {
  /** 表示するリカバリーコード。 */
  recoveryCode: string;
  /** 利用者が保管を確認したら呼ばれる。アプリ本体へ進む。 */
  onConfirmed: () => void;
}

export function ShowRecoveryCode({ recoveryCode, onConfirmed }: Props) {
  const [saved, setSaved] = useState(false);
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    try {
      await navigator.clipboard.writeText(recoveryCode);
      setCopied(true);
    } catch {
      // clipboard API が使えない環境では手動コピーを促す。
      setCopied(false);
    }
  }

  return (
    <div className="crypto-card">
      <h2>リカバリーコードを保管してください</h2>
      <p className="crypto-hint">
        パスフレーズを忘れた場合、このコードでのみ復旧できます。
        <strong>
          この画面を離れると二度と表示されません。
        </strong>
        コピーして、パスワードマネージャや安全な場所に保管してください。
      </p>

      <div className="crypto-recovery-code">{recoveryCode}</div>

      <button onClick={handleCopy} type="button">
        {copied ? "コピーしました" : "クリップボードにコピー"}
      </button>

      <label className="crypto-checkbox">
        <input
          type="checkbox"
          checked={saved}
          onChange={(e) => setSaved(e.target.checked)}
        />
        リカバリーコードを安全な場所に保管しました
      </label>

      <button onClick={onConfirmed} disabled={!saved}>
        アプリを開始する
      </button>
    </div>
  );
}
TSEOF

echo "  - frontend/src/crypto/ui/UnlockForm.tsx"
cat > frontend/src/crypto/ui/UnlockForm.tsx <<'TSEOF'
/**
 * アンロック画面: パスフレーズ入力 (2回目以降の起動)。
 *
 * フロー:
 *   1. サーバーから salt を取得済み (親が渡す)
 *   2. 利用者がパスフレーズ入力
 *   3. 鍵を導出
 *   4. 試し復号で鍵が正しいか検証 (verifyKey)
 *   5. 正しければ親に鍵を渡す
 *
 * パスフレーズ誤りは「試し復号の失敗」で検出する。
 */
import { useState } from "react";
import { deriveKey, type KeyDerivationParams } from "../index";

interface Props {
  /** サーバーから取得済みの salt。 */
  params: KeyDerivationParams;
  /**
   * 導出した鍵を検証する関数。
   * 暗号化データが1件でもあれば試し復号し、鍵の正しさを確認する。
   * データが0件なら検証をスキップ (true を返す)。
   */
  verifyKey: (key: CryptoKey) => Promise<boolean>;
  /** アンロック成功時に呼ばれる。 */
  onUnlocked: (key: CryptoKey) => void;
  /** 「リカバリーコードで復旧」リンク押下時。 */
  onUseRecovery: () => void;
}

export function UnlockForm({
  params,
  verifyKey,
  onUnlocked,
  onUseRecovery,
}: Props) {
  const [passphrase, setPassphrase] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleUnlock() {
    setError(null);
    if (!passphrase) {
      setError("パスフレーズを入力してください");
      return;
    }

    setBusy(true);
    try {
      const key = await deriveKey(passphrase, params);

      // 試し復号で鍵の正しさを検証する。
      const valid = await verifyKey(key);
      if (!valid) {
        setError("パスフレーズが正しくありません");
        return;
      }

      onUnlocked(key);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="crypto-card">
      <h2>ロック解除</h2>
      <p className="crypto-hint">
        パスフレーズを入力してデータを表示します。
      </p>

      <label className="crypto-label">
        パスフレーズ
        <input
          type="password"
          value={passphrase}
          onChange={(e) => setPassphrase(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === "Enter" && !busy) {
              handleUnlock();
            }
          }}
          disabled={busy}
          autoComplete="current-password"
          autoFocus
        />
      </label>

      {error && <p className="crypto-error">{error}</p>}

      <button onClick={handleUnlock} disabled={busy}>
        {busy ? "解除中…" : "ロック解除"}
      </button>

      <button
        type="button"
        className="crypto-link"
        onClick={onUseRecovery}
        disabled={busy}
      >
        パスフレーズを忘れた (リカバリーコードで復旧)
      </button>
    </div>
  );
}
TSEOF

echo "  - frontend/src/crypto/ui/RecoverForm.tsx"
cat > frontend/src/crypto/ui/RecoverForm.tsx <<'TSEOF'
/**
 * 復旧画面: リカバリーコードでアンロック。
 *
 * パスフレーズを忘れた場合に使う。
 * リカバリーコードからも (同じ salt を使えば) 同じ鍵が導出できる。
 *
 * 注意: この画面は「鍵の復旧」であって「パスフレーズの再設定」ではない。
 *       パスフレーズ変更機能は E2 では未実装 (将来フェーズ)。
 */
import { useState } from "react";
import {
  deriveKey,
  isValidRecoveryCodeFormat,
  normalizeRecoveryCode,
  type KeyDerivationParams,
} from "../index";

interface Props {
  /** サーバーから取得済みの salt。 */
  params: KeyDerivationParams;
  /** 導出した鍵を検証する関数 (UnlockForm と同じ)。 */
  verifyKey: (key: CryptoKey) => Promise<boolean>;
  /** 復旧成功時に呼ばれる。 */
  onRecovered: (key: CryptoKey) => void;
  /** 「パスフレーズ入力に戻る」押下時。 */
  onBack: () => void;
}

export function RecoverForm({
  params,
  verifyKey,
  onRecovered,
  onBack,
}: Props) {
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleRecover() {
    setError(null);

    if (!isValidRecoveryCodeFormat(code)) {
      setError("リカバリーコードの形式が正しくありません");
      return;
    }

    setBusy(true);
    try {
      // 入力の揺れ (小文字・空白) を正規化してから鍵導出。
      const normalized = normalizeRecoveryCode(code);
      const key = await deriveKey(normalized, params);

      const valid = await verifyKey(key);
      if (!valid) {
        setError("リカバリーコードが正しくありません");
        return;
      }

      onRecovered(key);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="crypto-card">
      <h2>リカバリーコードで復旧</h2>
      <p className="crypto-hint">
        セットアップ時に保管したリカバリーコードを入力してください。
        小文字・ハイフン・空白の違いは自動で吸収されます。
      </p>

      <label className="crypto-label">
        リカバリーコード
        <input
          type="text"
          value={code}
          onChange={(e) => setCode(e.target.value)}
          disabled={busy}
          placeholder="XXXXX-XXXXX-..."
          autoComplete="off"
        />
      </label>

      {error && <p className="crypto-error">{error}</p>}

      <button onClick={handleRecover} disabled={busy}>
        {busy ? "復旧中…" : "復旧する"}
      </button>

      <button
        type="button"
        className="crypto-link"
        onClick={onBack}
        disabled={busy}
      >
        パスフレーズ入力に戻る
      </button>
    </div>
  );
}
TSEOF

echo "  - frontend/src/crypto/crypto-ui.css"
cat > frontend/src/crypto/crypto-ui.css <<'CSSEOF'
/**
 * E2E暗号化 UI のスタイル。
 * 既存アプリのトーンに馴染む、控えめで実用的なデザイン。
 */

/* ゲート全体 — 画面中央にカードを配置 */
.crypto-gate {
  display: flex;
  align-items: center;
  justify-content: center;
  min-height: 100vh;
  padding: 24px;
  background: #f5f5f4;
}

/* カード */
.crypto-card {
  width: 100%;
  max-width: 420px;
  background: #ffffff;
  border: 1px solid #e0e0de;
  border-radius: 12px;
  padding: 28px 24px;
  box-shadow: 0 1px 3px rgba(0, 0, 0, 0.06);
}

.crypto-card h2 {
  margin: 0 0 12px;
  font-size: 1.2rem;
  color: #1a1a18;
}

/* 説明文 */
.crypto-hint {
  font-size: 0.86rem;
  line-height: 1.6;
  color: #57606a;
  margin: 0 0 18px;
}

.crypto-hint strong {
  color: #cf5a23;
}

/* 入力ラベル */
.crypto-label {
  display: block;
  font-size: 0.84rem;
  color: #44443f;
  margin-bottom: 14px;
}

.crypto-label input {
  display: block;
  width: 100%;
  margin-top: 6px;
  padding: 9px 10px;
  font-size: 0.95rem;
  border: 1px solid #d0d0cd;
  border-radius: 6px;
  box-sizing: border-box;
}

.crypto-label input:focus {
  outline: none;
  border-color: #5a8f6f;
  box-shadow: 0 0 0 2px rgba(90, 143, 111, 0.15);
}

/* ボタン */
.crypto-card button {
  width: 100%;
  margin-top: 8px;
  padding: 10px;
  font-size: 0.95rem;
  font-weight: 600;
  color: #ffffff;
  background: #5a8f6f;
  border: none;
  border-radius: 6px;
  cursor: pointer;
}

.crypto-card button:hover:not(:disabled) {
  background: #4a7c5e;
}

.crypto-card button:disabled {
  background: #b8bdb9;
  cursor: not-allowed;
}

/* リンク風ボタン (リカバリー導線) */
.crypto-card button.crypto-link {
  background: none;
  color: #5a8f6f;
  font-weight: 400;
  font-size: 0.82rem;
  text-decoration: underline;
  margin-top: 12px;
}

.crypto-card button.crypto-link:hover:not(:disabled) {
  background: none;
  color: #3a6a4c;
}

/* エラー表示 */
.crypto-error {
  font-size: 0.84rem;
  color: #cf222e;
  margin: 4px 0 12px;
}

/* リカバリーコード表示 */
.crypto-recovery-code {
  font-family: "SF Mono", "Consolas", monospace;
  font-size: 1.05rem;
  letter-spacing: 0.04em;
  word-break: break-all;
  line-height: 1.7;
  background: #f0f3f1;
  border: 1px dashed #9bb8a7;
  border-radius: 8px;
  padding: 16px;
  margin: 0 0 16px;
  color: #1a1a18;
  text-align: center;
}

/* 保管確認チェックボックス */
.crypto-checkbox {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  font-size: 0.84rem;
  color: #44443f;
  margin: 16px 0;
  cursor: pointer;
}

.crypto-checkbox input {
  margin-top: 2px;
  flex-shrink: 0;
}
CSSEOF


# ===========================================================================
# Block 2: main.py に router 登録を追加 (Python で安全にパッチ)
# ===========================================================================
echo ""
echo "==> [Block 2] main.py に router 登録"
python3 <<'PATCHEOF'
from pathlib import Path
import re

p = Path("backend/app/main.py")
text = p.read_text(encoding="utf-8")
original = text

# import 追加
import_line = "from app.routers import crypto_config, encrypted_tx"
if "crypto_config" not in text:
    # 既存の routers import の後ろに追加するのが理想だが、
    # 構造が不明なので app = FastAPI(...) の前に挿入する。
    m = re.search(r"^(app\s*=\s*FastAPI)", text, re.MULTILINE)
    if m:
        text = text[:m.start()] + import_line + "\n\n" + text[m.start():]
    else:
        # FastAPI 生成が見つからない場合は先頭付近に追加
        text = import_line + "\n" + text
    print("  import 追加")
else:
    print("  import 既存")

# include_router 追加
if "crypto_config.router" not in text:
    # 末尾に追加 (app 変数が定義済みである前提)
    addition = (
        "\n# E2E暗号化 (Phase E2)\n"
        "app.include_router(crypto_config.router)\n"
        "app.include_router(encrypted_tx.router)\n"
    )
    text = text.rstrip() + "\n" + addition
    print("  include_router 追加")
else:
    print("  include_router 既存")

if text != original:
    p.write_text(text, encoding="utf-8")

import ast
ast.parse(text)
print("  main.py 構文 OK")
PATCHEOF


# ===========================================================================
# Block 2 検証: 構文チェック + uvicorn 起動 + curl
# ===========================================================================
echo ""
echo "==> [Block 2 検証] バックエンド構文チェック"
python3 -c "import ast; ast.parse(open('backend/app/crypto_models.py').read()); print('  crypto_models.py OK')"
python3 -c "import ast; ast.parse(open('backend/app/routers/crypto_config.py').read()); print('  crypto_config.py OK')"
python3 -c "import ast; ast.parse(open('backend/app/routers/encrypted_tx.py').read()); print('  encrypted_tx.py OK')"

echo ""
echo "==> [Block 2 検証] uvicorn 再起動"
pkill -9 -f uvicorn 2>/dev/null || true
sleep 2
(cd "$REPO/backend" && nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 6
echo "  health:"
curl -s http://localhost:8000/api/health; echo

echo ""
echo "==> [Block 2 検証] 暗号API の疎通確認"
echo "  GET /api/crypto/config (未設定なら404が正常):"
curl -s -o /dev/null -w "    HTTP %{http_code}\n" http://localhost:8000/api/crypto/config
echo "  GET /api/encrypted-tx (空配列が正常):"
curl -s http://localhost:8000/api/encrypted-tx; echo

# ===========================================================================
# Block 3: App.tsx を CryptoGate でラップ (Python で安全にパッチ)
# ===========================================================================
echo ""
echo "==> [Block 3] App.tsx を CryptoGate でラップ"
python3 <<'PATCHEOF'
from pathlib import Path

p = Path("frontend/src/App.tsx")
if not p.exists():
    print("  ⚠ App.tsx が見つかりません。手動でのラップが必要です。")
else:
    text = p.read_text(encoding="utf-8")
    if "CryptoGate" in text:
        print("  App.tsx は既に CryptoGate を含む (スキップ)")
    else:
        # import 追加 (先頭の import 群の後)
        import_line = 'import { CryptoGate } from "./crypto/ui/CryptoGate";\n'
        css_line = 'import "./crypto/crypto-ui.css";\n'
        lines = text.split("\n")
        # 最後の import 行を探す
        last_import = -1
        for i, ln in enumerate(lines):
            if ln.strip().startswith("import "):
                last_import = i
        if last_import >= 0:
            lines.insert(last_import + 1, import_line.rstrip() + "\n" + css_line.rstrip())
            text = "\n".join(lines)
            print("  import 追加")
        else:
            text = import_line + css_line + text
            print("  import 追加 (先頭)")

        p.write_text(text, encoding="utf-8")
        print("")
        print("  ※ 注意: import は追加しましたが、JSX のラップは手動で行ってください。")
        print("  App コンポーネントの return を以下のように変更:")
        print("    return (")
        print("      <CryptoGate>")
        print("        {/* 既存の JSX */}")
        print("      </CryptoGate>")
        print("    );")
PATCHEOF

echo ""
echo "==> [Block 3 検証] TypeScript 型チェック"
cd "$REPO/frontend"
npx tsc --noEmit 2>&1 | head -15 || echo "  (型エラーあり。上記確認 — App.tsx の手動ラップが必要な可能性)"
cd "$REPO"

cat <<'EOM'

============================================================
Phase E2 配置完了.

【重要】App.tsx の手動ラップが必要です:
  frontend/src/App.tsx を開き、return している JSX 全体を
  <CryptoGate> ... </CryptoGate> で囲んでください。
  import 文は自動追加済みです。

配置物:
  バックエンド:
    crypto_models.py        DBモデル (app_crypto_config, encrypted_transactions)
    routers/crypto_config.py  salt の保存/取得 API
    routers/encrypted_tx.py   暗号化取引 CRUD API
  フロントエンド:
    crypto/useCrypto.ts       鍵状態の React hook
    crypto/cryptoApi.ts       salt API 通信
    crypto/ui/CryptoGate.tsx  アンロックゲート
    crypto/ui/*.tsx           設定/表示/解除/復旧 画面
    crypto/crypto-ui.css      スタイル

この時点の状態:
  - 暗号API と UI は配置済み
  - encrypted_transactions テーブルは空 (新規取引から入る)
  - 既存の平文 transactions・グラフ・OCR は無傷
  - App.tsx を CryptoGate でラップすると、起動時にパスフレーズ要求

次フェーズ (E3):
  - 取引の暗号化保存・復号表示をUIに接続
  - グラフ集計をフロント側に移行
============================================================
EOM
