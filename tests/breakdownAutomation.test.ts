import { describe, expect, test } from "vitest";
import {
  exportBreakdownClassificationCsv,
  parseReceiptCsv,
  runBreakdownClassificationFromCsvRows
} from "../src/inputAutomation";

describe("breakdown classification pipeline", () => {
  test("混在レシートはカテゴリごとに1行ずつ出力する", () => {
    const csv = [
      "receipt_id,merchantRaw,items,totalAmount,purchasedAt",
      "r001,FamilyMart,ミルクの束縛ミルクCO|雑誌書籍,408,2026-05-04"
    ].join("\n");

    const rows = parseReceiptCsv(csv);
    const result = runBreakdownClassificationFromCsvRows(rows, {
      additionalKeywordRules: { ミルク: "食費", 書籍: "教育", 雑誌: "教育" }
    });

    expect(result).toHaveLength(2);
    const food = result.find((r) => r.category === "食費");
    const education = result.find((r) => r.category === "教育");
    expect(food?.amount).toBeCloseTo(204, 2);
    expect(education?.amount).toBeCloseTo(204, 2);
    expect(food?.is_mixed).toBe("yes");
    expect(education?.is_mixed).toBe("yes");
  });

  test("税率ヒント付きで未知明細を食費に寄せる", () => {
    const csv = [
      "receipt_id,merchantRaw,items,totalAmount,purchasedAt",
      "r002,FamilyMart,ミルクの束縛ミルクCO|雑誌書籍,408,2026-05-04"
    ].join("\n");

    const rows = parseReceiptCsv(csv);
    const result = runBreakdownClassificationFromCsvRows(rows, {
      additionalKeywordRules: { 書籍: "教育", 雑誌: "教育" },
      perItemTaxRateHints: ["reduced", "standard"]
    });

    const food = result.find((r) => r.category === "食費");
    const education = result.find((r) => r.category === "教育");
    expect(food).toBeDefined();
    expect(education).toBeDefined();
  });

  test("単一カテゴリのレシートは1行・is_mixed=no", () => {
    const csv = [
      "receipt_id,merchantRaw,items,totalAmount,purchasedAt",
      "r003,セブンイレブン,おにぎり|牛乳,500,2026-05-16"
    ].join("\n");

    const rows = parseReceiptCsv(csv);
    const result = runBreakdownClassificationFromCsvRows(rows);

    expect(result).toHaveLength(1);
    expect(result[0].category).toBe("食費");
    expect(result[0].amount).toBe(500);
    expect(result[0].is_mixed).toBe("no");
  });

  test("バリデーションエラー行はREVIEWで1行出力", () => {
    const csv = [
      "receipt_id,merchantRaw,items,totalAmount,purchasedAt",
      "r004,,おにぎり,500,2026-05-16"
    ].join("\n");

    const rows = parseReceiptCsv(csv);
    const result = runBreakdownClassificationFromCsvRows(rows);

    expect(result).toHaveLength(1);
    expect(result[0].category).toBe("REVIEW");
    expect(result[0].reason).toBe("missing_merchant");
  });

  test("exportBreakdownClassificationCsvはヘッダー固定でTSV互換を出す", () => {
    const csv = exportBreakdownClassificationCsv([
      {
        receipt_id: "r001",
        merchant_normalized: "FamilyMart",
        category: "食費",
        item_texts: "ミルク",
        amount: 228,
        is_mixed: "yes",
        purchased_at: "2026-05-04",
        reason: "mixed_receipt_split"
      }
    ]);
    expect(csv.split("\n")[0]).toBe(
      "receipt_id,merchant_normalized,category,item_texts,amount,is_mixed,purchased_at,reason"
    );
    expect(csv.split("\n")[1]).toContain("FamilyMart");
  });
});
