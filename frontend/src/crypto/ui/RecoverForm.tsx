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
