import { describe, expect, test } from "vitest";
import {
  exportAutomatedClassificationCsv,
  parseReceiptCsv,
  parseReceiptCsvWithDiagnostics,
  runClassification,
  runClassificationFromCsvRows,
  validateCsvRowInput
} from "../src/inputAutomation";

describe("inputAutomation", () => {
  test("CSV入力を自動分類して3ケースを通す（セブン/Amazon明細なし/no rule matched）", () => {
    const csv = [
      "receipt_id,merchantRaw,items,totalAmount,purchasedAt",
      "r001,セブンイレブン,おにぎり|牛乳,450,2026-05-16",
      "r002,Amazon,,3980,2026-05-16",
      "r003,未知の店舗,未知の商品,1200,2026-05-16"
    ].join("\n");

    const rows = parseReceiptCsv(csv);
    const result = runClassificationFromCsvRows(rows);

    expect(result[0].category).toBe("食費");
    expect(result[0].needs_review).toBe("no");

    expect(result[1].category).toBe("REVIEW");
    expect(result[1].needs_review).toBe("yes");
    expect(result[1].reason).toBe("ambiguous merchant without items");

    expect(result[2].category).toBe("REVIEW");
    expect(result[2].needs_review).toBe("yes");
    expect(result[2].reason).toBe("no rule matched");
  });

  test("単票runClassificationで入力エラーを返す", () => {
    const bad = runClassification({
      merchantRaw: "",
      items: ["おにぎり"],
      totalAmount: 100,
      purchasedAt: "2026-05-16"
    });

    expect(bad.ok).toBe(false);
    if (!bad.ok) {
      expect(bad.error).toBe("missing_merchant");
      expect(bad.message).toContain("店舗名");
    }
  });

  test("入力チェック（店舗名必須・金額>0・日付形式）", () => {
    expect(
      validateCsvRowInput({
        receipt_id: "x1",
        merchantRaw: "",
        items: [],
        totalAmount: 100,
        purchasedAt: "2026-05-16"
      })
    ).toBe("missing_merchant");

    expect(
      validateCsvRowInput({
        receipt_id: "x2",
        merchantRaw: "店舗",
        items: [],
        totalAmount: 0,
        purchasedAt: "2026-05-16"
      })
    ).toBe("invalid_total_amount");

    expect(
      validateCsvRowInput({
        receipt_id: "x3",
        merchantRaw: "店舗",
        items: [],
        totalAmount: 100,
        purchasedAt: "2026/05/16"
      })
    ).toBe("invalid_purchased_at");
  });

  test("分類結果をresult.csv形式で出力する", () => {
    const csv = [
      "receipt_id,merchantRaw,items,totalAmount,purchasedAt",
      "r001,セブンイレブン,おにぎり|牛乳,450,2026-05-16"
    ].join("\n");
    const rows = parseReceiptCsv(csv);
    const result = runClassificationFromCsvRows(rows);
    const outCsv = exportAutomatedClassificationCsv(result);

    expect(outCsv).toContain(
      "receipt_id,merchant_normalized,items_text,screening_category,needs_review,reason,confidence,amount,purchased_at"
    );
    expect(outCsv).toContain("r001");
    expect(outCsv).toContain("食費");
  });

  test("CSVヘッダー不正でも例外を投げず空配列を返す", () => {
    const invalidHeaderCsv = [
      "id,merchant,items,total,date",
      "r001,セブンイレブン,おにぎり|牛乳,450,2026-05-16"
    ].join("\n");

    expect(() => parseReceiptCsv(invalidHeaderCsv)).not.toThrow();
    expect(parseReceiptCsv(invalidHeaderCsv)).toEqual([]);
    expect(parseReceiptCsvWithDiagnostics(invalidHeaderCsv).error).toBe("invalid_header");
  });

  test("CSVヘッダーのBOM/空白/大文字小文字ゆれを許容する", () => {
    const csv = [
      "\uFEFF receipt_id, merchantRaw, items, totalAmount, purchasedAt ",
      "r001,セブンイレブン,おにぎり|牛乳,450,2026-05-16"
    ].join("\n");

    const rows = parseReceiptCsv(csv);
    expect(rows).toHaveLength(1);
    expect(rows[0].merchantRaw).toBe("セブンイレブン");
  });

  test("金額列は通貨記号・桁区切り・全角数字を含んでも数値化される", () => {
    const csv = [
      "receipt_id,merchantRaw,items,totalAmount,purchasedAt",
      "r001,セブンイレブン,おにぎり,¥1,280,2026-05-16",
      "r002,ローソン,牛乳,￥２,０００,2026-05-16",
      "r003,ファミマ,パン,\t 980 ,2026-05-16"
    ].join("\n");

    const rows = parseReceiptCsv(csv);
    expect(rows[0].totalAmount).toBe(1280);
    expect(rows[1].totalAmount).toBe(2000);
    expect(rows[2].totalAmount).toBe(980);
  });
});
