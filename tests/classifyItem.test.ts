import { describe, expect, test } from "vitest";
import { classifyItem } from "../src/classifyItem";

describe("classifyItem", () => {
  test("既存itemKeywordRulesで明細を分類する", () => {
    const result = classifyItem("おにぎり鮭");
    expect(result.category).toBe("食費");
    expect(result.matchedKeyword).toBe("おにぎり");
    expect(result.reason).toBe("item_keyword: おにぎり");
  });

  test("ルール未マッチは category=null になる", () => {
    const result = classifyItem("謎の物体");
    expect(result.category).toBeNull();
    expect(result.matchedKeyword).toBeNull();
    expect(result.reason).toBe("no_keyword_matched");
  });

  test("additionalKeywordRulesで実行時にキーワード追加できる", () => {
    const result = classifyItem("雑誌書籍", {
      additionalKeywordRules: { 書籍: "教育", 雑誌: "教育" }
    });
    expect(result.category).toBe("教育");
    expect(result.matchedKeyword).toBe("書籍");
  });

  test("複数キーワードがマッチしたら最長一致を採用する", () => {
    const result = classifyItem("おにぎり梅", {
      additionalKeywordRules: { おに: "その他" }
    });
    expect(result.category).toBe("食費");
    expect(result.matchedKeyword).toBe("おにぎり");
  });

  test("空文字列はempty_itemを返す", () => {
    const result = classifyItem("   ");
    expect(result.category).toBeNull();
    expect(result.reason).toBe("empty_item");
  });

  test("税率ヒントreduced+キーワード未マッチなら食費にフォールバックする", () => {
    const result = classifyItem("ミルクの束縛ミルクCO", { taxRateHint: "reduced" });
    expect(result.category).toBe("食費");
    expect(result.reason).toBe("tax_rate_hint: reduced→食費");
    expect(result.matchedKeyword).toBeNull();
  });

  test("キーワード一致が優先され、税率ヒントはフォールバックに留まる", () => {
    const result = classifyItem("シャンプー詰替", { taxRateHint: "reduced" });
    expect(result.category).toBe("日用品");
    expect(result.matchedKeyword).toBe("シャンプー");
  });

  test("税率ヒントstandardだけではフォールバックしない", () => {
    const result = classifyItem("謎の物体", { taxRateHint: "standard" });
    expect(result.category).toBeNull();
    expect(result.reason).toBe("no_keyword_matched");
  });
});
