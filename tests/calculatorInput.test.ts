import { describe, expect, test } from "vitest";
import { applyCalculatorCommand } from "../frontend/src/crypto/calculatorInput.js";

describe("calculator keypad input", () => {
  test("初期0を数字で置換する", () => {
    expect(applyCalculatorCommand("0", "7")).toBe("7");
    expect(applyCalculatorCommand("0", "00")).toBe("0");
  });

  test("数字と演算子を順番に追加する", () => {
    let expression = "0";
    for (const command of ["1", "2", "+", "3", "0"] as const) {
      expression = applyCalculatorCommand(expression, command);
    }
    expect(expression).toBe("12+30");
  });

  test("連続する演算子は最後の演算子へ置換する", () => {
    expect(applyCalculatorCommand("12+", "*")).toBe("12*");
  });

  test("同じ数値内の小数点は1つだけにする", () => {
    expect(applyCalculatorCommand("12.3", ".")).toBe("12.3");
    expect(applyCalculatorCommand("12+", ".")).toBe("12+0.");
  });

  test("括弧と暗黙の乗算を扱う", () => {
    expect(applyCalculatorCommand("0", "(")).toBe("(");
    expect(applyCalculatorCommand("2", "(")).toBe("2*(");
    expect(applyCalculatorCommand("(12", ")")).toBe("(12)");
    expect(applyCalculatorCommand("12", ")")).toBe("12");
  });

  test("削除とクリアを扱う", () => {
    expect(applyCalculatorCommand("123", "backspace")).toBe("12");
    expect(applyCalculatorCommand("1", "backspace")).toBe("0");
    expect(applyCalculatorCommand("123", "clear")).toBe("0");
  });
});
