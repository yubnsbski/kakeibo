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
