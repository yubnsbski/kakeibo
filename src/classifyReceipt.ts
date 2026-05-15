import { ambiguousMerchants, itemKeywordRules, merchantRules } from "./rules";
import { normalizeMerchant } from "./normalizeMerchant";
import type { ClassificationResult, ReceiptInput } from "./types";

export function classifyReceipt(input: ReceiptInput): ClassificationResult {
  const merchantNormalized = normalizeMerchant(input.merchantRaw);
  const items = input.items ?? [];

  for (const [merchant, category] of Object.entries(merchantRules)) {
    if (merchantNormalized.includes(merchant)) {
      return {
        merchantNormalized,
        category,
        confidence: 0.9,
        needsReview: false,
        reason: `merchant_rule matched: ${merchant}`
      };
    }
  }

  for (const item of items) {
    for (const [keyword, category] of Object.entries(itemKeywordRules)) {
      if (item.includes(keyword)) {
        return {
          merchantNormalized,
          category,
          confidence: 0.75,
          needsReview: false,
          reason: `item_keyword matched: ${keyword}`
        };
      }
    }
  }

  for (const merchant of ambiguousMerchants) {
    if (merchantNormalized.includes(merchant)) {
      return {
        merchantNormalized,
        category: null,
        confidence: 0.3,
        needsReview: true,
        reason: `ambiguous merchant: ${merchant}`
      };
    }
  }

  return {
    merchantNormalized,
    category: null,
    confidence: 0.1,
    needsReview: true,
    reason: "no rule matched"
  };
}
