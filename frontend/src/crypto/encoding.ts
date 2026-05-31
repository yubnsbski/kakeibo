/**
 * バイト列と base64 文字列の相互変換ユーティリティ。
 *
 * 暗号データ (鍵・IV・暗号文) は ArrayBuffer/Uint8Array で扱うが、
 * JSON や DB に載せるには文字列化が必要なため base64 を用いる。
 *
 * このモジュールは副作用を持たない純粋関数のみで構成する。
 */

/** Uint8Array を base64 文字列に変換する。 */
export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return btoa(binary);
}

/** base64 文字列を Uint8Array に変換する。 */
export function base64ToBytes(base64: string): Uint8Array {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/** UTF-8 文字列を Uint8Array に変換する。 */
export function utf8ToBytes(text: string): Uint8Array {
  return new TextEncoder().encode(text);
}

/** Uint8Array を UTF-8 文字列に変換する。 */
export function bytesToUtf8(bytes: Uint8Array): string {
  return new TextDecoder().decode(bytes);
}

/** 暗号学的に安全な乱数バイト列を生成する。 */
export function randomBytes(length: number): Uint8Array {
  const bytes = new Uint8Array(length);
  crypto.getRandomValues(bytes);
  return bytes;
}

export function toArrayBuffer(bytes: Uint8Array): ArrayBuffer {
  return bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
}
