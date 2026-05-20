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
});
