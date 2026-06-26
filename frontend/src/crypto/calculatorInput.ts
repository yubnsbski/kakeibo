export type CalculatorCommand =
  | "0"
  | "1"
  | "2"
  | "3"
  | "4"
  | "5"
  | "6"
  | "7"
  | "8"
  | "9"
  | "00"
  | "."
  | "+"
  | "-"
  | "*"
  | "/"
  | "("
  | ")"
  | "backspace"
  | "clear";

const OPERATOR_PATTERN = /[+\-*/×÷−]/;

function lastSignificantCharacter(expression: string): string {
  return expression.trimEnd().slice(-1);
}

function stripLastSignificantCharacter(expression: string): string {
  const trimmed = expression.trimEnd();
  return trimmed.slice(0, -1).trimEnd();
}

function currentNumberToken(expression: string): string {
  const normalized = expression
    .replace(/[×]/g, "*")
    .replace(/[÷]/g, "/")
    .replace(/[−]/g, "-");
  const parts = normalized.split(/[+\-*/()]/);
  return (parts[parts.length - 1] ?? "").trim();
}

function unmatchedOpenParentheses(expression: string): number {
  let depth = 0;
  for (const character of expression) {
    if (character === "(") depth += 1;
    if (character === ")") depth -= 1;
  }
  return depth;
}

function appendDigit(expression: string, digit: string): string {
  const trimmed = expression.trim();
  if (!trimmed || trimmed === "0") {
    return digit === "00" ? "0" : digit;
  }

  const last = lastSignificantCharacter(expression);
  if (last === ")") {
    return `${expression.trimEnd()}*${digit}`;
  }

  return `${expression}${digit}`;
}

function appendDecimalPoint(expression: string): string {
  const trimmed = expression.trim();
  if (!trimmed || trimmed === "0") return "0.";
  if (currentNumberToken(expression).includes(".")) return expression;

  const last = lastSignificantCharacter(expression);
  if (last === ")") return `${expression.trimEnd()}*0.`;
  if (!/\d/.test(last)) return `${expression}0.`;
  return `${expression}.`;
}

function appendOperator(expression: string, operator: string): string {
  let base = expression.trimEnd();
  if (!base) return operator === "-" ? "-" : `0${operator}`;

  let last = lastSignificantCharacter(base);
  if (last === ".") {
    base = stripLastSignificantCharacter(base);
    last = lastSignificantCharacter(base);
  }

  if (OPERATOR_PATTERN.test(last)) {
    const withoutOperator = stripLastSignificantCharacter(base);
    if (!withoutOperator) return operator === "-" ? "-" : `0${operator}`;
    return `${withoutOperator}${operator}`;
  }

  if (last === "(") {
    return operator === "-" ? `${base}-` : base;
  }

  if (/\d/.test(last) || last === ")") {
    return `${base}${operator}`;
  }

  return base;
}

function appendOpenParenthesis(expression: string): string {
  const trimmed = expression.trim();
  if (!trimmed || trimmed === "0") return "(";

  const last = lastSignificantCharacter(expression);
  if (/\d/.test(last) || last === ")" || last === ".") {
    return `${expression.trimEnd()}*(`;
  }

  return `${expression}(`;
}

function appendCloseParenthesis(expression: string): string {
  if (unmatchedOpenParentheses(expression) <= 0) return expression;

  const last = lastSignificantCharacter(expression);
  if (!/\d/.test(last) && last !== ")") return expression;
  return `${expression.trimEnd()})`;
}

export function applyCalculatorCommand(
  expression: string,
  command: CalculatorCommand,
): string {
  if (command === "clear") return "0";

  if (command === "backspace") {
    const next = stripLastSignificantCharacter(expression);
    return next && next !== "-" ? next : "0";
  }

  if (/^(?:\d|00)$/.test(command)) {
    return appendDigit(expression, command);
  }

  if (command === ".") return appendDecimalPoint(expression);
  if (["+", "-", "*", "/"].includes(command)) {
    return appendOperator(expression, command);
  }
  if (command === "(") return appendOpenParenthesis(expression);
  if (command === ")") return appendCloseParenthesis(expression);

  return expression;
}
