import { itemKeywordRules } from "./rules";
import type { Category, ItemClassification, TaxRateHint } from "./types";

export type ClassifyItemOptions = {
  additionalKeywordRules?: Partial<Record<string, Category>>;
  taxRateHint?: TaxRateHint;
};

export function classifyItem(itemText: string, options: ClassifyItemOptions = {}): ItemClassification {
  const text = itemText.trim();
  if (text === "") {
    return {
      text,
      category: null,
      reason: "empty_item",
      matchedKeyword: null
    };
  }

  const merged = mergeKeywordRules(options.additionalKeywordRules);

  let bestKeyword: string | null = null;
  let bestCategory: Category | null = null;

  for (const [keyword, category] of merged) {
    if (!text.includes(keyword)) continue;
    if (bestKeyword === null || keyword.length > bestKeyword.length) {
      bestKeyword = keyword;
      bestCategory = category;
    }
  }

  if (bestKeyword !== null && bestCategory !== null) {
    return {
      text,
      category: bestCategory,
      reason: `item_keyword: ${bestKeyword}`,
      matchedKeyword: bestKeyword
    };
  }

  if (options.taxRateHint === "reduced") {
    return {
      text,
      category: "食費",
      reason: "tax_rate_hint: reduced→食費",
      matchedKeyword: null
    };
  }

  return {
    text,
    category: null,
    reason: "no_keyword_matched",
    matchedKeyword: null
  };
}

function mergeKeywordRules(
  additional: Partial<Record<string, Category>> | undefined
): Array<[string, Category]> {
  const merged = new Map<string, Category>(Object.entries(itemKeywordRules));
  if (additional) {
    for (const [keyword, category] of Object.entries(additional)) {
      if (category && keyword) {
        merged.set(keyword, category);
      }
    }
  }
  return Array.from(merged.entries());
}
