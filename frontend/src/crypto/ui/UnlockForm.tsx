/**
 * アンロック画面: パスフレーズ入力 (2回目以降の起動)。
 *
 * フロー:
 *   1. サーバーから salt を取得済み (親が渡す)
 *   2. 利用者がパスフレーズ入力
 *   3. 鍵を導出
 *   4. 試し復号で鍵が正しいか検証 (verifyKey)
 *   5. 検証結果に応じて分岐
 *
 * 鍵検証はフェイルセーフ:
 *   - 検証できない (サーバー未接続) 時はアンロックしない。
 *   - 鍵が全く通用しない時はアンロックしない。
 *   - 一部のデータのみ復号できる (データ分裂の疑い) 時は、
 *     アンロックは許可するが警告を出す。鍵自体は有効なため、
 *     ロックアウトするとユーザーが自分のデータにアクセスできなくなる。
 */
import { useState } from "react";
import { deriveKey, type KeyDerivationParams } from "../index";
import type { KeyVerifyResult } from "./CryptoGate";

interface Props {
  /** サーバーから取得済みの salt。 */
  params: KeyDerivationParams;
  /**
   * 導出した鍵を検証する関数。
   * 暗号化データの試し復号で、鍵の正しさとデータ整合性を確認する。
   */
  verifyKey: (key: CryptoKey) => Promise<KeyVerifyResult>;
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
  /** データ分裂の疑いを検知したときの警告 (アンロックは許可する)。 */
  const [warning, setWarning] = useState<string | null>(null);

  async function handleUnlock() {
    setError(null);
    setWarning(null);
    if (!passphrase) {
      setError("パスフレーズを入力してください");
      return;
    }

    setBusy(true);
    try {
      const key = await deriveKey(passphrase, params);
      const result = await verifyKey(key);

      switch (result.kind) {
        case "ok":
          onUnlocked(key);
          return;

        case "wrong_key":
          setError("パスフレーズが正しくありません");
          return;

        case "unavailable":
          // フェイルセーフ: 検証できない以上アンロックしない。
          // (旧実装はここで素通りし、誤鍵でもアンロックが通る穴があった)
          setError(
            "データを確認できないためロック解除できません。" +
              "バックエンドが起動しているか確認してください。",
          );
          return;

        case "partial":
          // 一部のデータのみ復号できた。鍵自体は (一部データに対し) 有効。
          // ロックアウトすると正規ユーザーが自分のデータにアクセスできなく
          // なるため、アンロックは許可する。ただし分裂を明示的に警告する。
          setWarning(
            "データ分裂の疑い: 確認した" + result.total + "件のうち" +
              result.ok + "件しか復号できませんでした。" +
              "過去に異なるパスフレーズで保存されたデータが" +
              "混在している可能性があります。" +
              "アンロック後、一覧で「復号失敗」と表示される行がないか確認してください。",
          );
          onUnlocked(key);
          return;
      }
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
      {warning && (
        <p className="crypto-error" style={{ color: "#b06a00" }}>
          {warning}
        </p>
      )}

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
