import { describe, expect, test } from "vitest";
import {
  evaluateItems,
  evaluateReceipts,
  formatItemReport,
  formatReceiptReport
} from "../src/evaluate";

describe("evaluateReceipts", () => {
  test("既存ルールでヒットするケースはaccuracy=1", () => {
    const report = evaluateReceipts([
      {
        name: "seven",
        input: { merchantRaw: "セブンイレブン", items: ["おにぎり"] },
        expected: { category: "食費", needsReview: false }
      }
    ]);
    expect(report.accuracy).toBe(1);
    expect(report.failures).toEqual([]);
  });

  test("期待と異なる結果はfailuresに入る", () => {
    const report = evaluateReceipts([
      {
        name: "wrong_expectation",
        input: { merchantRaw: "セブンイレブン", items: ["おにぎり"] },
        expected: { category: "教育", needsReview: false }
      }
    ]);
    expect(report.accuracy).toBe(0);
    expect(report.failures).toHaveLength(1);
    expect(report.failures[0].actual.category).toBe("食費");
  });

  test("needsReviewRateを正しく算出する", () => {
    const report = evaluateReceipts([
      {
        name: "ok",
        input: { merchantRaw: "セブンイレブン", items: ["おにぎり"] },
        expected: { category: "食費", needsReview: false }
      },
      {
        name: "amazon",
        input: { merchantRaw: "Amazon.co.jp", items: [] },
        expected: { category: null, needsReview: true }
      }
    ]);
    expect(report.needsReviewRate).toBeCloseTo(0.5, 2);
  });

  test("空ケースはaccuracy=0だがエラーにはならない", () => {
    const report = evaluateReceipts([]);
    expect(report.total).toBe(0);
    expect(report.accuracy).toBe(0);
  });

  test("formatReceiptReportは人間可読な文字列を返す", () => {
    const text = formatReceiptReport({
      total: 1,
      correct: 1,
      accuracy: 1,
      needsReviewRate: 0,
      failures: []
    });
    expect(text).toContain("accuracy");
    expect(text).toContain("(none)");
  });
});

describe("evaluateItems", () => {
  test("既存itemKeywordRulesで正答するケース", () => {
    const report = evaluateItems([
      { text: "おにぎり鮭", expectedCategory: "食費" },
      { text: "シャンプー詰替", expectedCategory: "日用品" }
    ]);
    expect(report.accuracy).toBe(1);
  });

  test("additionalKeywordRulesで実行時注入できる", () => {
    const report = evaluateItems(
      [{ text: "雑誌書籍", expectedCategory: "教育" }],
      { additionalKeywordRules: { 書籍: "教育" } }
    );
    expect(report.accuracy).toBe(1);
  });

  test("formatItemReportはfailuresを含めて出力する", () => {
    const text = formatItemReport({
      total: 1,
      correct: 0,
      accuracy: 0,
      failures: [{ text: "謎の物体", expected: "食費", actual: null }]
    });
    expect(text).toContain("謎の物体");
    expect(text).toContain("expected=食費");
  });
});
