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
