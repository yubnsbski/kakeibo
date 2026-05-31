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
