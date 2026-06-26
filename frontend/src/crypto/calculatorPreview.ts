import type {
  AmountCalculationResponse,
  AmountMode,
} from "../api.js";

function roundYen(value: number): number {
  return Math.round(value);
}

export function optimisticAmountPreview(
  expression: string,
  taxRate: number | null,
  amountMode: AmountMode,
): AmountCalculationResponse | null {
  if (taxRate === null || taxRate < 0 || taxRate > 100) return null;

  const normalized = expression.trim();
  if (!/^\d+(?:\.\d*)?$/.test(normalized)) return null;

  const numericValue = Number(normalized);
  if (!Number.isFinite(numericValue) || numericValue < 0) return null;

  const inputAmount = roundYen(numericValue);

  if (amountMode === "tax_excluded") {
    const taxAmount = roundYen((inputAmount * taxRate) / 100);
    return {
      amount: inputAmount + taxAmount,
      net_amount: inputAmount,
      tax_rate: taxRate,
      tax_amount: taxAmount,
      input_amount: inputAmount,
      amount_mode: amountMode,
    };
  }

  const taxAmount =
    taxRate === 0
      ? 0
      : roundYen((inputAmount * taxRate) / (100 + taxRate));

  return {
    amount: inputAmount,
    net_amount: inputAmount - taxAmount,
    tax_rate: taxRate,
    tax_amount: taxAmount,
    input_amount: inputAmount,
    amount_mode: amountMode,
  };
}

export function isZeroAmountPreview(
  preview: AmountCalculationResponse | null,
): boolean {
  return preview !== null && preview.input_amount === 0;
}
