/**
 * 復旧画面: リカバリーコードでアンロック。
 *
 * パスフレーズを忘れた場合に使う。
 * リカバリーコードからも (同じ salt を使えば) 同じ鍵が導出できる。
 *
 * 鍵検証は UnlockForm と同じフェイルセーフ方針:
 *   - 検証できない時 (サーバー未接続) はアンロックしない。
 *   - 鍵が全く通用しない時はアンロックしない。
 *   - 一部のみ復号できる時はアンロック許可 + 警告。
 */
import { useState } from "react";
import {
  deriveKey,
  isValidRecoveryCodeFormat,
  normalizeRecoveryCode,
  type KeyDerivationParams,
} from "../index";
import type { KeyVerifyResult } from "./CryptoGate";

interface Props {
  /** サーバーから取得済みの salt。 */
  params: KeyDerivationParams;
  /** 導出した鍵を検証する関数 (UnlockForm と同じ)。 */
  verifyKey: (key: CryptoKey) => Promise<KeyVerifyResult>;
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
  const [warning, setWarning] = useState<string | null>(null);

  async function handleRecover() {
    setError(null);
    setWarning(null);

    if (!isValidRecoveryCodeFormat(code)) {
      setError("リカバリーコードの形式が正しくありません");
      return;
    }

    setBusy(true);
    try {
      // 入力の揺れ (小文字・空白) を正規化してから鍵導出。
      const normalized = normalizeRecoveryCode(code);
      const key = await deriveKey(normalized, params);
      const result = await verifyKey(key);

      switch (result.kind) {
        case "ok":
          onRecovered(key);
          return;

        case "wrong_key":
          setError("リカバリーコードが正しくありません");
          return;

        case "unavailable":
          setError(
            "データを確認できないため復旧できません。" +
              "バックエンドが起動しているか確認してください。",
          );
          return;

        case "partial":
          setWarning(
            "データ分裂の疑い: 確認した" + result.total + "件のうち" +
              result.ok + "件しか復号できませんでした。" +
              "アンロック後、一覧で「復号失敗」の行がないか確認してください。",
          );
          onRecovered(key);
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
      {warning && (
        <p className="crypto-error" style={{ color: "#b06a00" }}>
          {warning}
        </p>
      )}

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
