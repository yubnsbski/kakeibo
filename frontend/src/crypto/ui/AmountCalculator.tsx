import { useCallback, useEffect, useRef, useState } from "react";
import type { CSSProperties } from "react";
import {
  calculateAmount,
  type AmountCalculationResponse,
} from "../../api";
import {
  applyCalculatorCommand,
  type CalculatorCommand,
} from "../calculatorInput";

type PreviewStatus =
  | { kind: "idle" }
  | { kind: "loading" }
  | { kind: "success"; result: AmountCalculationResponse }
  | { kind: "error"; message: string };

type AmountCalculatorProps = {
  id: string;
  expression: string;
  taxRate: string;
  disabled?: boolean;
  onExpressionChange: (expression: string) => void;
  onResultChange?: (result: AmountCalculationResponse | null) => void;
};

type KeyDefinition = {
  label: string;
  command: CalculatorCommand;
  kind?: "number" | "operator" | "control";
};

const keypad: KeyDefinition[] = [
  { label: "7", command: "7", kind: "number" },
  { label: "8", command: "8", kind: "number" },
  { label: "9", command: "9", kind: "number" },
  { label: "÷", command: "/", kind: "operator" },
  { label: "4", command: "4", kind: "number" },
  { label: "5", command: "5", kind: "number" },
  { label: "6", command: "6", kind: "number" },
  { label: "×", command: "*", kind: "operator" },
  { label: "1", command: "1", kind: "number" },
  { label: "2", command: "2", kind: "number" },
  { label: "3", command: "3", kind: "number" },
  { label: "−", command: "-", kind: "operator" },
  { label: "00", command: "00", kind: "number" },
  { label: "0", command: "0", kind: "number" },
  { label: ".", command: ".", kind: "number" },
  { label: "+", command: "+", kind: "operator" },
  { label: "(", command: "(", kind: "control" },
  { label: ")", command: ")", kind: "control" },
  { label: "⌫", command: "backspace", kind: "control" },
  { label: "AC", command: "clear", kind: "control" },
];

const panelStyle: CSSProperties = {
  border: "1px solid #d0d7de",
  borderRadius: 14,
  padding: 14,
  background: "#ffffff",
  display: "grid",
  gap: 12,
  maxWidth: 520,
};

const displayStyle: CSSProperties = {
  border: "1px solid #d8dee4",
  borderRadius: 12,
  padding: "14px 16px",
  minHeight: 88,
  background: "#f6f8fa",
  display: "grid",
  alignContent: "center",
  justifyItems: "end",
  gap: 4,
};

const keypadStyle: CSSProperties = {
  display: "grid",
  gridTemplateColumns: "repeat(4, minmax(54px, 1fr))",
  gap: 8,
};

const baseKeyStyle: CSSProperties = {
  minHeight: 48,
  borderRadius: 12,
  border: "1px solid #d0d7de",
  fontSize: "1.1rem",
  fontWeight: 600,
  cursor: "pointer",
};

function keyStyle(kind: KeyDefinition["kind"]): CSSProperties {
  if (kind === "operator") {
    return {
      ...baseKeyStyle,
      background: "#eef2f5",
    };
  }
  if (kind === "control") {
    return {
      ...baseKeyStyle,
      background: "#fff8e6",
    };
  }
  return {
    ...baseKeyStyle,
    background: "#ffffff",
  };
}

function parseTaxRate(value: string): number | null {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed >= 0 && parsed <= 100
    ? parsed
    : null;
}

function cleanErrorMessage(error: unknown): string {
  const message = error instanceof Error ? error.message : String(error);
  return message.replace(/^\d{3}:\s*/, "");
}

export function AmountCalculator({
  id,
  expression,
  taxRate,
  disabled = false,
  onExpressionChange,
  onResultChange,
}: AmountCalculatorProps) {
  const [status, setStatus] = useState<PreviewStatus>({ kind: "idle" });
  const requestSequence = useRef(0);

  const runCalculation = useCallback(async () => {
    const trimmedExpression = expression.trim();
    const parsedTaxRate = parseTaxRate(taxRate);
    const requestId = ++requestSequence.current;

    if (!trimmedExpression) {
      setStatus({ kind: "error", message: "値段式を入力してください" });
      onResultChange?.(null);
      return;
    }

    if (parsedTaxRate === null) {
      setStatus({ kind: "error", message: "税率は0〜100の整数で入力してください" });
      onResultChange?.(null);
      return;
    }

    setStatus({ kind: "loading" });
    onResultChange?.(null);

    try {
      const result = await calculateAmount(trimmedExpression, parsedTaxRate);
      if (requestId !== requestSequence.current) return;
      setStatus({ kind: "success", result });
      onResultChange?.(result);
    } catch (error) {
      if (requestId !== requestSequence.current) return;
      setStatus({ kind: "error", message: cleanErrorMessage(error) });
      onResultChange?.(null);
    }
  }, [expression, onResultChange, taxRate]);

  useEffect(() => {
    requestSequence.current += 1;
    setStatus({ kind: "idle" });
    onResultChange?.(null);

    const timer = window.setTimeout(() => {
      void runCalculation();
    }, 300);

    return () => window.clearTimeout(timer);
  }, [expression, onResultChange, runCalculation, taxRate]);

  function handleKey(command: CalculatorCommand) {
    onExpressionChange(applyCalculatorCommand(expression, command));
  }

  const result = status.kind === "success" ? status.result : null;

  return (
    <div style={panelStyle}>
      <label htmlFor={id} style={{ fontWeight: 600 }}>
        値段（税込）
      </label>

      <div style={displayStyle} aria-live="polite">
        <div style={{ fontSize: "0.82rem", color: "#57606a", maxWidth: "100%" }}>
          {expression.trim() ? `式: ${expression}` : "式を入力してください"}
        </div>
        <div style={{ fontSize: "2rem", fontWeight: 700, lineHeight: 1.15 }}>
          {result
            ? `¥${result.amount.toLocaleString()}`
            : status.kind === "loading"
              ? "計算中…"
              : "—"}
        </div>
        {result && (
          <div style={{ fontSize: "0.82rem", color: "#57606a" }}>
            内税 {result.tax_amount.toLocaleString()}円（税率{result.tax_rate}%）
          </div>
        )}
        {status.kind === "error" && (
          <div className="err" style={{ fontSize: "0.85rem" }}>
            {status.message}
          </div>
        )}
      </div>

      <input
        id={id}
        value={expression}
        disabled={disabled}
        autoComplete="off"
        spellCheck={false}
        placeholder="例: (1200 + 300) / 2"
        aria-label="値段の計算式"
        onChange={(event) => onExpressionChange(event.target.value)}
      />

      <div style={keypadStyle} aria-label="値段入力電卓">
        {keypad.map((key) => (
          <button
            key={`${key.label}-${key.command}`}
            type="button"
            disabled={disabled}
            style={keyStyle(key.kind)}
            aria-label={
              key.command === "backspace"
                ? "1文字削除"
                : key.command === "clear"
                  ? "全消去"
                  : key.label
            }
            onClick={() => handleKey(key.command)}
          >
            {key.label}
          </button>
        ))}
      </div>

      <button
        type="button"
        disabled={disabled || status.kind === "loading"}
        style={{
          minHeight: 48,
          borderRadius: 999,
          border: "none",
          background: "#2da44e",
          color: "white",
          fontWeight: 700,
          fontSize: "1rem",
          cursor: "pointer",
        }}
        onClick={() => void runCalculation()}
      >
        ＝ 計算する
      </button>

      <p className="hint" style={{ margin: 0 }}>
        入力後約0.3秒で自動計算します。保存時にもバックエンドで再計算します。
      </p>
    </div>
  );
}
