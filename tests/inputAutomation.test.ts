import { describe, expect, test } from "vitest";
import {
  exportAutomatedClassificationCsv,
  parseReceiptCsv,
  parseReceiptCsvWithDiagnostics,
  manualTransactionToAllocationInput,
  runClassification,
  runManualTransactionInput,
  runClassificationFromCsvRows,
  validateManualTransactionInput,
  validateCsvRowInput
} from "../src/inputAutomation";
import type { ManualTransactionInput } from "../src/types";

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

  test("正常なexpense手入力を受け付ける", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "セブンイレブン 渋谷店",
        purchasedAt: "2026-05-16",
        items: [{ name: "おにぎり", amount: 150, category: "食費" }],
        memo: "昼食"
      })
    ).toBeNull();
  });

  test("正常なincome手入力を受け付ける", () => {
    expect(
      validateManualTransactionInput({
        type: "income",
        merchantRaw: "給与振込",
        purchasedAt: "2026-05-16",
        items: [{ name: "5月給与", amount: 300000 }]
      })
    ).toBeNull();
  });

  test("merchantRaw空を拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "   ",
        purchasedAt: "2026-05-16",
        items: [{ name: "おにぎり", amount: 150 }]
      })
    ).toBe("missing_merchant");
  });

  test("purchasedAt不正形式を拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026/05/16",
        items: [{ name: "商品", amount: 100 }]
      })
    ).toBe("invalid_purchased_at");
  });

  test("存在しない日付を拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-02-30",
        items: [{ name: "商品", amount: 100 }]
      })
    ).toBe("invalid_purchased_at");
  });

  test("items空配列を拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-05-16",
        items: []
      })
    ).toBe("missing_items");
  });

  test("item.name空を拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-05-16",
        items: [{ name: "   ", amount: 100 }]
      })
    ).toBe("missing_item_name");
  });

  test("amountが0の場合に拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-05-16",
        items: [{ name: "商品", amount: 0 }]
      })
    ).toBe("invalid_item_amount");
  });

  test("amountが負数の場合に拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-05-16",
        items: [{ name: "商品", amount: -1 }]
      })
    ).toBe("invalid_item_amount");
  });

  test("amountがNaNの場合に拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-05-16",
        items: [{ name: "商品", amount: Number.NaN }]
      })
    ).toBe("invalid_item_amount");
  });

  test("amountがInfinityの場合に拒否する", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-05-16",
        items: [{ name: "商品", amount: Number.POSITIVE_INFINITY }]
      })
    ).toBe("invalid_item_amount");
  });

  test("無効カテゴリを拒否する", () => {
    const invalidCategoryInput = {
      type: "expense",
      merchantRaw: "店舗",
      purchasedAt: "2026-05-16",
      items: [{ name: "商品", amount: 100, category: "無効カテゴリ" }]
    } as any;

    expect(validateManualTransactionInput(invalidCategoryInput)).toBe("invalid_item_category");
  });

  test("定義済みカテゴリを受け付ける", () => {
    expect(
      validateManualTransactionInput({
        type: "expense",
        merchantRaw: "店舗",
        purchasedAt: "2026-05-16",
        items: [{ name: "商品", amount: 100, category: "日用品" }]
      })
    ).toBeNull();
  });

  test("valid expense manual transaction を AllocationInput に変換できる", () => {
    const result = manualTransactionToAllocationInput({
      type: "expense",
      merchantRaw: "セブンイレブン 渋谷店",
      purchasedAt: "2026-05-16",
      items: [{ name: "おにぎり", amount: 120, category: "食費" }]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.id).toBe("manual-2026-05-16-セブンイレブン 渋谷店");
    }
  });

  test("amount が明細合計になる", () => {
    const result = manualTransactionToAllocationInput({
      type: "expense",
      merchantRaw: "店舗A",
      purchasedAt: "2026-05-16",
      items: [
        { name: "商品1", amount: 100, category: "日用品" },
        { name: "商品2", amount: 230, category: "日用品" }
      ]
    });

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.amount).toBe(330);
  });

  test("purchasedAt が維持される", () => {
    const result = manualTransactionToAllocationInput({
      type: "expense",
      merchantRaw: "店舗A",
      purchasedAt: "2026-05-20",
      items: [{ name: "商品", amount: 200, category: "日用品" }]
    });

    expect(result.ok).toBe(true);
    if (result.ok) expect(result.value.purchasedAt).toBe("2026-05-20");
  });

  test("全明細が同一カテゴリなら、そのカテゴリになり needsReview false になる", () => {
    const result = manualTransactionToAllocationInput({
      type: "expense",
      merchantRaw: "店舗A",
      purchasedAt: "2026-05-16",
      items: [
        { name: "商品1", amount: 100, category: "交通" },
        { name: "商品2", amount: 200, category: "交通" }
      ]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.category).toBe("交通");
      expect(result.value.needsReview).toBe(false);
    }
  });

  test("カテゴリ未指定明細がある場合、category は その他 になり needsReview true になる", () => {
    const result = manualTransactionToAllocationInput({
      type: "expense",
      merchantRaw: "店舗A",
      purchasedAt: "2026-05-16",
      items: [
        { name: "商品1", amount: 100, category: "食費" },
        { name: "商品2", amount: 200 }
      ]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.category).toBe("その他");
      expect(result.value.needsReview).toBe(true);
    }
  });

  test("複数カテゴリが混在する場合、category は その他 になり needsReview true になる", () => {
    const result = manualTransactionToAllocationInput({
      type: "expense",
      merchantRaw: "店舗A",
      purchasedAt: "2026-05-16",
      items: [
        { name: "商品1", amount: 100, category: "食費" },
        { name: "商品2", amount: 200, category: "日用品" }
      ]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.value.category).toBe("その他");
      expect(result.value.needsReview).toBe(true);
    }
  });

  test("income は変換できず ok false になる", () => {
    const result = manualTransactionToAllocationInput({
      type: "income",
      merchantRaw: "給与振込",
      purchasedAt: "2026-05-16",
      items: [{ name: "5月給与", amount: 300000, category: "その他" }]
    });

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toBe("UNSUPPORTED_TRANSACTION_TYPE");
  });

  test("validateManualTransactionInput に失敗する入力は変換されない", () => {
    const result = manualTransactionToAllocationInput({
      type: "expense",
      merchantRaw: "  ",
      purchasedAt: "2026-05-16",
      items: [{ name: "商品", amount: 100, category: "食費" }]
    });

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toBe("missing_merchant");
  });

  test("valid expense manual transaction を runManualTransactionInput で処理できる", () => {
    const result = runManualTransactionInput({
      type: "expense",
      merchantRaw: "店舗B",
      purchasedAt: "2026-05-18",
      items: [{ name: "商品", amount: 500, category: "日用品" }]
    });

    expect(result.ok).toBe(true);
  });

  test("成功時に allocationInput を返す", () => {
    const result = runManualTransactionInput({
      type: "expense",
      merchantRaw: "店舗B",
      purchasedAt: "2026-05-18",
      items: [{ name: "商品", amount: 500, category: "日用品" }]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.allocationInput.amount).toBe(500);
      expect(result.allocationInput.items).toEqual(["商品"]);
    }
  });

  test("成功時の needsReview が allocationInput.needsReview と一致する", () => {
    const result = runManualTransactionInput({
      type: "expense",
      merchantRaw: "店舗B",
      purchasedAt: "2026-05-18",
      items: [{ name: "商品", amount: 500, category: "日用品" }]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.needsReview).toBe(result.allocationInput.needsReview);
    }
  });

  test("カテゴリ未指定明細がある場合、成功するが needsReview true になる", () => {
    const result = runManualTransactionInput({
      type: "expense",
      merchantRaw: "店舗B",
      purchasedAt: "2026-05-18",
      items: [
        { name: "商品1", amount: 300, category: "食費" },
        { name: "商品2", amount: 200 }
      ]
    });

    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.needsReview).toBe(true);
      expect(result.allocationInput.category).toBe("その他");
    }
  });

  test("income は ok false + UNSUPPORTED_TRANSACTION_TYPE になる", () => {
    const result = runManualTransactionInput({
      type: "income",
      merchantRaw: "給与振込",
      purchasedAt: "2026-05-18",
      items: [{ name: "給与", amount: 300000, category: "その他" }]
    });

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toBe("UNSUPPORTED_TRANSACTION_TYPE");
  });

  test("validateManualTransactionInput に失敗する入力は ok false になる", () => {
    const result = runManualTransactionInput({
      type: "expense",
      merchantRaw: "",
      purchasedAt: "2026-05-18",
      items: [{ name: "商品", amount: 500, category: "日用品" }]
    });

    expect(result.ok).toBe(false);
    if (!result.ok) expect(result.error).toBe("missing_merchant");
  });

  test("runManualTransactionInput は manualTransactionToAllocationInput と矛盾しない結果を返す", () => {
    const input: ManualTransactionInput = {
      type: "expense",
      merchantRaw: "店舗B",
      purchasedAt: "2026-05-18",
      items: [{ name: "商品", amount: 500, category: "日用品" }]
    };

    const runResult = runManualTransactionInput(input);
    const converted = manualTransactionToAllocationInput(input);

    expect(runResult.ok).toBe(converted.ok);
    if (runResult.ok && converted.ok) {
      expect(runResult.allocationInput).toEqual(converted.value);
      expect(runResult.needsReview).toBe(converted.value.needsReview);
    }
  });
});
