import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, expect, test } from "vitest";
import { extractNgrams, mineKeywords, type LabeledExample } from "../src/keywordMiner";

describe("extractNgrams", () => {
  test("指定範囲のn-gramを重複なく抽出する", () => {
    const result = extractNgrams("おにぎり", 2, 3);
    expect(result).toEqual(expect.arrayContaining(["おに", "にぎ", "ぎり", "おにぎ", "にぎり"]));
    expect(new Set(result).size).toBe(result.length);
  });

  test("文字数未満の長さは無視する", () => {
    const result = extractNgrams("薬", 2, 3);
    expect(result).toEqual([]);
  });
});

describe("mineKeywords", () => {
  test("純度の高い明細キーワードをカテゴリ付きで抽出する", () => {
    const examples: LabeledExample[] = [
      { items: [{ text: "おにぎり鮭", category: "食費" }] },
      { items: [{ text: "おにぎり梅", category: "食費" }] },
      { items: [{ text: "シャンプー本体", category: "日用品" }] },
      { items: [{ text: "シャンプー詰替", category: "日用品" }] }
    ];

    const candidates = mineKeywords(examples, { minSupport: 2, minPurity: 1 });

    const onigiri = candidates.find((c) => c.keyword === "おにぎ" || c.keyword === "にぎり");
    const shampoo = candidates.find((c) => c.keyword === "シャン");

    expect(onigiri?.category).toBe("食費");
    expect(shampoo?.category).toBe("日用品");
  });

  test("純度が閾値未満のn-gramは除外する", () => {
    const examples: LabeledExample[] = [
      { items: [{ text: "あいうえ", category: "食費" }] },
      { items: [{ text: "あいうえ", category: "日用品" }] }
    ];

    const candidates = mineKeywords(examples, { minSupport: 1, minPurity: 0.8 });
    expect(candidates).toEqual([]);
  });

  test("既存キーワードは除外する", () => {
    const examples: LabeledExample[] = [
      { items: [{ text: "牛乳1L", category: "食費" }] },
      { items: [{ text: "牛乳パック", category: "食費" }] }
    ];

    const candidates = mineKeywords(examples, {
      minSupport: 2,
      minPurity: 1,
      excludeExistingKeywords: ["牛乳"]
    });

    expect(candidates.find((c) => c.keyword === "牛乳")).toBeUndefined();
  });

  test("FamilyMartレシートの『雑誌書籍』から教育カテゴリ候補が抽出される", () => {
    const filePath = join(__dirname, "..", "fixtures", "training", "labeled-items.json");
    const examples = JSON.parse(readFileSync(filePath, "utf-8")) as LabeledExample[];

    const candidates = mineKeywords(examples, { minSupport: 2, minPurity: 0.8 });
    const educationCandidates = candidates.filter((c) => c.category === "教育");

    expect(educationCandidates.length).toBeGreaterThan(0);
    expect(educationCandidates.some((c) => c.keyword.includes("書籍") || c.keyword.includes("雑誌"))).toBe(true);
  });
});
