import { describe, expect, test } from "vitest";
import {
  exportAutomatedClassificationCsv,
  manualTransactionToAllocationInput,
  parseReceiptCsv,
  runManualTransactionInput,
  runClassification,
  runClassificationFromCsvRows,
  validateManualTransactionInput,
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

  test("手入力 expense は実行成功する", () => {
    const result = runManualTransactionInput({
      date: "2026-05-16",
      txType: "expense",
      memo: "セブンイレブン",
      items: [
        { name: "おにぎり", amount: 120 },
        { name: "牛乳", amount: 180 }
      ]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.output.classification.category).toBe("食費");
      expect(result.output.needsReview).toBe(false);
      expect(result.output.allocation.totalAmount).toBe(300);
    }
  });

  test("手入力で needsReview=true の結果を返せる", () => {
    const result = runManualTransactionInput({
      date: "2026-05-16",
      txType: "expense",
      memo: "Amazon",
      items: [{ name: "不明商品", amount: 1200 }]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.output.needsReview).toBe(true);
    }
  });

  test("手入力 income は拒否される", () => {
    const validation = validateManualTransactionInput({
      date: "2026-05-16",
      txType: "income",
      memo: "給与",
      items: [{ name: "振込", amount: 200000 }]
    });
    expect(validation.ok).toBe(true);

    const converted = manualTransactionToAllocationInput({
      date: "2026-05-16",
      txType: "income",
      memo: "給与",
      items: [{ name: "振込", amount: 200000 }]
    });
    expect(converted.ok).toBe(false);
    if (!converted.ok) {
      expect(converted.error).toBe("income_not_supported");
    }

    const result = runManualTransactionInput({
      date: "2026-05-16",
      txType: "income",
      memo: "給与",
      items: [{ name: "振込", amount: 200000 }]
    });
    expect(result.ok).toBe(false);
    if (!result.ok) {
      expect(result.error).toBe("income_not_supported");
    }
  });

  test("手入力の日付不正または未入力は失敗する", () => {
    const missingDate = validateManualTransactionInput({
      date: "",
      txType: "expense",
      items: [{ name: "パン", amount: 100 }]
    });
    expect(missingDate.ok).toBe(false);
    if (!missingDate.ok) expect(missingDate.error).toBe("missing_date");

    const invalidDate = validateManualTransactionInput({
      date: "2026/05/16",
      txType: "expense",
      items: [{ name: "パン", amount: 100 }]
    });
    expect(invalidDate.ok).toBe(false);
    if (!invalidDate.ok) expect(invalidDate.error).toBe("invalid_date");
  });

  test("手入力 items空は失敗する", () => {
    const result = runManualTransactionInput({
      date: "2026-05-16",
      txType: "expense",
      items: []
    });
    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toBe("missing_items");
  });

  test("手入力 amount不正は失敗する", () => {
    const zero = runManualTransactionInput({
      date: "2026-05-16",
      txType: "expense",
      items: [{ name: "パン", amount: 0 }]
    });
    expect(zero.ok).toBe(false);
    if (!zero.ok) expect(zero.error).toBe("invalid_item_amount");

    const notFinite = runManualTransactionInput({
      date: "2026-05-16",
      txType: "expense",
      items: [{ name: "パン", amount: Number.NaN }]
    });
    expect(notFinite.ok).toBe(false);
    if (!notFinite.ok) expect(notFinite.error).toBe("invalid_item_amount");
  });

  test("manualTransactionToAllocationInput と runManualTransactionInput の整合", () => {
    const input = {
      date: "2026-05-16",
      txType: "expense" as const,
      memo: "セブンイレブン",
      items: [{ name: "サンドイッチ", amount: 320 }]
    };

    const converted = manualTransactionToAllocationInput(input);
    expect(converted.ok).toBe(true);
    if (converted.ok) {
      expect(converted.value.totalAmount).toBe(320);
      expect(converted.value.receiptInput.purchasedAt).toBe("2026-05-16");
      expect(converted.value.receiptInput.items).toEqual(["サンドイッチ"]);
    }

    const executed = runManualTransactionInput(input);
    expect(executed.ok).toBe(true);
    if (executed.ok) {
      expect(executed.output.allocation.totalAmount).toBe(320);
    }
  });
});
