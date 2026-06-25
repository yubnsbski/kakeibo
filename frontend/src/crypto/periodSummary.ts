import type { NormalizedEncryptedTx, TxType } from "./txPayload";

export type PeriodUnit = "day" | "month" | "year";

export type CategoryTotal = {
  category: string;
  amount: number;
};

export type PeriodCategorySummary = {
  unit: PeriodUnit;
  anchorDate: string;
  label: string;
  matchingRows: number;
  fallbackRows: number;
  skippedInvalidRows: number;
  expenseTotal: number;
  incomeTotal: number;
  balance: number;
  expenseCategories: CategoryTotal[];
  incomeCategories: CategoryTotal[];
};

type Allocation = {
  category: string;
  amount: number;
};

function isValidIsoDate(value: string): boolean {
  const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (!match) return false;

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const date = new Date(Date.UTC(year, month - 1, day));

  return (
    date.getUTCFullYear() === year &&
    date.getUTCMonth() === month - 1 &&
    date.getUTCDate() === day
  );
}

function normalizeCategoryLabel(value: string | null | undefined): string {
  return value?.trim() || "未分類";
}

function isUsableAmount(value: number): boolean {
  return Number.isFinite(value) && value >= 0;
}

function matchesPeriod(
  date: string,
  unit: PeriodUnit,
  anchorDate: string,
): boolean {
  if (!isValidIsoDate(date)) return false;
  if (unit === "day") return date === anchorDate;
  if (unit === "month") return date.slice(0, 7) === anchorDate.slice(0, 7);
  return date.slice(0, 4) === anchorDate.slice(0, 4);
}

function allocationsForRow(row: NormalizedEncryptedTx): {
  allocations: Allocation[];
  usedFallback: boolean;
} {
  const validLineItems =
    row.line_items.length > 0 &&
    row.line_items.every((item) => isUsableAmount(item.amount));
  const lineItemTotal = validLineItems
    ? row.line_items.reduce((sum, item) => sum + item.amount, 0)
    : Number.NaN;

  if (validLineItems && lineItemTotal === row.amount) {
    return {
      allocations: row.line_items.map((item) => ({
        category: normalizeCategoryLabel(item.category || row.category),
        amount: item.amount,
      })),
      usedFallback: false,
    };
  }

  return {
    allocations: [
      {
        category: normalizeCategoryLabel(row.category),
        amount: isUsableAmount(row.amount) ? row.amount : 0,
      },
    ],
    usedFallback: true,
  };
}

function addAllocations(
  target: Map<string, number>,
  allocations: Allocation[],
): void {
  for (const allocation of allocations) {
    target.set(
      allocation.category,
      (target.get(allocation.category) ?? 0) + allocation.amount,
    );
  }
}

function sortedCategoryTotals(source: Map<string, number>): CategoryTotal[] {
  return [...source.entries()]
    .map(([category, amount]) => ({ category, amount }))
    .sort((left, right) => {
      const amountOrder = right.amount - left.amount;
      return amountOrder !== 0
        ? amountOrder
        : left.category.localeCompare(right.category, "ja");
    });
}

export function periodLabel(unit: PeriodUnit, anchorDate: string): string {
  if (!isValidIsoDate(anchorDate)) {
    throw new Error("集計基準日はYYYY-MM-DD形式の実在日で指定してください");
  }

  const [year, month, day] = anchorDate.split("-").map(Number);
  if (unit === "day") return `${year}年${month}月${day}日`;
  if (unit === "month") return `${year}年${month}月`;
  return `${year}年`;
}

export function summarizeByCategory(
  rows: NormalizedEncryptedTx[],
  unit: PeriodUnit,
  anchorDate: string,
): PeriodCategorySummary {
  const label = periodLabel(unit, anchorDate);
  const categoryMaps: Record<TxType, Map<string, number>> = {
    expense: new Map<string, number>(),
    income: new Map<string, number>(),
  };

  let matchingRows = 0;
  let fallbackRows = 0;
  let skippedInvalidRows = 0;
  let expenseTotal = 0;
  let incomeTotal = 0;

  for (const row of rows) {
    if (!isValidIsoDate(row.date)) {
      skippedInvalidRows += 1;
      continue;
    }
    if (!matchesPeriod(row.date, unit, anchorDate)) continue;

    matchingRows += 1;
    const { allocations, usedFallback } = allocationsForRow(row);
    if (usedFallback) fallbackRows += 1;

    addAllocations(categoryMaps[row.tx_type], allocations);
    if (row.tx_type === "expense") {
      expenseTotal += isUsableAmount(row.amount) ? row.amount : 0;
    } else {
      incomeTotal += isUsableAmount(row.amount) ? row.amount : 0;
    }
  }

  return {
    unit,
    anchorDate,
    label,
    matchingRows,
    fallbackRows,
    skippedInvalidRows,
    expenseTotal,
    incomeTotal,
    balance: incomeTotal - expenseTotal,
    expenseCategories: sortedCategoryTotals(categoryMaps.expense),
    incomeCategories: sortedCategoryTotals(categoryMaps.income),
  };
}
