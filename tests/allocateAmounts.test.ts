import { describe, expect, test } from "vitest";
import { allocateAmountsByCategory } from "../src/allocateAmounts";
import { classifyReceiptBreakdown } from "../src/classifyReceiptBreakdown";

describe("allocateAmountsByCategory", () => {
  test("perItemAmounts指定でカテゴリ別に正確按分する（FamilyMart実レシート）", () => {
    const breakdown = classifyReceiptBreakdown(
      {
        merchantRaw: "FamilyMart 船橋海神二丁目店",
        items: ["ミルクの束縛ミルクCO", "雑誌書籍"],
        totalAmount: 408
      },
      { additionalKeywordRules: { ミルク: "食費", 書籍: "教育", 雑誌: "教育" } }
    );

    const result = allocateAmountsByCategory(breakdown, 408, { perItemAmounts: [228, 180] });

    expect(result.strategy).toBe("per_item_amounts");
    const food = result.allocations.find((a) => a.category === "食費");
    const education = result.allocations.find((a) => a.category === "教育");
    expect(food?.amount).toBe(228);
    expect(education?.amount).toBe(180);
    expect(result.unclassifiedAmount).toBe(0);
  });

  test("perItemAmounts未指定なら均等按分する", () => {
    const breakdown = classifyReceiptBreakdown(
      {
        merchantRaw: "FamilyMart",
        items: ["ミルク", "雑誌書籍"]
      },
      { additionalKeywordRules: { ミルク: "食費", 書籍: "教育", 雑誌: "教育" } }
    );

    const result = allocateAmountsByCategory(breakdown, 408);

    expect(result.strategy).toBe("equal_split");
    const total = result.allocations.reduce((sum, a) => sum + a.amount, 0);
    expect(total).toBe(408);
    expect(result.allocations).toHaveLength(2);
  });

  test("未分類明細はnullカテゴリのバケットに集計される", () => {
    const breakdown = classifyReceiptBreakdown({
      merchantRaw: "セブンイレブン",
      items: ["おにぎり", "謎の物体"]
    });

    const result = allocateAmountsByCategory(breakdown, 1000, { perItemAmounts: [400, 600] });

    const unclassified = result.allocations.find((a) => a.category === null);
    expect(unclassified?.amount).toBe(600);
    expect(unclassified?.itemTexts).toEqual(["謎の物体"]);
    expect(result.unclassifiedAmount).toBe(600);
  });

  test("明細が空ならallocations=[]でunclassifiedAmount=totalAmount", () => {
    const breakdown = classifyReceiptBreakdown({
      merchantRaw: "Amazon.co.jp",
      items: [],
      totalAmount: 3000
    });

    const result = allocateAmountsByCategory(breakdown, 3000);
    expect(result.allocations).toEqual([]);
    expect(result.unclassifiedAmount).toBe(3000);
  });

  test("同カテゴリ複数明細はマージされて1バケットになる", () => {
    const breakdown = classifyReceiptBreakdown({
      merchantRaw: "セブンイレブン",
      items: ["おにぎり鮭", "おにぎり梅", "牛乳1L"]
    });

    const result = allocateAmountsByCategory(breakdown, 900, { perItemAmounts: [200, 200, 500] });

    expect(result.allocations).toHaveLength(1);
    expect(result.allocations[0].category).toBe("食費");
    expect(result.allocations[0].amount).toBe(900);
    expect(result.allocations[0].itemTexts).toEqual(["おにぎり鮭", "おにぎり梅", "牛乳1L"]);
  });

  test("perItemAmountsの長さが合わなければエラー", () => {
    const breakdown = classifyReceiptBreakdown({
      merchantRaw: "セブンイレブン",
      items: ["おにぎり", "牛乳"]
    });
    expect(() =>
      allocateAmountsByCategory(breakdown, 500, { perItemAmounts: [500] })
    ).toThrow(/length/);
  });

  test("負のtotalAmountはエラー", () => {
    const breakdown = classifyReceiptBreakdown({
      merchantRaw: "セブンイレブン",
      items: ["おにぎり"]
    });
    expect(() => allocateAmountsByCategory(breakdown, -100)).toThrow(/non-negative/);
  });

  test("均等按分の端数は最後の明細に寄せて合計が一致する", () => {
    const breakdown = classifyReceiptBreakdown({
      merchantRaw: "セブンイレブン",
      items: ["おにぎり鮭", "おにぎり梅", "牛乳1L"]
    });
    const result = allocateAmountsByCategory(breakdown, 100);
    const total = result.allocations.reduce((sum, a) => sum + a.amount, 0);
    expect(total).toBeCloseTo(100, 2);
  });
});
