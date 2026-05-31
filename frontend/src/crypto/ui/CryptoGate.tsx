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
 *
 * ── 鍵検証の方針 (セキュリティレビューによる修正) ──
 * 鍵検証はフェイルセーフ。検証できない時はアンロックを「許可しない」。
 * 旧実装は取得失敗時に true を返し、誤パスフレーズでもアンロックが
 * 通る穴があった。その状態で取引を保存すると、既存データと異なる鍵で
 * 暗号化されたデータが混入し (データ分裂)、復旧困難になる。
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

/** 鍵検証で試し復号する最大件数 (データ分裂の検知も兼ねる)。 */
const VERIFY_SAMPLE_SIZE = 5;

/** 鍵検証の結果。 */
export type KeyVerifyResult =
  | { kind: "ok" } // 全サンプル復号成功、または検証対象なし
  | { kind: "wrong_key" } // 全サンプル復号失敗 = 鍵が誤り
  | { kind: "partial"; ok: number; total: number } // 一部のみ成功 = データ分裂の疑い
  | { kind: "unavailable" }; // サーバーに接続できず検証不能

/**
 * 鍵が正しいかを、暗号化取引の試し復号で検証する。
 *
 * フェイルセーフ設計:
 *  - サーバーに繋がらない → "unavailable" (アンロックは拒否)
 *  - 暗号化取引が0件 → "ok" (検証対象が無いだけ。初回セットアップ直後など)
 *  - サンプルを試し復号し、全成功 → "ok" / 全失敗 → "wrong_key"
 *  - 一部だけ成功 → "partial" (異なる鍵で保存されたデータの混在を疑う)
 */
async function verifyKeyAgainstData(
  key: CryptoKey,
): Promise<KeyVerifyResult> {
  let rows: Array<{ encrypted_payload: string }>;
  try {
    const res = await fetch(`${API_BASE}/encrypted-tx`);
    if (!res.ok) {
      // 取得失敗。検証できない以上、アンロックを許可してはいけない。
      return { kind: "unavailable" };
    }
    rows = await res.json();
  } catch {
    return { kind: "unavailable" };
  }

  if (!Array.isArray(rows) || rows.length === 0) {
    // 検証対象が無い。初回セットアップ直後など。鍵の正否は判定不能だが、
    // データが無いので誤鍵で保存しても分裂は起きない。アンロック許可。
    return { kind: "ok" };
  }

  // 先頭 VERIFY_SAMPLE_SIZE 件を試し復号する。
  const sample = rows.slice(0, VERIFY_SAMPLE_SIZE);
  let success = 0;
  for (const row of sample) {
    try {
      const record: EncryptedRecord = JSON.parse(row.encrypted_payload);
      await decryptJson(key, record);
      success += 1;
    } catch {
      // この1件は復号できなかった。
    }
  }

  if (success === 0) {
    return { kind: "wrong_key" };
  }
  if (success === sample.length) {
    return { kind: "ok" };
  }
  // 一部だけ成功 = サンプル内に異なる鍵のデータが混在している。
  return { kind: "partial", ok: success, total: sample.length };
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
