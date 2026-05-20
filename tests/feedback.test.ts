import { describe, expect, test } from "vitest";
import { mergeLabeledExamples, toLabeledExamples } from "../src/feedback";
import type { LabeledExample } from "../src/keywordMiner";

describe("toLabeledExamples", () => {
  test("確認済みレビュー結果をLabeledExample形式に変換する", () => {
    const result = toLabeledExamples([
      {
        source: "familymart_2026-05-04",
        confirmedItems: [
          { text: "ミルクの束縛ミルクCO", confirmedCategory: "食費" },
          { text: "雑誌書籍", confirmedCategory: "教育" }
        ]
      }
    ]);

    expect(result).toEqual([
      {
        source: "familymart_2026-05-04",
        items: [
          { text: "ミルクの束縛ミルクCO", category: "食費" },
          { text: "雑誌書籍", category: "教育" }
        ]
      }
    ]);
  });

  test("空テキストの確認項目はスキップする", () => {
    const result = toLabeledExamples([
      {
        source: "r001",
        confirmedItems: [
          { text: "  ", confirmedCategory: "食費" },
          { text: "おにぎり", confirmedCategory: "食費" }
        ]
      }
    ]);
    expect(result[0].items).toEqual([{ text: "おにぎり", category: "食費" }]);
  });

  test("有効な明細がゼロのレビューは除外される", () => {
    const result = toLabeledExamples([
      { source: "empty", confirmedItems: [{ text: "  ", confirmedCategory: "食費" }] }
    ]);
    expect(result).toEqual([]);
  });
});

describe("mergeLabeledExamples", () => {
  test("同一sourceは明細を統合・重複は除去する", () => {
    const existing: LabeledExample[] = [
      {
        source: "familymart_2026-05-04",
        items: [{ text: "ミルクの束縛ミルクCO", category: "食費" }]
      }
    ];

    const additions: LabeledExample[] = [
      {
        source: "familymart_2026-05-04",
        items: [
          { text: "ミルクの束縛ミルクCO", category: "食費" },
          { text: "雑誌書籍", category: "教育" }
        ]
      }
    ];

    const merged = mergeLabeledExamples(existing, additions);
    const target = merged.find((e) => e.source === "familymart_2026-05-04");
    expect(target?.items).toEqual([
      { text: "ミルクの束縛ミルクCO", category: "食費" },
      { text: "雑誌書籍", category: "教育" }
    ]);
  });

  test("異なるsourceは別エントリとして追加される", () => {
    const existing: LabeledExample[] = [{ source: "a", items: [{ text: "おにぎり", category: "食費" }] }];
    const additions: LabeledExample[] = [{ source: "b", items: [{ text: "本", category: "教育" }] }];

    const merged = mergeLabeledExamples(existing, additions);
    expect(merged.map((e) => e.source).sort()).toEqual(["a", "b"]);
  });

  test("source未指定は常に追記扱い", () => {
    const merged = mergeLabeledExamples(
      [{ items: [{ text: "x", category: "食費" }] }],
      [{ items: [{ text: "y", category: "日用品" }] }]
    );
    expect(merged).toHaveLength(2);
  });

  test("入力配列を変更しない（イミュータブル）", () => {
    const existing: LabeledExample[] = [
      { source: "a", items: [{ text: "おにぎり", category: "食費" }] }
    ];
    const additions: LabeledExample[] = [
      { source: "a", items: [{ text: "牛乳", category: "食費" }] }
    ];
    const snapshot = JSON.stringify(existing);
    mergeLabeledExamples(existing, additions);
    expect(JSON.stringify(existing)).toBe(snapshot);
  });
});
