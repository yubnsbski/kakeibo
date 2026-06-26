import { describe, expect, test } from "vitest";
import {
  isZeroAmountPreview,
  optimisticAmountPreview,
} from "../frontend/src/crypto/calculatorPreview.js";

describe("calculator immediate preview", () => {
  test("0円スタートを税込・税抜とも表示できる", () => {
    const included = optimisticAmountPreview("0", 10, "tax_included");
    const excluded = optimisticAmountPreview("0", 10, "tax_excluded");

    expect(included).toEqual({
      amount: 0,
      net_amount: 0,
      tax_rate: 10,
      tax_amount: 0,
      input_amount: 0,
      amount_mode: "tax_included",
    });
    expect(excluded).toEqual({
      amount: 0,
      net_amount: 0,
      tax_rate: 10,
      tax_amount: 0,
      input_amount: 0,
      amount_mode: "tax_excluded",
    });
    expect(isZeroAmountPreview(included)).toBe(true);
  });

  test("単純な数字入力はバックエンド応答前に税込内訳を表示できる", () => {
    expect(optimisticAmountPreview("1100", 10, "tax_included")).toEqual({
      amount: 1100,
      net_amount: 1000,
      tax_rate: 10,
      tax_amount: 100,
      input_amount: 1100,
      amount_mode: "tax_included",
    });
  });

  test("税抜入力は税込支払額を即時表示できる", () => {
    expect(optimisticAmountPreview("1000", 10, "tax_excluded")).toEqual({
      amount: 1100,
      net_amount: 1000,
      tax_rate: 10,
      tax_amount: 100,
      input_amount: 1000,
      amount_mode: "tax_excluded",
    });
  });

  test("演算式はバックエンド計算へ委ねる", () => {
    expect(optimisticAmountPreview("1000+100", 10, "tax_included")).toBeNull();
    expect(optimisticAmountPreview("", 10, "tax_included")).toBeNull();
  });
});
