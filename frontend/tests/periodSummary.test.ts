import { describe, expect, test } from "vitest";
import { summarizeByCategory } from "../src/crypto/periodSummary";

type TestRow = {
  date: string;
  tx_type: "expense" | "income";
  merchant: string;
  amount_mode: "tax_included" | "tax_excluded";
  amount: number;
  category: string;
  memo: string;
  source: "manual";
  line_items: Array<{
    name: string;
    amount: number;
    category: string;
  }>;
};

function makeRow(overrides: Partial<TestRow> = {}): TestRow {
  const amount = overrides.amount ?? 100;
  const category = overrides.category ?? "食費";
  return {
    date: "2026-06-25",
    tx_type: "expense",
    merchant: "テスト店舗",
    amount_mode: "tax_included",
    amount,
    category,
    memo: "",
    source: "manual",
    line_items: [
      {
        name: "明細",
        amount,
        category,
      },
    ],
    ...overrides,
  };
}

describe("period category summary", () => {
  const rows: TestRow[] = [
    makeRow({ date: "2026-06-25", amount: 100, category: "食費" }),
    makeRow({ date: "2026-06-24", amount: 200, category: "日用品" }),
    makeRow({ date: "2026-05-31", amount: 300, category: "交通" }),
    makeRow({ date: "2025-06-25", amount: 400, category: "医療" }),
    makeRow({
      date: "2026-06-25",
      tx_type: "income",
      amount: 1000,
      category: "給与",
      line_items: [{ name: "給与", amount: 1000, category: "給与" }],
    }),
  ];

  test("日単位では同日の支出と収入だけを集計する", () => {
    const summary = summarizeByCategory(rows, "day", "2026-06-25");

    expect(summary.expenseTotal).toBe(100);
    expect(summary.incomeTotal).toBe(1000);
    expect(summary.balance).toBe(900);
    expect(summary.expenseCategories).toEqual([
      { category: "食費", amount: 100 },
    ]);
  });

  test("月単位では同月の全日を集計する", () => {
    const summary = summarizeByCategory(rows, "month", "2026-06-01");

    expect(summary.expenseTotal).toBe(300);
    expect(summary.incomeTotal).toBe(1000);
    expect(summary.matchingRows).toBe(3);
  });

  test("年単位では同年の全月を集計する", () => {
    const summary = summarizeByCategory(rows, "year", "2026-01-01");

    expect(summary.expenseTotal).toBe(600);
    expect(summary.incomeTotal).toBe(1000);
    expect(summary.matchingRows).toBe(4);
  });

  test("明細合計が一致すれば明細カテゴリへ配分する", () => {
    const mixed = makeRow({
      amount: 1000,
      category: "その他",
      line_items: [
        { name: "食品", amount: 400, category: "食費" },
        { name: "酒", amount: 600, category: "酒類" },
      ],
    });

    const summary = summarizeByCategory([mixed], "day", "2026-06-25");

    expect(summary.fallbackRows).toBe(0);
    expect(summary.expenseCategories).toEqual([
      { category: "酒類", amount: 600 },
      { category: "食費", amount: 400 },
    ]);
  });

  test("明細合計が取引合計と違う場合は取引カテゴリへフォールバックする", () => {
    const inconsistent = makeRow({
      amount: 1000,
      category: "日用品",
      line_items: [
        { name: "A", amount: 400, category: "食費" },
        { name: "B", amount: 500, category: "交通" },
      ],
    });

    const summary = summarizeByCategory(
      [inconsistent],
      "day",
      "2026-06-25",
    );

    expect(summary.fallbackRows).toBe(1);
    expect(summary.expenseTotal).toBe(1000);
    expect(summary.expenseCategories).toEqual([
      { category: "日用品", amount: 1000 },
    ]);
  });

  test("不正な日付の行は集計対象外として数える", () => {
    const invalid = makeRow({ date: "2026-02-30" });
    const summary = summarizeByCategory([invalid], "year", "2026-01-01");

    expect(summary.matchingRows).toBe(0);
    expect(summary.skippedInvalidRows).toBe(1);
  });
});
