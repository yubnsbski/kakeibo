import type { Category } from "./types";

export type SubCategory = string;
export type CategoryBudget = { category: Category; subCategory?: SubCategory; amount: number };

export type AllocationInput = {
  id: string;
  amount: number;
  category: Category | null;
  subCategory?: SubCategory;
  needsReview: boolean;
  merchantNormalized?: string;
  items?: string[];
  purchasedAt?: string;
};

export type AllocationRecord = {
  id: string;
  amount: number;
  categoryUsed: Category;
  subCategoryUsed: SubCategory;
  isProvisional: boolean;
  usedFallbackOther: boolean;
};

export type WalletState = {
  totalBalance: number;
  categoryBalances: Record<Category, number>;
  subCategoryBalances: Record<string, number>;
  allocations: AllocationRecord[];
};

export type WalletConfig = {
  totalBalance: number;
  categoryBudgets: CategoryBudget[];
};

export type CategoryOverride = { category: Category; subCategory?: string };

export type CsvBackup = {
  name: string;
  csv: string;
};

export type ScreeningCellRecord = {
  receipt_id: string;
  merchant_normalized: string;
  items_text: string;
  screening_category: Category | "REVIEW";
  needs_review: "yes" | "no";
  reason: string;
  confidence: number;
  amount: number;
  purchased_at: string;
};

const DEFAULT_CATEGORY: Category = "その他";
const DEFAULT_SUBCATEGORY = "未分類";
const CATEGORIES: Category[] = ["食費", "日用品", "交通", "医療", "通信", "娯楽", "教育", "その他"];

function subCategoryKey(category: Category, subCategory?: string): string {
  return `${category}:${subCategory ?? DEFAULT_SUBCATEGORY}`;
}

function resolveAllocationCategory(input: AllocationInput) {
  if (input.needsReview || input.category === null) {
    return {
      categoryUsed: DEFAULT_CATEGORY,
      subCategoryUsed: DEFAULT_SUBCATEGORY,
      isProvisional: true
    };
  }

  return {
    categoryUsed: input.category,
    subCategoryUsed: input.subCategory ?? DEFAULT_SUBCATEGORY,
    isProvisional: false
  };
}

export function createWalletState(config: WalletConfig): WalletState {
  const categoryBalances = CATEGORIES.reduce((acc, category) => {
    acc[category] = 0;
    return acc;
  }, {} as Record<Category, number>);
  const subCategoryBalances: Record<string, number> = {};

  for (const budget of config.categoryBudgets) {
    categoryBalances[budget.category] += budget.amount;
    const key = subCategoryKey(budget.category, budget.subCategory);
    subCategoryBalances[key] = (subCategoryBalances[key] ?? 0) + budget.amount;
  }

  return {
    totalBalance: config.totalBalance,
    categoryBalances,
    subCategoryBalances,
    allocations: []
  };
}

export function applyExpense(state: WalletState, input: AllocationInput): WalletState {
  const { categoryUsed, subCategoryUsed, isProvisional } = resolveAllocationCategory(input);

  const categoryBalances = { ...state.categoryBalances };
  const after = categoryBalances[categoryUsed] - input.amount;
  let usedFallbackOther = false;

  if (categoryUsed !== DEFAULT_CATEGORY && after < 0) {
    categoryBalances[categoryUsed] = 0;
    categoryBalances[DEFAULT_CATEGORY] -= Math.abs(after);
    usedFallbackOther = true;
  } else {
    categoryBalances[categoryUsed] = after;
  }

  const subCategoryBalances = { ...state.subCategoryBalances };
  const key = subCategoryKey(categoryUsed, subCategoryUsed);
  subCategoryBalances[key] = (subCategoryBalances[key] ?? 0) - input.amount;

  return {
    totalBalance: state.totalBalance - input.amount,
    categoryBalances,
    subCategoryBalances,
    allocations: [
      ...state.allocations,
      { id: input.id, amount: input.amount, categoryUsed, subCategoryUsed, isProvisional, usedFallbackOther }
    ]
  };
}

export function replayAllocations(
  baseConfig: WalletConfig,
  inputs: AllocationInput[],
  overrides: Partial<Record<string, CategoryOverride>> = {}
): WalletState {
  return inputs.reduce((state, input) => {
    const override = overrides[input.id];
    return applyExpense(state, override ? { ...input, ...override, needsReview: false } : input);
  }, createWalletState(baseConfig));
}

export function summarizeByCategory(state: WalletState): Record<Category, number> {
  return state.categoryBalances;
}

export function summarizeBySubCategory(state: WalletState): Record<string, number> {
  return state.subCategoryBalances;
}

export function exportScreeningCsv(records: ScreeningCellRecord[]): string {
  const header =
    "receipt_id,merchant_normalized,items_text,screening_category,needs_review,reason,confidence,amount,purchased_at";
  const lines = records.map((r) =>
    [
      r.receipt_id,
      r.merchant_normalized.split(",").join(" "),
      r.items_text.split(",").join(" "),
      r.screening_category,
      r.needs_review,
      r.reason,
      r.confidence,
      r.amount,
      r.purchased_at
    ].join(",")
  );
  return [header, ...lines].join("\n");
}

export function createCsvBackup(currentCsv: string, backupName: string, previousBackups: CsvBackup[]): CsvBackup[] {
  return [...previousBackups, { name: backupName, csv: currentCsv }];
}

export function toScreeningCellRecord(input: AllocationInput): ScreeningCellRecord {
  const needsReview = input.needsReview || input.category === null;
  const screeningCategory: Category | "REVIEW" = needsReview ? "REVIEW" : input.category!;

  return {
    receipt_id: input.id,
    merchant_normalized: input.merchantNormalized ?? "",
    items_text: (input.items ?? []).join("|"),
    screening_category: screeningCategory,
    needs_review: needsReview ? "yes" : "no",
    reason: needsReview ? "manual_review_required" : "recordable",
    confidence: needsReview ? 0 : 0.9,
    amount: input.amount,
    purchased_at: input.purchasedAt ?? ""
  };
}


export function createScreeningCsvTemplate(): string {
  const header =
    "receipt_id,merchant_normalized,items_text,screening_category,needs_review,reason,confidence,amount,purchased_at";
  const sample1 =
    "sample-001,セブンイレブン,おにぎり|牛乳,食費,no,recordable,0.9,450,2026-05-16";
  const sample2 =
    "sample-002,Amazon,充電器,REVIEW,yes,manual_review_required,0,3980,2026-05-16";
  return [header, sample1, sample2].join("\n");
}
