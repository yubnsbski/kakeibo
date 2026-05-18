import { ambiguousMerchants, itemKeywordRules, merchantRules } from "./rules";
import { normalizeMerchant } from "./normalizeMerchant";
import type { Category, ClassificationResult, ReceiptInput } from "./types";

const MERCHANT_RULE_CONFIDENCE = 0.92;
const ITEM_RULE_CONFIDENCE = 0.78;
const MANUAL_REVIEW_CONFIDENCE = 0.35;
const REVIEW_CONFIDENCE = 0;

const categories: Category[] = ["食費", "日用品", "交通", "医療", "通信", "娯楽", "教育", "その他"];

function isCategory(value: unknown): value is Category {
  return typeof value === "string" && categories.includes(value as Category);
}

function findUserOverrideCategory(
  merchantNormalized: string,
  userCategoryOverrides: Partial<Record<string, Category>> | undefined
): Category | null {
  if (!userCategoryOverrides) return null;

  for (const [merchant, category] of Object.entries(userCategoryOverrides)) {
    const normalizedKey = normalizeMerchant(merchant);
    if (normalizedKey && merchantNormalized.includes(normalizedKey) && isCategory(category)) {
      return category;
    }
  }

  return null;
}

function matchMerchantRule(merchantNormalized: string): { category: Category; reason: string } | null {
  for (const [merchant, category] of Object.entries(merchantRules)) {
    if (merchantNormalized.includes(merchant)) {
      return { category, reason: `merchant_rule: ${merchant}` };
    }
  }
  return null;
}

function matchItemRule(items: string[]): { category: Category; reason: string } | null {
  for (const item of items) {
    const normalizedItem = item.trim();
    if (!normalizedItem) continue;

    for (const [keyword, category] of Object.entries(itemKeywordRules)) {
      if (normalizedItem.includes(keyword)) {
        return { category, reason: `item_keyword: ${keyword}` };
      }
    }
  }
  return null;
}

export function classifyReceipt(input: ReceiptInput): ClassificationResult {
  const merchantNormalized = normalizeMerchant(input.merchantRaw);
  const items = (input.items ?? []).filter((item) => item.trim().length > 0);
  const isAmbiguous = ambiguousMerchants.some((merchant) => merchantNormalized.includes(merchant));

  const override = findUserOverrideCategory(merchantNormalized, input.userCategoryOverrides);
  if (override) {
    return {
      merchantNormalized,
      category: override,
      confidence: 1,
      needsReview: false,
      reason: `user_override: ${override}`,
      reasons: ["user_override"],
      screeningLabel: "recordable"
    };
  }

  if (isAmbiguous && items.length === 0) {
    return {
      merchantNormalized,
      category: null,
      confidence: REVIEW_CONFIDENCE,
      needsReview: true,
      reason: "ambiguous merchant without items",
      reasons: ["ambiguous_merchant_no_items"],
      screeningLabel: "needs_review"
    };
  }

  const merchantMatch = matchMerchantRule(merchantNormalized);
  const itemMatch = merchantMatch ? null : matchItemRule(items);
  const match = merchantMatch ?? itemMatch;

  if (!match) {
    return {
      merchantNormalized,
      category: null,
      confidence: REVIEW_CONFIDENCE,
      needsReview: true,
      reason: "no rule matched",
      reasons: ["no_rule_matched"],
      screeningLabel: "needs_review"
    };
  }

  if (isAmbiguous) {
    return {
      merchantNormalized,
      category: null,
      confidence: MANUAL_REVIEW_CONFIDENCE,
      needsReview: true,
      reason: "ambiguous merchant requires manual category",
      reasons: [match.reason, "ambiguous_merchant_with_items"],
      screeningLabel: "needs_review"
    };
  }

  return {
    merchantNormalized,
    category: match.category,
    confidence: merchantMatch ? MERCHANT_RULE_CONFIDENCE : ITEM_RULE_CONFIDENCE,
    needsReview: false,
    reason: `rule_match: ${match.category}`,
    reasons: [match.reason],
    screeningLabel: "recordable"
  };
}
