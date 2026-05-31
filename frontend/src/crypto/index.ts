/**
 * E2E暗号化モジュールの公開 API。
 *
 * アプリの他の部分は、必ずこの index 経由で暗号機能を使う。
 * 内部ファイル (cipher.ts 等) を直接 import しないこと。
 * これにより、暗号実装の変更影響を crypto/ フォルダ内に閉じ込める。
 *
 * ── 典型的な使い方 ──
 *
 * 初回セットアップ:
 *   const params = createKeyDerivationParams();   // salt 生成
 *   const recoveryCode = generateRecoveryCode();  // 復旧コード生成
 *   const key = await deriveKey(passphrase, params);
 *   setKey(key);
 *   // params はサーバー保存可。recoveryCode は画面表示のみ。
 *
 * 2回目以降のアンロック:
 *   const key = await deriveKey(passphrase, params);  // params はサーバーから取得
 *   setKey(key);
 *
 * データの暗号化/復号:
 *   const record = await encryptJson(requireKey(), { amount: 1200 });
 *   const data = await decryptJson(requireKey(), record);
 */

// ── 型・定数 ──
export type { EncryptedRecord, KeyDerivationParams } from "./types";
export { CURRENT_PAYLOAD_VERSION } from "./types";

// ── 鍵導出 ──
export { createKeyDerivationParams, deriveKey } from "./keyDerivation";

// ── 暗号化・復号 ──
export {
  encryptString,
  decryptString,
  encryptJson,
  decryptJson,
} from "./cipher";

// ── リカバリーコード ──
export {
  generateRecoveryCode,
  normalizeRecoveryCode,
  isValidRecoveryCodeFormat,
} from "./recoveryCode";

// ── 鍵ストア (メモリ保持) ──
export {
  setKey,
  getKey,
  requireKey,
  isUnlocked,
  clearKey,
  subscribeLockState,
} from "./keyStore";
