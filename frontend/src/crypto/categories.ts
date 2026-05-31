/**
 * 支出・収入カテゴリの定義。
 *
 * カテゴリは「何に使ったか」を表す。
 * 支払い手段は payment_method 側で扱い、
 * カテゴリには含めない。
 */

export const EXPENSE_CATEGORIES = [
  "食費",
  "日用品",
  "交通",
  "交際費",
  "娯楽",
  "医療",
  "通信",
  "住居",
  "水道光熱",
  "教育",
  "衣服",
  "その他",
  "未分類",
] as const;

export const INCOME_CATEGORIES = [
  "給与",
  "副業",
  "臨時収入",
  "返金",
  "その他収入",
] as const;

export type ExpenseCategory = (typeof EXPENSE_CATEGORIES)[number];
export type IncomeCategory = (typeof INCOME_CATEGORIES)[number];

export function categoryOptions(txType: "expense" | "income"): readonly string[] {
  return txType === "income" ? INCOME_CATEGORIES : EXPENSE_CATEGORIES;
}

export function normalizeCategory(category: string | null | undefined): string {
  if (!category) return "未分類";
  return category.trim() || "未分類";
}

/**
 * カテゴリ選択肢を返す。
 * 既存データに、現在の選択肢に無いカテゴリ（旧カテゴリなど）が
 * 入っている場合、その値を先頭に追加して選択可能にする。
 * これにより、編集時に既存値が消えるのを防ぐ。
 */
export function categoryOptionsWithCurrent(
  txType: "expense" | "income",
  current: string | null | undefined,
): string[] {
  const normalized = normalizeCategory(current);
  const base = [...categoryOptions(txType)];

  if (!base.includes(normalized)) {
    return [normalized, ...base];
  }

  return base;
}
