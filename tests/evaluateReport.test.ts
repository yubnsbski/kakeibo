import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, test } from "vitest";
import {
  evaluateItems,
  evaluateReceipts,
  formatItemReport,
  formatReceiptReport,
  type ItemEvaluationCase,
  type ReceiptEvaluationCase
} from "../src/evaluate";
import { itemKeywordRules } from "../src/rules";
import { mineKeywords, type LabeledExample } from "../src/keywordMiner";
import type { Category } from "../src/types";

const REPORT_MODE = process.env.EVALUATE_REPORT === "1";

describe.skipIf(!REPORT_MODE)("evaluation report", () => {
  test("receipt-level evaluation", () => {
    const filePath = join(__dirname, "..", "fixtures", "receipts", "evaluation.json");
    const cases = JSON.parse(readFileSync(filePath, "utf-8")) as ReceiptEvaluationCase[];
    const report = evaluateReceipts(cases);
    console.log("\n" + formatReceiptReport(report));
  });

  test("item-level evaluation (baseline + mined keywords)", () => {
    const filePath = join(__dirname, "..", "fixtures", "training", "labeled-items.json");
    const examples = JSON.parse(readFileSync(filePath, "utf-8")) as LabeledExample[];
    const cases: ItemEvaluationCase[] = examples.flatMap((ex) =>
      ex.items.map((it) => ({ text: it.text, expectedCategory: it.category }))
    );

    const baseline = evaluateItems(cases);
    console.log("\n## baseline (rules.ts only)");
    console.log(formatItemReport(baseline));

    const mined = mineKeywords(examples, {
      minLength: 2,
      maxLength: 3,
      minSupport: 2,
      minPurity: 0.8,
      excludeExistingKeywords: Object.keys(itemKeywordRules)
    });
    const additional: Partial<Record<string, Category>> = {};
    for (const candidate of mined) {
      additional[candidate.keyword] = candidate.category;
    }

    const augmented = evaluateItems(cases, { additionalKeywordRules: additional });
    console.log("\n## with mined keywords");
    console.log(formatItemReport(augmented));
    console.log(`\ndelta accuracy: ${((augmented.accuracy - baseline.accuracy) * 100).toFixed(1)}pt`);
  });
});
