import { ambiguousMerchants, itemKeywordRules, merchantRules } from "./rules";
import { normalizeMerchant } from "./normalizeMerchant";
import type { Category, CategoryScore, ClassificationResult, ReceiptInput } from "./types";

const MERCHANT_SCORE = 80;
const ITEM_SCORE = 50;
const SMALL_MARGIN = 20;

function toSortedScores(scoreMap: Partial<Record<Category, number>>): CategoryScore[] {
  return Object.entries(scoreMap)
    .map(([category, score]) => ({ category: category as Category, score: score ?? 0 }))
    .filter((entry) => entry.score > 0)
    .sort((a, b) => b.score - a.score);
}

export function classifyReceipt(input: ReceiptInput): ClassificationResult {
  const merchantNormalized = normalizeMerchant(input.merchantRaw);
  const items = input.items ?? [];
  const reasons: string[] = [];
  const scoreMap: Partial<Record<Category, number>> = {};

  for (const merchant of ambiguousMerchants) {
    if (merchantNormalized.includes(merchant) && items.length === 0) {
      return {
        merchantNormalized,
        category: null,
        confidence: 0.3,
        needsReview: true,
        reason: `ambiguous merchant: ${merchant}`,
        reasons: [`ambiguous_merchant_no_items: ${merchant}`],
        scores: []
      };
    }
  }

  for (const [merchant, category] of Object.entries(merchantRules)) {
    if (merchantNormalized.includes(merchant)) {
      scoreMap[category] = (scoreMap[category] ?? 0) + MERCHANT_SCORE;
      reasons.push(`merchant_rule: ${merchant}`);
    }
  }

  for (const item of items) {
    for (const [keyword, category] of Object.entries(itemKeywordRules)) {
      if (item.includes(keyword)) {
        scoreMap[category] = (scoreMap[category] ?? 0) + ITEM_SCORE;
        reasons.push(`item_keyword: ${keyword}`);
      }
    }
  }

  const scores = toSortedScores(scoreMap);
  if (scores.length === 0) {
    return {
      merchantNormalized,
      category: null,
      confidence: 0.1,
      needsReview: true,
      reason: "no rule matched",
      reasons: ["no_rule_matched"],
      scores
    };
  }

  const best = scores[0];
  const second = scores[1];
  const total = scores.reduce((sum, s) => sum + s.score, 0);
  const confidence = Math.min(0.99, Number((best.score / total).toFixed(2)));
  const isAmbiguousTop = ambiguousMerchants.some((merchant) => merchantNormalized.includes(merchant));
  const hasSmallMargin = second ? best.score - second.score < SMALL_MARGIN : false;
  const needsReview = isAmbiguousTop || hasSmallMargin;

  return {
    merchantNormalized,
    category: needsReview ? null : best.category,
    confidence,
    needsReview,
    reason: needsReview
      ? isAmbiguousTop
        ? "ambiguous merchant requires review"
        : "score margin too small"
      : `score_winner: ${best.category}`,
    reasons,
    scores
  };
}
