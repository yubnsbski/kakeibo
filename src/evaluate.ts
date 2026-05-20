import { classifyReceipt } from "./classifyReceipt";
import { classifyItem, type ClassifyItemOptions } from "./classifyItem";
import type { Category, ReceiptInput } from "./types";

export type ReceiptEvaluationCase = {
  name: string;
  input: ReceiptInput;
  expected: {
    category: Category | null;
    needsReview: boolean;
  };
};

export type ItemEvaluationCase = {
  text: string;
  expectedCategory: Category | null;
};

export type ReceiptEvaluationReport = {
  total: number;
  correct: number;
  accuracy: number;
  needsReviewRate: number;
  failures: Array<{
    name: string;
    expected: ReceiptEvaluationCase["expected"];
    actual: { category: Category | null; needsReview: boolean };
  }>;
};

export type ItemEvaluationReport = {
  total: number;
  correct: number;
  accuracy: number;
  failures: Array<{
    text: string;
    expected: Category | null;
    actual: Category | null;
  }>;
};

export function evaluateReceipts(cases: ReadonlyArray<ReceiptEvaluationCase>): ReceiptEvaluationReport {
  let correct = 0;
  let needsReviewCount = 0;
  const failures: ReceiptEvaluationReport["failures"] = [];

  for (const c of cases) {
    const result = classifyReceipt(c.input);
    const matches =
      result.category === c.expected.category && result.needsReview === c.expected.needsReview;
    if (matches) {
      correct += 1;
    } else {
      failures.push({
        name: c.name,
        expected: c.expected,
        actual: { category: result.category, needsReview: result.needsReview }
      });
    }
    if (result.needsReview) needsReviewCount += 1;
  }

  const total = cases.length;
  return {
    total,
    correct,
    accuracy: total === 0 ? 0 : correct / total,
    needsReviewRate: total === 0 ? 0 : needsReviewCount / total,
    failures
  };
}

export function evaluateItems(
  cases: ReadonlyArray<ItemEvaluationCase>,
  options: ClassifyItemOptions = {}
): ItemEvaluationReport {
  let correct = 0;
  const failures: ItemEvaluationReport["failures"] = [];

  for (const c of cases) {
    const result = classifyItem(c.text, options);
    if (result.category === c.expectedCategory) {
      correct += 1;
    } else {
      failures.push({
        text: c.text,
        expected: c.expectedCategory,
        actual: result.category
      });
    }
  }

  const total = cases.length;
  return {
    total,
    correct,
    accuracy: total === 0 ? 0 : correct / total,
    failures
  };
}

export function formatReceiptReport(report: ReceiptEvaluationReport): string {
  const lines: string[] = [];
  lines.push("# receipt evaluation");
  lines.push(`accuracy:        ${(report.accuracy * 100).toFixed(1)}% (${report.correct}/${report.total})`);
  lines.push(`needs_review_rate: ${(report.needsReviewRate * 100).toFixed(1)}%`);
  if (report.failures.length === 0) {
    lines.push("failures:        (none)");
  } else {
    lines.push("failures:");
    for (const f of report.failures) {
      lines.push(
        `  - ${f.name}: expected category=${stringifyCategory(f.expected.category)} needsReview=${f.expected.needsReview}, got category=${stringifyCategory(f.actual.category)} needsReview=${f.actual.needsReview}`
      );
    }
  }
  return lines.join("\n");
}

export function formatItemReport(report: ItemEvaluationReport): string {
  const lines: string[] = [];
  lines.push("# item evaluation");
  lines.push(`accuracy: ${(report.accuracy * 100).toFixed(1)}% (${report.correct}/${report.total})`);
  if (report.failures.length === 0) {
    lines.push("failures: (none)");
  } else {
    lines.push("failures:");
    for (const f of report.failures) {
      lines.push(
        `  - ${f.text}: expected=${stringifyCategory(f.expected)}, got=${stringifyCategory(f.actual)}`
      );
    }
  }
  return lines.join("\n");
}

function stringifyCategory(category: Category | null): string {
  return category === null ? "(null)" : category;
}
