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
