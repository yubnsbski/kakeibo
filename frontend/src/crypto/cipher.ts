/**
 * AES-GCM による暗号化・復号。
 *
 * 設計方針:
 *  - AES-GCM は「認証付き暗号」。改ざんされた暗号文は復号時にエラーになる。
 *  - IV (初期化ベクトル) は暗号化のたびに新規生成する。使い回し厳禁。
 *  - 入出力は EncryptedRecord (base64 文字列) とし、JSON/DB に安全に載せられる。
 *  - JSON オブジェクトの暗号化を主用途とする (encryptJson / decryptJson)。
 */

import {
  CURRENT_PAYLOAD_VERSION,
  IV_LENGTH,
  type EncryptedRecord,
} from "./types";
import {
  base64ToBytes,
  bytesToBase64,
  bytesToUtf8,
  randomBytes,
  utf8ToBytes,
  toArrayBuffer,
} from "./encoding";

/**
 * 文字列を暗号化する。
 *
 * @param key - deriveKey で導出した AES-GCM 鍵
 * @param plaintext - 平文文字列
 * @returns 暗号化レコード (サーバーに保存可能)
 */
export async function encryptString(
  key: CryptoKey,
  plaintext: string,
): Promise<EncryptedRecord> {
  const iv = randomBytes(IV_LENGTH);
  const ciphertext = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv: toArrayBuffer(iv) },
    key,
    toArrayBuffer(utf8ToBytes(plaintext)),
  );
  return {
    payloadVersion: CURRENT_PAYLOAD_VERSION,
    iv: bytesToBase64(iv),
    ciphertext: bytesToBase64(new Uint8Array(ciphertext)),
  };
}

/**
 * 暗号化レコードを復号して文字列を得る。
 *
 * @throws 鍵が誤っている / データが改ざんされている場合は例外
 */
export async function decryptString(
  key: CryptoKey,
  record: EncryptedRecord,
): Promise<string> {
  let plaintextBuffer: ArrayBuffer;
  try {
    plaintextBuffer = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: toArrayBuffer(base64ToBytes(record.iv)) },
      key,
      toArrayBuffer(base64ToBytes(record.ciphertext)),
    );
  } catch {
    // AES-GCM は鍵違い・改ざんを区別せず例外を投げる。
    // 利用者向けには「パスフレーズが違うかデータが壊れている」と扱う。
    throw new Error("復号に失敗しました (パスフレーズ誤り、またはデータ破損)");
  }
  return bytesToUtf8(new Uint8Array(plaintextBuffer));
}

/**
 * JSON オブジェクトを暗号化する。
 * アプリの主用途 (取引データ等の暗号化) はこちらを使う。
 */
export async function encryptJson(
  key: CryptoKey,
  data: unknown,
): Promise<EncryptedRecord> {
  return encryptString(key, JSON.stringify(data));
}

/**
 * 暗号化レコードを復号して JSON オブジェクトを得る。
 *
 * @typeParam T - 復号後の型 (呼び出し側が指定)
 */
export async function decryptJson<T = unknown>(
  key: CryptoKey,
  record: EncryptedRecord,
): Promise<T> {
  const text = await decryptString(key, record);
  return JSON.parse(text) as T;
}
