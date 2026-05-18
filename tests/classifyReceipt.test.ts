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
    expect(result.reasons).toContain("merchant_rule: セブンイレブン");
  });

  test("店舗名ルールは明細キーワードより優先される", () => {
    const result = classifyReceipt({
      merchantRaw: "マツモトキヨシ 新宿店",
      items: ["おにぎり"],
      totalAmount: 480
    });

    expect(result.category).toBe("日用品");
    expect(result.reason).toBe("rule_match: 日用品");
    expect(result.reasons).toEqual(["merchant_rule: マツモトキヨシ"]);
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

  test("店舗名ルールがない場合は明細キーワードで分類する", () => {
    const result = classifyReceipt({
      merchantRaw: "不明店舗",
      items: ["ガソリン"],
      totalAmount: 3000
    });

    expect(result.category).toBe("交通");
    expect(result.needsReview).toBe(false);
    expect(result.reasons).toEqual(["item_keyword: ガソリン"]);
  });

  test("Amazonは明細なしなら要確認にする", () => {
    const result = classifyReceipt({
      merchantRaw: "Amazon.co.jp",
      items: [],
      totalAmount: 3000
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
    expect(result.reasons).toEqual(["ambiguous_merchant_no_items"]);
  });

  test("Amazonは明細ありなら通常ルールで分類する", () => {
    const result = classifyReceipt({
      merchantRaw: "Amazon.co.jp",
      items: ["イヤホン"],
      totalAmount: 3000
    });

    expect(result.category).toBe("通信");
    expect(result.needsReview).toBe(false);
    expect(result.reason).toBe("rule_match: 通信");
  });

  test("分類ルールがなければ要確認", () => {
    const result = classifyReceipt({
      merchantRaw: "未知の店舗",
      items: ["未知の品目"],
      totalAmount: 1000
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
    expect(result.reason).toBe("no rule matched");
  });

  test("ドン・キホーテ表記も危険店舗として明細なし要確認", () => {
    const result = classifyReceipt({
      merchantRaw: "ドン・キホーテ",
      items: [],
      totalAmount: 1980
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
    expect(result.reason).toBe("ambiguous merchant without items");
  });

  test("イオンは明細ありなら明細キーワードで分類する", () => {
    const result = classifyReceipt({
      merchantRaw: "イオン",
      items: ["ティッシュ"],
      totalAmount: 420
    });

    expect(result.category).toBe("日用品");
    expect(result.needsReview).toBe(false);
    expect(result.reason).toBe("rule_match: 日用品");
  });

  test("明細キーワードの交通系表記ゆれを分類できる", () => {
    const result = classifyReceipt({
      merchantRaw: "不明店舗",
      items: ["電車"],
      totalAmount: 180
    });

    expect(result.category).toBe("交通");
    expect(result.needsReview).toBe(false);
    expect(result.reasons).toEqual(["item_keyword: 電車"]);
  });

});
