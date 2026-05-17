import { describe, expect, test } from "vitest";
import {
  applyExpense,
  createCsvBackup,
  createWalletState,
  exportScreeningCsv,
  replayAllocations,
  summarizeByCategory,
  summarizeBySubCategory,
  toScreeningCellRecord,
  createScreeningCsvTemplate
} from "../src/walletEngine";

describe("walletEngine", () => {
  const baseConfig = {
    totalBalance: 5_000_000,
    categoryBudgets: [
      { category: "食費" as const, subCategory: "スーパー", amount: 50_000 },
      { category: "日用品" as const, subCategory: "消耗品", amount: 20_000 },
      { category: "その他" as const, subCategory: "予備", amount: 100_000 }
    ]
  };

  test("カテゴリとサブカテゴリの両方で集計できる", () => {
    const state = createWalletState(baseConfig);
    const next = applyExpense(state, {
      id: "r1",
      amount: 3_000,
      category: "食費",
      subCategory: "スーパー",
      needsReview: false
    });

    expect(summarizeByCategory(next).食費).toBe(47_000);
    expect(summarizeBySubCategory(next)["食費:スーパー"]).toBe(47_000);
  });

  test("不足時はその他にフォールバックする", () => {
    const state = createWalletState(baseConfig);
    const next = applyExpense(state, {
      id: "r2",
      amount: 30_000,
      category: "日用品",
      subCategory: "消耗品",
      needsReview: false
    });

    expect(next.categoryBalances.日用品).toBe(0);
    expect(next.categoryBalances.その他).toBe(90_000);
  });

  test("needsReviewはその他に仮計上する", () => {
    const state = createWalletState(baseConfig);
    const next = applyExpense(state, {
      id: "r3",
      amount: 8_000,
      category: null,
      needsReview: true
    });

    expect(next.allocations[0]?.categoryUsed).toBe("その他");
    expect(next.allocations[0]?.isProvisional).toBe(true);
  });

  test("手動修正して再計算できる", () => {
    const withOverride = replayAllocations(
      baseConfig,
      [
        { id: "r4", amount: 10_000, category: null, needsReview: true },
        { id: "r5", amount: 5_000, category: "食費", subCategory: "スーパー", needsReview: false }
      ],
      { r4: { category: "日用品", subCategory: "消耗品" } }
    );

    expect(withOverride.categoryBalances.日用品).toBe(10_000);
    expect(withOverride.categoryBalances.その他).toBe(100_000);
  });

  test("スクリーニング結果をセル記録に変換できる", () => {
    const record = toScreeningCellRecord({
      id: "s1",
      amount: 1234,
      category: "食費",
      needsReview: false,
      merchantNormalized: "セブンイレブン",
      items: ["おにぎり", "牛乳"],
      purchasedAt: "2026-05-16"
    });

    expect(record.screening_category).toBe("食費");
    expect(record.needs_review).toBe("no");
    expect(record.items_text).toBe("おにぎり|牛乳");
  });

  test("CSV出力とバックアップ保持ができる", () => {
    const csv = exportScreeningCsv([
      {
        receipt_id: "r8",
        merchant_normalized: "セブンイレブン",
        items_text: "おにぎり|牛乳",
        screening_category: "食費",
        needs_review: "no",
        reason: "recordable",
        confidence: 0.9,
        amount: 450,
        purchased_at: "2026-05-16"
      }
    ]);

    expect(csv).toContain("receipt_id,merchant_normalized,items_text");
    const backups = createCsvBackup(csv, "backup-2026-05-16", []);
    expect(backups).toHaveLength(1);
  });


  test("運用向けCSVテンプレを生成できる", () => {
    const template = createScreeningCsvTemplate();
    expect(template).toContain("receipt_id,merchant_normalized,items_text,screening_category");
    expect(template).toContain("sample-001,セブンイレブン,おにぎり|牛乳,食費,no");
    expect(template).toContain("sample-002,Amazon,充電器,REVIEW,yes");
  });

});
