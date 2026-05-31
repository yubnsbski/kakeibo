/**
 * E2E暗号化の型定義.
 *
 * 設計方針:
 *  - 平文の型と暗号文の型を厳密に分離し、復号し忘れをコンパイル時に検出する。
 *  - 暗号文は base64 文字列としてやり取りする (JSON/DB に安全に載るため)。
 */

/**
 * 暗号化された1レコード。
 * サーバーにはこの形でしか保存しない。
 */
export interface EncryptedRecord {
  /** payload スキーマのバージョン。将来の移行用。 */
  payloadVersion: number;
  /** AES-GCM の初期化ベクトル (base64, 12バイト)。 */
  iv: string;
  /** 暗号文本体 (base64)。AES-GCM の認証タグを含む。 */
  ciphertext: string;
}

/**
 * 鍵導出に使うパラメータ。
 * salt はレコードと一緒に保存し、復号時に同じ値を使う。
 */
export interface KeyDerivationParams {
  /** PBKDF2 のソルト (base64, 16バイト)。 */
  salt: string;
  /** PBKDF2 の反復回数。 */
  iterations: number;
}

/** 現在の payload スキーマバージョン。 */
export const CURRENT_PAYLOAD_VERSION = 1;

/** PBKDF2 反復回数 (OWASP 2023 推奨: SHA-256 で 600,000)。 */
export const PBKDF2_ITERATIONS = 600_000;

/** AES-GCM の鍵長 (ビット)。 */
export const AES_KEY_LENGTH = 256;

/** IV の長さ (バイト)。AES-GCM の推奨は 12。 */
export const IV_LENGTH = 12;

/** ソルトの長さ (バイト)。 */
export const SALT_LENGTH = 16;
