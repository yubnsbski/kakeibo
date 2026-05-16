import { describe, expect, test } from "vitest";
import { readFileSync } from "node:fs";
import { classifyReceipt } from "../src/classifyReceipt";

describe("classifyReceipt", () => {
  test("セブンイレブンは食費に分類する", () => {
    const result = classifyReceipt({
      merchantRaw: "ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
      items: ["おにぎり", "牛乳"],
      totalAmount: 620
    });

    expect(result.category).toBe("食費");
    expect(result.needsReview).toBe(false);
    expect(result.scores[0]?.category).toBe("食費");
    expect(result.reasons).toContain("merchant_rule: セブンイレブン");
  });

  test("マツモトキヨシは日用品に分類する", () => {
    const result = classifyReceipt({
      merchantRaw: "マツモトキヨシ 新宿店",
      items: ["洗剤"],
      totalAmount: 480
    });

    expect(result.category).toBe("日用品");
    expect(result.needsReview).toBe(false);
  });

  test("ユーザー修正ルールを最優先で適用する", () => {
    const result = classifyReceipt({
      merchantRaw: "Amazon.co.jp",
      items: [],
      userCategoryOverrides: { Amazon: "通信" },
      totalAmount: 3000
    });

    expect(result.category).toBe("通信");
    expect(result.needsReview).toBe(false);
    expect(result.reason).toBe("user_override: 通信");
  });



  test("空のユーザー修正キーは無視する", () => {
    const result = classifyReceipt({
      merchantRaw: "セブンイレブン 渋谷店",
      items: ["おにぎり"],
      userCategoryOverrides: { "   ": "通信", Amazon: "娯楽" },
      totalAmount: 300
    });

    expect(result.category).toBe("食費");
    expect(result.needsReview).toBe(false);
    expect(result.reason).not.toBe("user_override: 通信");
  });

  test("Amazonは明細なしなら要確認にする", () => {
    const result = classifyReceipt({
      merchantRaw: "Amazon.co.jp",
      items: [],
      totalAmount: 3000
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
  });

  test("イオンでカテゴリ拮抗なら要確認にする", () => {
    const result = classifyReceipt({
      merchantRaw: "イオン",
      items: ["牛乳", "洗剤"],
      totalAmount: 980
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
    expect(result.reason).toBe("ambiguous merchant requires review");
  });

  test("evaluation fixtureの期待を満たす", () => {
    const fixture = JSON.parse(
      readFileSync("fixtures/receipts/evaluation.json", "utf-8")
    ) as Array<{
      input: { merchantRaw: string; items?: string[]; totalAmount?: number };
      expected: { category: string | null; needsReview: boolean };
    }>;

    for (const c of fixture) {
      const result = classifyReceipt(c.input);
      expect(result.category).toBe(c.expected.category);
      expect(result.needsReview).toBe(c.expected.needsReview);
    }
  });
});
