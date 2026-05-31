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
