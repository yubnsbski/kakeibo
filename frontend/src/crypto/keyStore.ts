/**
 * 鍵ストア (メモリ保持版)。
 *
 * 設計方針:
 *  - 導出した CryptoKey をモジュールスコープ変数で保持する。
 *  - localStorage / sessionStorage には保存しない。
 *    → ページをリロードすると鍵は消え、パスフレーズ再入力が必要。
 *    → これは「最も安全」な選択 (端末を覗かれても鍵が残らない)。
 *  - アプリ全体で唯一のインスタンスとして振る舞う (シングルトン)。
 *
 * 将来 sessionStorage 版に切り替える場合も、この公開APIを保てば
 * 他コードへの影響を最小化できる。
 */

let currentKey: CryptoKey | null = null;

/** ロック状態の変化を購読するリスナー。 */
type LockListener = (unlocked: boolean) => void;
const listeners = new Set<LockListener>();

function notify(): void {
  const unlocked = currentKey !== null;
  for (const listener of listeners) {
    listener(unlocked);
  }
}

/**
 * 鍵をストアにセットする (アンロック)。
 * パスフレーズ/リカバリーコードでの認証成功時に呼ぶ。
 */
export function setKey(key: CryptoKey): void {
  currentKey = key;
  notify();
}

/**
 * 現在の鍵を取得する。未アンロックなら null。
 */
export function getKey(): CryptoKey | null {
  return currentKey;
}

/**
 * 現在の鍵を取得する。未アンロックなら例外。
 * 暗号化/復号の直前で使い、鍵が無い状態の操作を防ぐ。
 */
export function requireKey(): CryptoKey {
  if (currentKey === null) {
    throw new Error("ロックされています。先にパスフレーズを入力してください。");
  }
  return currentKey;
}

/** アンロック済みかどうか。 */
export function isUnlocked(): boolean {
  return currentKey !== null;
}

/**
 * 鍵を破棄する (ロック)。
 * ログアウト相当。メモリから鍵参照を消す。
 */
export function clearKey(): void {
  currentKey = null;
  notify();
}

/**
 * ロック状態の変化を購読する。
 * @returns 購読解除関数
 */
export function subscribeLockState(listener: LockListener): () => void {
  listeners.add(listener);
  return () => listeners.delete(listener);
}
