import type { Category } from "./types";
import type { LabeledExample, LabeledItem } from "./keywordMiner";

export type ConfirmedItem = {
  text: string;
  confirmedCategory: Category;
};

export type ManualReviewEntry = {
  source: string;
  confirmedItems: ConfirmedItem[];
};

export function toLabeledExamples(reviews: ReadonlyArray<ManualReviewEntry>): LabeledExample[] {
  return reviews
    .map((review) => {
      const items: LabeledItem[] = review.confirmedItems
        .filter((item) => item.text.trim().length > 0)
        .map((item) => ({ text: item.text.trim(), category: item.confirmedCategory }));
      return { source: review.source, items };
    })
    .filter((example) => example.items.length > 0);
}

export function mergeLabeledExamples(
  existing: ReadonlyArray<LabeledExample>,
  additions: ReadonlyArray<LabeledExample>
): LabeledExample[] {
  const bySource = new Map<string, LabeledExample>();
  const sourceless: LabeledExample[] = [];

  for (const example of existing) {
    if (example.source) {
      bySource.set(example.source, cloneExample(example));
    } else {
      sourceless.push(cloneExample(example));
    }
  }

  for (const addition of additions) {
    if (!addition.source) {
      sourceless.push(cloneExample(addition));
      continue;
    }
    const previous = bySource.get(addition.source);
    if (!previous) {
      bySource.set(addition.source, cloneExample(addition));
      continue;
    }
    bySource.set(addition.source, {
      source: addition.source,
      items: dedupeItems([...previous.items, ...addition.items])
    });
  }

  return [...bySource.values(), ...sourceless];
}

function cloneExample(example: LabeledExample): LabeledExample {
  return {
    source: example.source,
    items: example.items.map((item) => ({ ...item }))
  };
}

function dedupeItems(items: ReadonlyArray<LabeledItem>): LabeledItem[] {
  const seen = new Map<string, LabeledItem>();
  for (const item of items) {
    const key = `${item.text}${item.category}`;
    if (!seen.has(key)) {
      seen.set(key, { ...item });
    }
  }
  return Array.from(seen.values());
}
