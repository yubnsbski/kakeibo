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
    expect(result.screeningLabel).toBe("recordable");
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
    expect(result.screeningLabel).toBe("needs_review");
  });

  test("Amazonは明細ありでも手動分類前提なので要確認", () => {
    const result = classifyReceipt({
      merchantRaw: "Amazon.co.jp",
      items: ["イヤホン"],
      totalAmount: 3000
    });

    expect(result.category).toBeNull();
    expect(result.needsReview).toBe(true);
    expect(result.reason).toBe("ambiguous merchant requires manual category");
  });


  test("confidenceは自動分類0.9・曖昧明細あり0.4・要確認0を返す", () => {
    const auto = classifyReceipt({
      merchantRaw: "セブンイレブン 渋谷店",
      items: ["牛乳"],
      totalAmount: 300
    });
    const ambiguous = classifyReceipt({
      merchantRaw: "Amazon.co.jp",
      items: ["イヤホン"],
      totalAmount: 3000
    });
    const noMatch = classifyReceipt({
      merchantRaw: "未知の店舗",
      items: [""],
      totalAmount: 1000
    });

    expect(auto.confidence).toBe(0.9);
    expect(ambiguous.confidence).toBe(0.4);
    expect(noMatch.confidence).toBe(0);
  });

  test("明細の前後空白は除去してキーワード判定する", () => {
    const result = classifyReceipt({
      merchantRaw: "不明店舗",
      items: ["  ガソリン  ", "   "],
      totalAmount: 3000
    });

    expect(result.category).toBe("交通");
    expect(result.needsReview).toBe(false);
    expect(result.reasons).toEqual(["item_keyword: ガソリン"]);
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
    expect(result.screeningLabel).toBe("needs_review");
  });
});
