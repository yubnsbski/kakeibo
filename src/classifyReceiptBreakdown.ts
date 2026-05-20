import { classifyItem, type ClassifyItemOptions } from "./classifyItem";
import { normalizeMerchant } from "./normalizeMerchant";
import type { Category, ItemClassification, ReceiptBreakdown, ReceiptInput } from "./types";

export type BreakdownOptions = ClassifyItemOptions;

export function classifyReceiptBreakdown(
  input: ReceiptInput,
  options: BreakdownOptions = {}
): ReceiptBreakdown {
  const merchantNormalized = normalizeMerchant(input.merchantRaw);
  const items = (input.items ?? []).map((text) => classifyItem(text, options));

  const categoryCounts = new Map<Category, number>();
  for (const item of items) {
    if (item.category) {
      categoryCounts.set(item.category, (categoryCounts.get(item.category) ?? 0) + 1);
    }
  }

  const dominantCategory = pickDominantCategory(categoryCounts);
  const isMixed = categoryCounts.size > 1;
  const hasUnclassified = items.some((item) => item.category === null);
  const needsReview = items.length === 0 || hasUnclassified || isMixed;

  return {
    merchantNormalized,
    items,
    dominantCategory,
    isMixed,
    needsReview
  };
}

function pickDominantCategory(counts: Map<Category, number>): Category | null {
  let best: Category | null = null;
  let bestCount = 0;
  let tied = false;

  for (const [category, count] of counts) {
    if (count > bestCount) {
      best = category;
      bestCount = count;
      tied = false;
    } else if (count === bestCount) {
      tied = true;
    }
  }

  return tied ? null : best;
}

export function summarizeItemsByCategory(
  breakdown: ReceiptBreakdown
): Array<{ category: Category | null; itemTexts: string[] }> {
  const grouped = new Map<Category | null, string[]>();
  for (const item of breakdown.items) {
    const existing = grouped.get(item.category) ?? [];
    existing.push(item.text);
    grouped.set(item.category, existing);
  }
  return Array.from(grouped.entries()).map(([category, itemTexts]) => ({ category, itemTexts }));
}
