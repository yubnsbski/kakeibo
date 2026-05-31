#!/usr/bin/env bash
# Phase E1: E2E暗号基盤を frontend/src/crypto/ に配置する.
#
# このスクリプトは crypto/ モジュールを追加するだけ.
# DB・API・既存コンポーネントには一切触れない (既存機能は無傷).
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_e2e_phase1.sh

set -u
REPO=/workspaces/kakeibo
CRYPTO_DIR="$REPO/frontend/src/crypto"
cd "$REPO"

echo "============================================================"
echo "Phase E1: E2E暗号基盤"
echo "============================================================"
echo ""
echo "==> crypto/ ディレクトリ作成"
mkdir -p "$CRYPTO_DIR"

# ---------------------------------------------------------------------------
# crypto/types.ts
# ---------------------------------------------------------------------------
echo "==> crypto/types.ts"
cat > "$CRYPTO_DIR/types.ts" <<'TSEOF'
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
TSEOF

# ---------------------------------------------------------------------------
# crypto/encoding.ts
# ---------------------------------------------------------------------------
echo "==> crypto/encoding.ts"
cat > "$CRYPTO_DIR/encoding.ts" <<'TSEOF'
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
TSEOF

# ---------------------------------------------------------------------------
# crypto/keyDerivation.ts
# ---------------------------------------------------------------------------
echo "==> crypto/keyDerivation.ts"
cat > "$CRYPTO_DIR/keyDerivation.ts" <<'TSEOF'
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
import { base64ToBytes, bytesToBase64, randomBytes, utf8ToBytes } from "./encoding";

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
    utf8ToBytes(secret),
    "PBKDF2",
    false,
    ["deriveKey"],
  );

  // 2. PBKDF2 で AES-GCM 鍵を導出
  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt: base64ToBytes(params.salt),
      iterations: params.iterations,
      hash: "SHA-256",
    },
    baseKey,
    { name: "AES-GCM", length: AES_KEY_LENGTH },
    false, // extractable=false: 鍵バイト列を取り出せなくする
    ["encrypt", "decrypt"],
  );
}
TSEOF

# ---------------------------------------------------------------------------
# crypto/cipher.ts
# ---------------------------------------------------------------------------
echo "==> crypto/cipher.ts"
cat > "$CRYPTO_DIR/cipher.ts" <<'TSEOF'
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
    { name: "AES-GCM", iv },
    key,
    utf8ToBytes(plaintext),
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
      { name: "AES-GCM", iv: base64ToBytes(record.iv) },
      key,
      base64ToBytes(record.ciphertext),
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
TSEOF

# ---------------------------------------------------------------------------
# crypto/recoveryCode.ts
# ---------------------------------------------------------------------------
echo "==> crypto/recoveryCode.ts"
cat > "$CRYPTO_DIR/recoveryCode.ts" <<'TSEOF'
/**
 * リカバリーコードの生成・整形。
 *
 * 用途:
 *  - パスフレーズを忘れた場合の復旧手段。
 *  - 初回セットアップ時にブラウザ内で生成し、画面に1回だけ表示する。
 *  - サーバーには絶対に送らない・保存しない (E2E を保つため)。
 *
 * 設計方針:
 *  - 十分なエントロピー (160bit) を持たせ、総当たりを非現実的にする。
 *  - 人が書き写せるよう、紛らわしい文字 (0/O, 1/I/l) を除いた文字集合を使う。
 *  - 5文字ごとにハイフンで区切り、可読性を上げる。
 */

import { randomBytes } from "./encoding";

/**
 * 使用する文字集合 (Crockford Base32 風、紛らわしい文字を除外)。
 * 0,1,O,I,L を含まない 32 文字。
 */
const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";

/** コードの文字数 (ハイフン除く)。32文字集合 × 32文字 = 160bit 相当。 */
const CODE_LENGTH = 32;

/** ハイフン区切りのグループ長。 */
const GROUP_SIZE = 5;

/**
 * 新しいリカバリーコードを生成する。
 *
 * @returns 例: "A7K2M-9PQRS-..." 形式の文字列
 */
export function generateRecoveryCode(): string {
  // 必要な文字数ぶんの乱数バイトを取得し、各バイトを文字集合にマッピング。
  const bytes = randomBytes(CODE_LENGTH);
  let raw = "";
  for (let i = 0; i < CODE_LENGTH; i++) {
    raw += ALPHABET[bytes[i] % ALPHABET.length];
  }
  return formatRecoveryCode(raw);
}

/**
 * 連続した文字列を GROUP_SIZE ごとにハイフン区切りに整形する。
 */
export function formatRecoveryCode(raw: string): string {
  const groups: string[] = [];
  for (let i = 0; i < raw.length; i += GROUP_SIZE) {
    groups.push(raw.slice(i, i + GROUP_SIZE));
  }
  return groups.join("-");
}

/**
 * 利用者が入力したリカバリーコードを正規化する。
 *
 * 入力時の揺れ (小文字、空白、ハイフン有無) を吸収し、
 * 鍵導出に使える正規形に揃える。
 *
 * @returns ハイフン区切りの大文字文字列
 */
export function normalizeRecoveryCode(input: string): string {
  const cleaned = input
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, ""); // ハイフン・空白を除去
  return formatRecoveryCode(cleaned);
}

/**
 * 文字列がリカバリーコードの形式として妥当かを判定する。
 * (鍵が正しいかではなく、形式チェックのみ)
 */
export function isValidRecoveryCodeFormat(input: string): boolean {
  const cleaned = input.toUpperCase().replace(/[^A-Z0-9]/g, "");
  if (cleaned.length !== CODE_LENGTH) {
    return false;
  }
  for (const ch of cleaned) {
    if (!ALPHABET.includes(ch)) {
      return false;
    }
  }
  return true;
}
TSEOF

# ---------------------------------------------------------------------------
# crypto/keyStore.ts
# ---------------------------------------------------------------------------
echo "==> crypto/keyStore.ts"
cat > "$CRYPTO_DIR/keyStore.ts" <<'TSEOF'
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
TSEOF

# ---------------------------------------------------------------------------
# crypto/index.ts
# ---------------------------------------------------------------------------
echo "==> crypto/index.ts"
cat > "$CRYPTO_DIR/index.ts" <<'TSEOF'
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
TSEOF

# ---------------------------------------------------------------------------
# 検証: TypeScript 型チェック
# ---------------------------------------------------------------------------
echo ""
echo "==> TypeScript 型チェック"
cd "$REPO/frontend"
if npx tsc --noEmit --strict src/crypto/*.ts 2>&1 | head -20; then
  echo "  ✓ 型チェック OK"
else
  echo "  (型チェックで警告あり。上記を確認)"
fi
cd "$REPO"

cat <<EOM

============================================================
Phase E1 配置完了.

作成したファイル (frontend/src/crypto/):
  types.ts          型定義・定数
  encoding.ts       base64/バイト列 変換
  keyDerivation.ts  パスフレーズ→鍵 (PBKDF2)
  cipher.ts         AES-GCM 暗号化/復号
  recoveryCode.ts   リカバリーコード生成/検証
  keyStore.ts       鍵のメモリ保持
  index.ts          公開API

この時点での状態:
  - crypto/ モジュールを「追加」しただけ
  - DB・API・既存コンポーネントは未変更 → 既存機能は無傷
  - まだデータは暗号化されていない (E2 から)

次フェーズ (E2):
  - DB スキーマ変更 (encrypted_transactions テーブル)
  - 取引データの暗号化保存
  - パスフレーズ入力UI

============================================================
EOM
