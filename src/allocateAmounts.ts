import type {
  AmountAllocationResult,
  Category,
  CategoryAllocation,
  ReceiptBreakdown
} from "./types";

export type AllocateOptions = {
  perItemAmounts?: number[];
};

export function allocateAmountsByCategory(
  breakdown: ReceiptBreakdown,
  totalAmount: number,
  options: AllocateOptions = {}
): AmountAllocationResult {
  assertNonNegative(totalAmount, "totalAmount");

  const items = breakdown.items;
  if (items.length === 0) {
    return {
      totalAmount,
      allocations: [],
      strategy: "equal_split",
      unclassifiedAmount: totalAmount
    };
  }

  const perItem = resolvePerItemAmounts(items.length, totalAmount, options.perItemAmounts);
  const strategy = options.perItemAmounts ? "per_item_amounts" : "equal_split";

  const buckets = new Map<Category | null, { amount: number; itemTexts: string[] }>();
  for (let i = 0; i < items.length; i++) {
    const item = items[i];
    const amount = perItem[i];
    const bucket = buckets.get(item.category) ?? { amount: 0, itemTexts: [] };
    bucket.amount += amount;
    bucket.itemTexts.push(item.text);
    buckets.set(item.category, bucket);
  }

  const allocations: CategoryAllocation[] = Array.from(buckets.entries())
    .map(([category, bucket]) => ({
      category,
      amount: bucket.amount,
      itemTexts: bucket.itemTexts
    }))
    .sort((a, b) => b.amount - a.amount);

  const unclassifiedAmount = allocations.find((a) => a.category === null)?.amount ?? 0;

  return {
    totalAmount,
    allocations,
    strategy,
    unclassifiedAmount
  };
}

function resolvePerItemAmounts(
  itemCount: number,
  totalAmount: number,
  provided: number[] | undefined
): number[] {
  if (provided) {
    if (provided.length !== itemCount) {
      throw new Error(
        `perItemAmounts length (${provided.length}) does not match items length (${itemCount})`
      );
    }
    for (const amount of provided) {
      assertNonNegative(amount, "perItemAmounts entry");
    }
    return provided.slice();
  }

  return equalSplit(totalAmount, itemCount);
}

function equalSplit(total: number, count: number): number[] {
  if (count === 0) return [];
  const base = Math.floor((total / count) * 100) / 100;
  const amounts = new Array<number>(count).fill(base);
  const distributed = roundCurrency(base * count);
  const remainder = roundCurrency(total - distributed);
  amounts[count - 1] = roundCurrency(amounts[count - 1] + remainder);
  return amounts;
}

function roundCurrency(value: number): number {
  return Math.round(value * 100) / 100;
}

function assertNonNegative(value: number, label: string): void {
  if (!Number.isFinite(value) || value < 0) {
    throw new Error(`${label} must be a finite non-negative number, got ${value}`);
  }
}
