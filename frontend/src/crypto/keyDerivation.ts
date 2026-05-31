/**
 * 鍵導出 (Key Derivation)。
 *
 * パスフレーズまたはリカバリーコードから、PBKDF2 で AES-GCM 用の鍵を導出する。
 *
 * 設計方針:
 *  - パスフレーズとリカバリーコードは「同じ salt」から「同じ鍵」を導出する。
 *    これにより、どちらを使っても同じデータを復号できる。
 *  - salt はアカウントごとに1つ。サーバーに保存してよい (秘密ではない)。
 *  - 導出した CryptoKey は extractable=false とし、鍵そのものを取り出せなくする。
 */

import {
  AES_KEY_LENGTH,
  PBKDF2_ITERATIONS,
  SALT_LENGTH,
  type KeyDerivationParams,
} from "./types";
import { base64ToBytes, bytesToBase64, randomBytes, utf8ToBytes,
  toArrayBuffer,
} from "./encoding";

/**
 * 新しい鍵導出パラメータ (salt) を生成する。
 * アカウント初回セットアップ時に1回だけ呼ぶ。
 */
export function createKeyDerivationParams(): KeyDerivationParams {
  return {
    salt: bytesToBase64(randomBytes(SALT_LENGTH)),
    iterations: PBKDF2_ITERATIONS,
  };
}

/**
 * 秘密文字列 (パスフレーズ または リカバリーコード) から AES-GCM 鍵を導出する。
 *
 * @param secret - パスフレーズ または リカバリーコード
 * @param params - salt と反復回数 (createKeyDerivationParams で生成したもの)
 * @returns AES-GCM 256bit 鍵 (extractable=false)
 */
export async function deriveKey(
  secret: string,
  params: KeyDerivationParams,
): Promise<CryptoKey> {
  if (!secret) {
    throw new Error("deriveKey: secret が空です");
  }

  // 1. 秘密文字列を PBKDF2 の入力鍵素材としてインポート
  const baseKey = await crypto.subtle.importKey(
    "raw",
    toArrayBuffer(utf8ToBytes(secret)),
    "PBKDF2",
    false,
    ["deriveKey"],
  );

  // 2. PBKDF2 で AES-GCM 鍵を導出
  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt: toArrayBuffer(base64ToBytes(params.salt)),
      iterations: params.iterations,
      hash: "SHA-256",
    },
    baseKey,
    { name: "AES-GCM", length: AES_KEY_LENGTH },
    false, // extractable=false: 鍵バイト列を取り出せなくする
    ["encrypt", "decrypt"],
  );
}
