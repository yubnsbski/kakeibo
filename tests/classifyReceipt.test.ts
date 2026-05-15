import { describe, expect, test } from "vitest";
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

  test("Amazonは明細なしなら要確認にする", () => {
    const result = classifyReceipt({
      merchantRaw: "Amazon.co.jp",
      items: [],
      totalAmount: 3000
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
  });

  test("未知の店舗は要確認にする", () => {
    const result = classifyReceipt({
      merchantRaw: "知らない店",
      items: [],
      totalAmount: 1000
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
  });
});
