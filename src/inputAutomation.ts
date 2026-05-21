import { classifyReceipt } from "./classifyReceipt";
import { classifyReceiptBreakdown, type BreakdownOptions } from "./classifyReceiptBreakdown";
import { allocateAmountsByCategory } from "./allocateAmounts";
import type {
  AmountAllocationResult,
  Category,
  ClassificationResult,
  ManualTransactionInput,
  ReceiptInput
} from "./types";

export type CsvReceiptRow = {
  receipt_id: string;
  merchantRaw: string;
  items: string[];
  totalAmount: number;
  purchasedAt: string;
};

export type InputValidationErrorCode =
  | "missing_merchant"
  | "invalid_total_amount"
  | "invalid_purchased_at";

export type AutomatedClassificationRow = {
  receipt_id: string;
  merchantRaw: string;
  merchant_normalized: string;
  items_text: string;
  category: Category | "REVIEW";
  needs_review: "yes" | "no";
  reason: string;
  confidence: number;
  amount: number;
  purchased_at: string;
  validation_error?: InputValidationErrorCode;
  validation_message?: string;
};

export type RunClassificationResult = {
  ok: true;
  output: ClassificationResult;
} | {
  ok: false;
  error: InputValidationErrorCode;
  message: string;
};

export type ManualInputValidationErrorCode =
  | "missing_date"
  | "invalid_date"
  | "missing_tx_type"
  | "missing_items"
  | "invalid_item_amount"
  | "missing_item_text";

export type ManualInputUnsupportedErrorCode =
  | "income_not_supported";

export type ManualInputErrorCode =
  | ManualInputValidationErrorCode
  | ManualInputUnsupportedErrorCode;

export type ManualInputValidationResult = {
  ok: true;
} | {
  ok: false;
  error: ManualInputValidationErrorCode;
  message: string;
};

export type ManualAllocationInput = {
  receiptInput: ReceiptInput;
  totalAmount: number;
  source: "manual_input";
};

export type ManualToAllocationResult = {
  ok: true;
  value: ManualAllocationInput;
} | {
  ok: false;
  error: ManualInputErrorCode;
  message: string;
};

export type ManualTransactionOutput = {
  classification: ClassificationResult;
  allocation: AmountAllocationResult;
  needsReview: boolean;
};

export type RunManualTransactionResult = {
  ok: true;
  output: ManualTransactionOutput;
} | {
  ok: false;
  error: ManualInputErrorCode;
  message: string;
};

const OUTPUT_HEADER =
  "receipt_id,merchant_normalized,items_text,screening_category,needs_review,reason,confidence,amount,purchased_at";

const VALIDATION_MESSAGES: Record<InputValidationErrorCode, string> = {
  missing_merchant: "店舗名を入力してください",
  invalid_total_amount: "金額は0より大きい値を入力してください",
  invalid_purchased_at: "日付はYYYY-MM-DD形式で入力してください"
};

const MANUAL_VALIDATION_MESSAGES: Record<ManualInputErrorCode, string> = {
  missing_date: "日付を入力してください",
  invalid_date: "日付はYYYY-MM-DD形式で入力してください",
  missing_tx_type: "取引種別を選択してください",
  missing_items: "明細を1件以上入力してください",
  invalid_item_amount: "明細金額は0より大きい値を入力してください",
  missing_item_text: "各明細はnameまたはmemoのいずれかを入力してください",
  income_not_supported: "手入力は現在、支出のみ対応です"
};

export function parseReceiptCsv(csvText: string): CsvReceiptRow[] {
  const lines = csvText
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  if (lines.length === 0) return [];

  const [header, ...rows] = lines;
  const expectedHeader = "receipt_id,merchantRaw,items,totalAmount,purchasedAt";
  if (header !== expectedHeader) {
    throw new Error(`invalid csv header: expected '${expectedHeader}'`);
  }

  return rows.map((row) => {
    const [receipt_id = "", merchantRaw = "", itemsRaw = "", totalAmountRaw = "", purchasedAt = ""] =
      row.split(",");

    return {
      receipt_id,
      merchantRaw,
      items: itemsRaw
        .split("|")
        .map((item) => item.trim())
        .filter((item) => item.length > 0),
      totalAmount: Number(totalAmountRaw),
      purchasedAt
    };
  });
}

export function validateCsvRowInput(row: CsvReceiptRow): InputValidationErrorCode | null {
  if (!row.merchantRaw.trim()) return "missing_merchant";
  if (!Number.isFinite(row.totalAmount) || row.totalAmount <= 0) return "invalid_total_amount";
  if (!isValidDateYYYYMMDD(row.purchasedAt)) return "invalid_purchased_at";
  return null;
}

function isValidDateYYYYMMDD(dateText: string): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(dateText)) return false;
  const d = new Date(`${dateText}T00:00:00Z`);
  if (Number.isNaN(d.getTime())) return false;
  return d.toISOString().slice(0, 10) === dateText;
}

export function validateManualTransactionInput(
  input: ManualTransactionInput
): ManualInputValidationResult {
  if (!input.date?.trim()) {
    return { ok: false, error: "missing_date", message: MANUAL_VALIDATION_MESSAGES.missing_date };
  }
  if (!isValidDateYYYYMMDD(input.date)) {
    return { ok: false, error: "invalid_date", message: MANUAL_VALIDATION_MESSAGES.invalid_date };
  }
  if (!input.txType) {
    return { ok: false, error: "missing_tx_type", message: MANUAL_VALIDATION_MESSAGES.missing_tx_type };
  }
  if (!Array.isArray(input.items) || input.items.length === 0) {
    return { ok: false, error: "missing_items", message: MANUAL_VALIDATION_MESSAGES.missing_items };
  }

  for (const item of input.items) {
    if (!Number.isFinite(item.amount) || item.amount <= 0) {
      return {
        ok: false,
        error: "invalid_item_amount",
        message: MANUAL_VALIDATION_MESSAGES.invalid_item_amount
      };
    }

    const label = item.name?.trim() || item.memo?.trim() || "";
    if (!label) {
      return {
        ok: false,
        error: "missing_item_text",
        message: MANUAL_VALIDATION_MESSAGES.missing_item_text
      };
    }
  }

  return { ok: true };
}

export function manualTransactionToAllocationInput(
  input: ManualTransactionInput
): ManualToAllocationResult {
  const validation = validateManualTransactionInput(input);
  if (!validation.ok) {
    return validation;
  }

  if (input.txType === "income") {
    return {
      ok: false,
      error: "income_not_supported",
      message: MANUAL_VALIDATION_MESSAGES.income_not_supported
    };
  }

  const itemTexts = input.items.map((item) => (item.name?.trim() || item.memo?.trim() || "").trim());
  const totalAmount = input.items.reduce((sum, item) => sum + item.amount, 0);

  return {
    ok: true,
    value: {
      receiptInput: {
        merchantRaw: input.memo?.trim() || "手入力",
        items: itemTexts,
        totalAmount,
        purchasedAt: input.date
      },
      totalAmount,
      source: "manual_input"
    }
  };
}

export function runManualTransactionInput(input: ManualTransactionInput): RunManualTransactionResult {
  const normalized = manualTransactionToAllocationInput(input);
  if (!normalized.ok) {
    return normalized;
  }

  const classification = classifyReceipt(normalized.value.receiptInput);
  const breakdown = classifyReceiptBreakdown(normalized.value.receiptInput);
  const allocation = allocateAmountsByCategory(breakdown, normalized.value.totalAmount);

  return {
    ok: true,
    output: {
      classification,
      allocation,
      needsReview: classification.needsReview || breakdown.needsReview
    }
  };
}

export function runClassification(
  input: ReceiptInput,
  receiptId = "single-001"
): RunClassificationResult {
  const normalizedInput: CsvReceiptRow = {
    receipt_id: receiptId,
    merchantRaw: input.merchantRaw,
    items: input.items ?? [],
    totalAmount: input.totalAmount ?? NaN,
    purchasedAt: input.purchasedAt ?? ""
  };

  const validationError = validateCsvRowInput(normalizedInput);
  if (validationError) {
    return {
      ok: false,
      error: validationError,
      message: VALIDATION_MESSAGES[validationError]
    };
  }

  return { ok: true, output: classifyReceipt(input) };
}

export function runClassificationFromCsvRows(
  rows: CsvReceiptRow[],
  userCategoryOverrides?: Partial<Record<string, Category>>
): AutomatedClassificationRow[] {
  return rows.map((row) => {
    const validationError = validateCsvRowInput(row);

    if (validationError) {
      return {
        receipt_id: row.receipt_id,
        merchantRaw: row.merchantRaw,
        merchant_normalized: row.merchantRaw,
        items_text: row.items.join("|"),
        category: "REVIEW",
        needs_review: "yes",
        reason: validationError,
        confidence: 0,
        amount: Number.isFinite(row.totalAmount) ? row.totalAmount : 0,
        purchased_at: row.purchasedAt,
        validation_error: validationError,
        validation_message: VALIDATION_MESSAGES[validationError]
      };
    }

    const input: ReceiptInput = {
      merchantRaw: row.merchantRaw,
      items: row.items,
      totalAmount: row.totalAmount,
      purchasedAt: row.purchasedAt,
      userCategoryOverrides
    };

    const result = classifyReceipt(input);

    return {
      receipt_id: row.receipt_id,
      merchantRaw: row.merchantRaw,
      merchant_normalized: result.merchantNormalized,
      items_text: row.items.join("|"),
      category: result.category ?? "REVIEW",
      needs_review: result.needsReview ? "yes" : "no",
      reason: result.reason,
      confidence: result.confidence,
      amount: row.totalAmount,
      purchased_at: row.purchasedAt
    };
  });
}

export type BreakdownClassificationRow = {
  receipt_id: string;
  merchant_normalized: string;
  category: Category | "REVIEW";
  item_texts: string;
  amount: number;
  is_mixed: "yes" | "no";
  purchased_at: string;
  reason: string;
};

const BREAKDOWN_OUTPUT_HEADER =
  "receipt_id,merchant_normalized,category,item_texts,amount,is_mixed,purchased_at,reason";

export function runBreakdownClassificationFromCsvRows(
  rows: CsvReceiptRow[],
  options: BreakdownOptions = {}
): BreakdownClassificationRow[] {
  const output: BreakdownClassificationRow[] = [];

  for (const row of rows) {
    const validationError = validateCsvRowInput(row);
    if (validationError) {
      output.push({
        receipt_id: row.receipt_id,
        merchant_normalized: row.merchantRaw,
        category: "REVIEW",
        item_texts: row.items.join("|"),
        amount: Number.isFinite(row.totalAmount) ? row.totalAmount : 0,
        is_mixed: "no",
        purchased_at: row.purchasedAt,
        reason: validationError
      });
      continue;
    }

    const breakdown = classifyReceiptBreakdown(
      {
        merchantRaw: row.merchantRaw,
        items: row.items,
        totalAmount: row.totalAmount,
        purchasedAt: row.purchasedAt
      },
      options
    );

    const allocation = allocateAmountsByCategory(breakdown, row.totalAmount);
    const isMixed: "yes" | "no" = breakdown.isMixed ? "yes" : "no";

    if (allocation.allocations.length === 0) {
      output.push({
        receipt_id: row.receipt_id,
        merchant_normalized: breakdown.merchantNormalized,
        category: "REVIEW",
        item_texts: "",
        amount: row.totalAmount,
        is_mixed: isMixed,
        purchased_at: row.purchasedAt,
        reason: "no_items"
      });
      continue;
    }

    for (const allocationEntry of allocation.allocations) {
      output.push({
        receipt_id: row.receipt_id,
        merchant_normalized: breakdown.merchantNormalized,
        category: allocationEntry.category ?? "REVIEW",
        item_texts: allocationEntry.itemTexts.join("|"),
        amount: allocationEntry.amount,
        is_mixed: isMixed,
        purchased_at: row.purchasedAt,
        reason:
          allocationEntry.category === null
            ? "no_keyword_matched"
            : breakdown.isMixed
              ? "mixed_receipt_split"
              : "rule_match"
      });
    }
  }

  return output;
}

export function exportBreakdownClassificationCsv(rows: BreakdownClassificationRow[]): string {
  const body = rows.map((row) =>
    [
      row.receipt_id,
      row.merchant_normalized.split(",").join(" "),
      row.category,
      row.item_texts.split(",").join(" "),
      row.amount,
      row.is_mixed,
      row.purchased_at,
      row.reason.split(",").join(" ")
    ].join(",")
  );
  return [BREAKDOWN_OUTPUT_HEADER, ...body].join("\n");
}

export function exportAutomatedClassificationCsv(rows: AutomatedClassificationRow[]): string {
  const body = rows.map((row) =>
    [
      row.receipt_id,
      row.merchant_normalized.split(",").join(" "),
      row.items_text.split(",").join(" "),
      row.category,
      row.needs_review,
      row.reason.split(",").join(" "),
      row.confidence,
      row.amount,
      row.purchased_at
    ].join(",")
  );

  return [OUTPUT_HEADER, ...body].join("\n");
}
