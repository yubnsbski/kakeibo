import { useCallback, useEffect, useRef, useState } from "react";
import type { CSSProperties } from "react";
import {
  calculateAmount,
  type AmountCalculationResponse,
  type AmountMode,
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
  amountMode: AmountMode;
  disabled?: boolean;
  onExpressionChange: (expression: string) => void;
  onTaxRateChange: (taxRate: string) => void;
  onAmountModeChange: (amountMode: AmountMode) => void;
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
  borderRadius: 16,
  padding: 16,
  background: "#ffffff",
  color: "#1f2328",
  display: "grid",
  gap: 14,
  maxWidth: 560,
  boxShadow: "0 4px 16px rgba(31, 35, 40, 0.08)",
};

const displayStyle: CSSProperties = {
  border: "1px solid #d8dee4",
  borderRadius: 14,
  padding: "16px",
  minHeight: 154,
  background: "#f6f8fa",
  color: "#1f2328",
  display: "grid",
  gap: 10,
};

const keypadStyle: CSSProperties = {
  display: "grid",
  gridTemplateColumns: "repeat(4, minmax(56px, 1fr))",
  gap: 8,
};

const baseKeyStyle: CSSProperties = {
  minHeight: 50,
  borderRadius: 12,
  border: "1px solid #b6bec8",
  color: "#1f2328",
  WebkitTextFillColor: "#1f2328",
  fontSize: "1.15rem",
  lineHeight: 1,
  fontWeight: 700,
  cursor: "pointer",
  boxShadow: "0 1px 2px rgba(31, 35, 40, 0.08)",
};

const taxSummaryStyle: CSSProperties = {
  display: "grid",
  gridTemplateColumns: "repeat(3, minmax(0, 1fr))",
  gap: 8,
  width: "100%",
};

function keyStyle(kind: KeyDefinition["kind"]): CSSProperties {
  if (kind === "operator") {
    return {
      ...baseKeyStyle,
      background: "#dbeafe",
      color: "#075985",
      WebkitTextFillColor: "#075985",
      borderColor: "#93c5fd",
    };
  }
  if (kind === "control") {
    return {
      ...baseKeyStyle,
      background: "#fff4d6",
      color: "#7c2d12",
      WebkitTextFillColor: "#7c2d12",
      borderColor: "#f2c66d",
    };
  }
  return {
    ...baseKeyStyle,
    background: "#ffffff",
    color: "#111827",
    WebkitTextFillColor: "#111827",
  };
}

function modeButtonStyle(selected: boolean): CSSProperties {
  return {
    flex: "1 1 150px",
    minHeight: 46,
    borderRadius: 12,
    border: selected ? "2px solid #1f6feb" : "1px solid #b6bec8",
    background: selected ? "#1f6feb" : "#ffffff",
    color: selected ? "#ffffff" : "#1f2328",
    WebkitTextFillColor: selected ? "#ffffff" : "#1f2328",
    fontWeight: 700,
    cursor: "pointer",
  };
}

function taxRateButtonStyle(selected: boolean): CSSProperties {
  return {
    minWidth: 58,
    minHeight: 40,
    borderRadius: 999,
    border: selected ? "2px solid #2da44e" : "1px solid #b6bec8",
    background: selected ? "#dafbe1" : "#ffffff",
    color: selected ? "#116329" : "#1f2328",
    WebkitTextFillColor: selected ? "#116329" : "#1f2328",
    fontWeight: 700,
    cursor: "pointer",
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

function modeLabel(mode: AmountMode): string {
  return mode === "tax_excluded" ? "税抜で入力" : "税込で入力";
}

function SummaryCell({
  label,
  value,
  emphasis = false,
}: {
  label: string;
  value: number | null;
  emphasis?: boolean;
}) {
  return (
    <div
      style={{
        border: "1px solid #d8dee4",
        borderRadius: 10,
        padding: "9px 8px",
        textAlign: "center",
        background: emphasis ? "#eefbf2" : "#ffffff",
        minWidth: 0,
      }}
    >
      <div style={{ color: "#57606a", fontSize: "0.76rem" }}>{label}</div>
      <div
        style={{
          color: "#1f2328",
          fontSize: "0.98rem",
          fontWeight: emphasis ? 800 : 650,
          overflowWrap: "anywhere",
        }}
      >
        {value === null ? "—" : `${value.toLocaleString()}円`}
      </div>
    </div>
  );
}

export function AmountCalculator({
  id,
  expression,
  taxRate,
  amountMode,
  disabled = false,
  onExpressionChange,
  onTaxRateChange,
  onAmountModeChange,
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
      const result = await calculateAmount(
        trimmedExpression,
        parsedTaxRate,
        amountMode,
      );
      if (requestId !== requestSequence.current) return;
      setStatus({ kind: "success", result });
      onResultChange?.(result);
    } catch (error) {
      if (requestId !== requestSequence.current) return;
      setStatus({ kind: "error", message: cleanErrorMessage(error) });
      onResultChange?.(null);
    }
  }, [amountMode, expression, onResultChange, taxRate]);

  useEffect(() => {
    requestSequence.current += 1;
    setStatus({ kind: "idle" });
    onResultChange?.(null);

    const timer = window.setTimeout(() => {
      void runCalculation();
    }, 300);

    return () => window.clearTimeout(timer);
  }, [amountMode, expression, onResultChange, runCalculation, taxRate]);

  function handleKey(command: CalculatorCommand) {
    onExpressionChange(applyCalculatorCommand(expression, command));
  }

  const result = status.kind === "success" ? status.result : null;
  const selectedTaxRate = parseTaxRate(taxRate);

  return (
    <div style={panelStyle}>
      <div>
        <div style={{ fontWeight: 800, fontSize: "1.05rem" }}>金額を計算</div>
        <div className="hint" style={{ marginTop: 3 }}>
          入力する金額が税込か税抜かを先に選びます。
        </div>
      </div>

      <div
        role="group"
        aria-label="金額の入力方式"
        style={{ display: "flex", gap: 8, flexWrap: "wrap" }}
      >
        <button
          type="button"
          aria-pressed={amountMode === "tax_included"}
          disabled={disabled}
          style={modeButtonStyle(amountMode === "tax_included")}
          onClick={() => onAmountModeChange("tax_included")}
        >
          税込で入力
        </button>
        <button
          type="button"
          aria-pressed={amountMode === "tax_excluded"}
          disabled={disabled}
          style={modeButtonStyle(amountMode === "tax_excluded")}
          onClick={() => onAmountModeChange("tax_excluded")}
        >
          税抜で入力
        </button>
      </div>

      <div style={displayStyle} aria-live="polite">
        <div style={{ color: "#57606a", fontSize: "0.8rem" }}>
          {modeLabel(amountMode)}
          {expression.trim() ? `：${expression}` : "：式を入力してください"}
        </div>

        <div style={{ display: "grid", justifyItems: "end", gap: 2 }}>
          <div style={{ color: "#57606a", fontSize: "0.8rem" }}>
            支払額（税込）
          </div>
          <div
            style={{
              color: "#111827",
              fontSize: "2.15rem",
              fontWeight: 850,
              lineHeight: 1.1,
            }}
          >
            {result
              ? `¥${result.amount.toLocaleString()}`
              : status.kind === "loading"
                ? "計算中…"
                : "—"}
          </div>
        </div>

        <div style={taxSummaryStyle}>
          <SummaryCell label="税抜" value={result?.net_amount ?? null} />
          <SummaryCell label="消費税" value={result?.tax_amount ?? null} />
          <SummaryCell label="税込" value={result?.amount ?? null} emphasis />
        </div>

        {status.kind === "error" && (
          <div className="err" style={{ fontSize: "0.86rem", fontWeight: 650 }}>
            {status.message}
          </div>
        )}
      </div>

      <label htmlFor={id} style={{ fontWeight: 700 }}>
        {amountMode === "tax_excluded" ? "税抜金額・計算式" : "税込金額・計算式"}
      </label>
      <input
        id={id}
        value={expression}
        disabled={disabled}
        autoComplete="off"
        inputMode="decimal"
        spellCheck={false}
        placeholder="例: (1200 + 300) / 2"
        aria-label="値段の計算式"
        style={{
          minHeight: 46,
          padding: "10px 12px",
          border: "1px solid #b6bec8",
          borderRadius: 10,
          color: "#111827",
          background: "#ffffff",
          fontSize: "1.05rem",
        }}
        onChange={(event) => onExpressionChange(event.target.value)}
      />

      <div style={{ display: "grid", gap: 8 }}>
        <div style={{ fontWeight: 700 }}>税率</div>
        <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
          {[0, 8, 10].map((rate) => (
            <button
              key={rate}
              type="button"
              aria-pressed={selectedTaxRate === rate}
              disabled={disabled}
              style={taxRateButtonStyle(selectedTaxRate === rate)}
              onClick={() => onTaxRateChange(String(rate))}
            >
              {rate}%
            </button>
          ))}
          <label style={{ display: "flex", gap: 6, alignItems: "center" }}>
            <span className="hint">その他</span>
            <input
              type="number"
              min="0"
              max="100"
              step="1"
              value={taxRate}
              disabled={disabled}
              aria-label="税率"
              style={{ width: 76, minHeight: 40 }}
              onChange={(event) => onTaxRateChange(event.target.value)}
            />
            <span>%</span>
          </label>
        </div>
      </div>

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
          minHeight: 50,
          borderRadius: 999,
          border: "none",
          background: "#2da44e",
          color: "#ffffff",
          WebkitTextFillColor: "#ffffff",
          fontWeight: 800,
          fontSize: "1rem",
          cursor: "pointer",
        }}
        onClick={() => void runCalculation()}
      >
        ＝ 計算する
      </button>

      <p className="hint" style={{ margin: 0 }}>
        入力後約0.3秒で自動計算します。1円未満は四捨五入し、保存時にも再計算します。
      </p>
    </div>
  );
}
