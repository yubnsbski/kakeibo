import { describe, expect, test } from "vitest";
import { classifyReceiptBreakdown, summarizeItemsByCategory } from "../src/classifyReceiptBreakdown";

describe("classifyReceiptBreakdown", () => {
  test("FamilyMartの混在レシート（ミルク+雑誌書籍）を明細ごとに分類する", () => {
    const result = classifyReceiptBreakdown(
      {
        merchantRaw: "FamilyMart 船橋海神二丁目店",
        items: ["ミルクの束縛ミルクCO", "雑誌書籍"],
        totalAmount: 408,
        purchasedAt: "2026-05-04"
      },
      {
        additionalKeywordRules: { ミルク: "食費", 書籍: "教育", 雑誌: "教育" }
      }
    );

    expect(result.items).toHaveLength(2);
    expect(result.items[0].category).toBe("食費");
    expect(result.items[1].category).toBe("教育");
    expect(result.isMixed).toBe(true);
    expect(result.dominantCategory).toBeNull();
    expect(result.needsReview).toBe(true);
  });

  test("全明細が同一カテゴリならdominantCategoryが定まりneedsReview=false", () => {
    const result = classifyReceiptBreakdown({
      merchantRaw: "セブンイレブン 渋谷店",
      items: ["おにぎり鮭", "おにぎり梅", "牛乳1L"],
      totalAmount: 800
    });

    expect(result.dominantCategory).toBe("食費");
    expect(result.isMixed).toBe(false);
    expect(result.needsReview).toBe(false);
  });

  test("分類できない明細が含まれていればneedsReview=true", () => {
    const result = classifyReceiptBreakdown({
      merchantRaw: "セブンイレブン",
      items: ["おにぎり鮭", "謎の物体"],
      totalAmount: 500
    });

    expect(result.items[1].category).toBeNull();
    expect(result.needsReview).toBe(true);
  });

  test("明細が空ならneedsReview=true・dominantCategory=null", () => {
    const result = classifyReceiptBreakdown({
      merchantRaw: "Amazon.co.jp",
      items: [],
      totalAmount: 3000
    });

    expect(result.items).toEqual([]);
    expect(result.dominantCategory).toBeNull();
    expect(result.needsReview).toBe(true);
  });

  test("merchantNormalizedはnormalizeMerchantを通る", () => {
    const result = classifyReceiptBreakdown({
      merchantRaw: "ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
      items: ["おにぎり"]
    });
    expect(result.merchantNormalized).toContain("セブンイレブン");
  });

  test("perItemTaxRateHintsで税率を伝搬し、軽減税率の未知明細を食費にフォールバックする", () => {
    const result = classifyReceiptBreakdown(
      {
        merchantRaw: "FamilyMart",
        items: ["ミルクの束縛ミルクCO", "雑誌書籍"]
      },
      {
        additionalKeywordRules: { 書籍: "教育" },
        perItemTaxRateHints: ["reduced", "standard"]
      }
    );

    expect(result.items[0].category).toBe("食費");
    expect(result.items[0].reason).toBe("tax_rate_hint: reduced→食費");
    expect(result.items[1].category).toBe("教育");
  });

  test("perItemTaxRateHintsの長さがitemsと合わなければエラー", () => {
    expect(() =>
      classifyReceiptBreakdown(
        { merchantRaw: "FamilyMart", items: ["a", "b"] },
        { perItemTaxRateHints: ["reduced"] }
      )
    ).toThrow(/length/);
  });

  test("summarizeItemsByCategoryはカテゴリ別にグルーピングする", () => {
    const breakdown = classifyReceiptBreakdown(
      {
        merchantRaw: "FamilyMart",
        items: ["ミルク", "雑誌書籍"]
      },
      { additionalKeywordRules: { ミルク: "食費", 書籍: "教育", 雑誌: "教育" } }
    );

    const summary = summarizeItemsByCategory(breakdown);
    const foodGroup = summary.find((s) => s.category === "食費");
    const educationGroup = summary.find((s) => s.category === "教育");
    expect(foodGroup?.itemTexts).toEqual(["ミルク"]);
    expect(educationGroup?.itemTexts).toEqual(["雑誌書籍"]);
  });
});
