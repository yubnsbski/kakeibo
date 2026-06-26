import { describe, expect, test } from "vitest";
import {
  assertLineItemTotal,
  buildManualLineItems,
  emptyLineItemDraft,
  lineItemTotal,
} from "../frontend/src/crypto/lineItems.js";

describe("manual line item helpers", () => {
  test("明細が空なら取引金額とカテゴリから1件生成する", () => {
    expect(
      buildManualLineItems([], {
        totalAmount: 750,
        fallbackName: "スーパー",
        fallbackCategory: "食費",
        memo: "テスト",
      }),
    ).toEqual([
      {
        name: "スーパー",
        amount: 750,
        category: "食費",
        memo: "テスト",
      },
    ]);
  });

  test("複数明細を保存できる", () => {
    const items = buildManualLineItems(
      [
        { name: "パン", amount: "200", category: "食費" },
        { name: "洗剤", amount: "500", category: "日用品" },
      ],
      {
        totalAmount: 700,
        fallbackName: "店舗",
        fallbackCategory: "その他",
      },
    );

    expect(lineItemTotal(items)).toBe(700);
    expect(items).toHaveLength(2);
  });

  test("割引はマイナス明細として合計できる", () => {
    const items = buildManualLineItems(
      [
        { name: "商品", amount: "1000", category: "日用品" },
        { name: "割引", amount: "-100", category: "日用品" },
      ],
      {
        totalAmount: 900,
        fallbackName: "店舗",
        fallbackCategory: "日用品",
      },
    );

    expect(lineItemTotal(items)).toBe(900);
  });

  test("明細合計が取引金額と違えば保存を止める", () => {
    expect(() =>
      assertLineItemTotal(
        [
          { amount: 400 },
          { amount: 500 },
        ],
        1000,
      ),
    ).toThrow("一致しません");
  });

  test("品目名と整数金額を検証する", () => {
    expect(() =>
      buildManualLineItems(
        [{ name: "", amount: "100", category: "食費" }],
        {
          totalAmount: 100,
          fallbackName: "店舗",
          fallbackCategory: "食費",
        },
      ),
    ).toThrow("品目名");

    expect(() =>
      buildManualLineItems(
        [{ name: "商品", amount: "10.5", category: "食費" }],
        {
          totalAmount: 11,
          fallbackName: "店舗",
          fallbackCategory: "食費",
        },
      ),
    ).toThrow("整数");
  });

  test("新規明細は指定カテゴリと既定0円で初期化する", () => {
    expect(emptyLineItemDraft("食費")).toEqual({
      name: "",
      amount: "0",
      category: "食費",
    });
  });

  test("最初の明細へ計算結果を初期値として渡せる", () => {
    expect(emptyLineItemDraft("食費", 1100)).toEqual({
      name: "",
      amount: "1100",
      category: "食費",
    });
  });

  test("明細の初期金額は整数だけを許可する", () => {
    expect(() => emptyLineItemDraft("食費", 10.5)).toThrow("整数");
  });
});
