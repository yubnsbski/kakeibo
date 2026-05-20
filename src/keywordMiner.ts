import type { Category } from "./types";

export type LabeledItem = {
  text: string;
  category: Category;
};

export type LabeledExample = {
  source?: string;
  items: LabeledItem[];
};

export type KeywordCandidate = {
  keyword: string;
  category: Category;
  support: number;
  purity: number;
  score: number;
};

export type MineOptions = {
  minLength?: number;
  maxLength?: number;
  minSupport?: number;
  minPurity?: number;
  excludeExistingKeywords?: ReadonlyArray<string>;
};

const DEFAULT_OPTIONS: Required<Omit<MineOptions, "excludeExistingKeywords">> = {
  minLength: 2,
  maxLength: 3,
  minSupport: 2,
  minPurity: 0.8
};

export function extractNgrams(text: string, minLength: number, maxLength: number): string[] {
  const cleaned = text.replace(/\s+/g, "");
  const ngrams = new Set<string>();
  for (let len = minLength; len <= maxLength; len++) {
    if (cleaned.length < len) continue;
    for (let i = 0; i <= cleaned.length - len; i++) {
      ngrams.add(cleaned.slice(i, i + len));
    }
  }
  return Array.from(ngrams);
}

export function mineKeywords(
  examples: ReadonlyArray<LabeledExample>,
  options: MineOptions = {}
): KeywordCandidate[] {
  const opts = { ...DEFAULT_OPTIONS, ...options };
  const excluded = new Set(options.excludeExistingKeywords ?? []);

  const ngramCategoryCounts = new Map<string, Map<Category, number>>();

  for (const example of examples) {
    for (const item of example.items) {
      const ngrams = extractNgrams(item.text, opts.minLength, opts.maxLength);
      for (const ngram of ngrams) {
        if (excluded.has(ngram)) continue;
        let categoryCounts = ngramCategoryCounts.get(ngram);
        if (!categoryCounts) {
          categoryCounts = new Map();
          ngramCategoryCounts.set(ngram, categoryCounts);
        }
        categoryCounts.set(item.category, (categoryCounts.get(item.category) ?? 0) + 1);
      }
    }
  }

  const candidates: KeywordCandidate[] = [];

  for (const [ngram, categoryCounts] of ngramCategoryCounts) {
    let total = 0;
    let bestCategory: Category | null = null;
    let bestCount = 0;
    for (const [category, count] of categoryCounts) {
      total += count;
      if (count > bestCount) {
        bestCount = count;
        bestCategory = category;
      }
    }
    if (!bestCategory) continue;

    const support = bestCount;
    const purity = bestCount / total;

    if (support < opts.minSupport) continue;
    if (purity < opts.minPurity) continue;

    candidates.push({
      keyword: ngram,
      category: bestCategory,
      support,
      purity,
      score: support * purity
    });
  }

  candidates.sort((a, b) => {
    if (b.score !== a.score) return b.score - a.score;
    if (b.support !== a.support) return b.support - a.support;
    return a.keyword.localeCompare(b.keyword);
  });

  return removeSubstringRedundancy(candidates);
}

function removeSubstringRedundancy(candidates: KeywordCandidate[]): KeywordCandidate[] {
  const kept: KeywordCandidate[] = [];
  for (const candidate of candidates) {
    const isCoveredByLongerKept = kept.some(
      (existing) =>
        existing.category === candidate.category &&
        existing.keyword.includes(candidate.keyword) &&
        existing.keyword !== candidate.keyword &&
        existing.support >= candidate.support
    );
    if (isCoveredByLongerKept) continue;
    kept.push(candidate);
  }
  return kept;
}
