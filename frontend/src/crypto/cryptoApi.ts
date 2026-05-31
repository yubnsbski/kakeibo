/**
 * 暗号関連の API 通信。
 *
 * salt の取得・保存のみ。パスフレーズ・鍵・リカバリーコードは
 * 一切 API に送らない (E2E を保つため)。
 */
import type { KeyDerivationParams } from "./index";

/** API のベース URL。既存 api.ts と同じ規約に合わせる。 */
const API_BASE = "/api";

/**
 * サーバーから鍵導出パラメータ (salt) を取得する。
 *
 * @returns salt が設定済みなら KeyDerivationParams、未設定 (初回) なら null
 */
export async function fetchCryptoConfig(): Promise<KeyDerivationParams | null> {
  const res = await fetch(`${API_BASE}/crypto/config`);
  if (res.status === 404) {
    return null; // 初回セットアップ前
  }
  if (!res.ok) {
    throw new Error(`crypto config 取得失敗: HTTP ${res.status}`);
  }
  const data = await res.json();
  return { salt: data.salt, iterations: data.iterations };
}

/**
 * 鍵導出パラメータ (salt) をサーバーに初回保存する。
 *
 * @throws 既に設定済み (409) の場合は例外
 */
export async function saveCryptoConfig(
  params: KeyDerivationParams,
): Promise<void> {
  const res = await fetch(`${API_BASE}/crypto/config`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      salt: params.salt,
      iterations: params.iterations,
    }),
  });
  if (!res.ok) {
    if (res.status === 409) {
      throw new Error("暗号設定は既に存在します (salt は上書きできません)");
    }
    throw new Error(`crypto config 保存失敗: HTTP ${res.status}`);
  }
}
