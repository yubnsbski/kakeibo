import { classifyReceipt } from "./classifyReceipt";
import type { Category, ClassificationResult, ReceiptInput } from "./types";

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

export type ParseCsvResult = {
  rows: CsvReceiptRow[];
  error?: "invalid_header";
  warnings?: Array<{
    row: number;
    code: "invalid_csv_row";
  }>;
};

const INPUT_HEADER = "receipt_id,merchantRaw,items,totalAmount,purchasedAt";
const INPUT_COLUMN_COUNT = 5;

const OUTPUT_HEADER =
  "receipt_id,merchant_normalized,items_text,screening_category,needs_review,reason,confidence,amount,purchased_at";

const VALIDATION_MESSAGES: Record<InputValidationErrorCode, string> = {
  missing_merchant: "店舗名を入力してください",
  invalid_total_amount: "金額は0より大きい値を入力してください",
  invalid_purchased_at: "日付はYYYY-MM-DD形式で入力してください"
};

export function parseReceiptCsv(csvText: string): CsvReceiptRow[] {
  return parseReceiptCsvWithDiagnostics(csvText).rows;
}

export function parseReceiptCsvWithDiagnostics(csvText: string): ParseCsvResult {
  const lines = csvText
    .split(/\r?\n/)
    .filter((line) => line.trim().length > 0);

  if (lines.length === 0) return { rows: [] };

  const [header, ...rows] = lines;
  if (normalizeHeader(header) !== normalizeHeader(INPUT_HEADER)) {
    return { rows: [], error: "invalid_header" };
  }

  const warnings: NonNullable<ParseCsvResult["warnings"]> = [];
  const parsedRows = rows.flatMap((row, index) => {
    const rowNumber = index + 2;
    const columns = parseCsvLine(row);
    if (!isValidInputRow(columns)) {
      addInvalidCsvRowWarning(warnings, rowNumber);
      return [];
    }
    const receipt_id = columns[0] ?? "";
    const merchantRaw = columns[1] ?? "";
    const purchasedAt = columns.at(-1) ?? "";
    const { itemsRaw, totalAmountRaw } = splitItemsAndAmount(columns.slice(2, -1));

    return [{
      receipt_id,
      merchantRaw,
      items: itemsRaw
        .split("|")
        .map((item) => item.trim())
        .filter((item) => item.length > 0),
      totalAmount: parseTotalAmount(totalAmountRaw),
      purchasedAt
    }];
  });

  return warnings.length > 0 ? { rows: parsedRows, warnings } : { rows: parsedRows };
}

function addInvalidCsvRowWarning(
  warnings: NonNullable<ParseCsvResult["warnings"]>,
  rowNumber: number
): void {
  warnings.push({ row: rowNumber, code: "invalid_csv_row" });
}

function isValidInputRow(columns: string[] | null): columns is string[] {
  return columns !== null && columns.length >= INPUT_COLUMN_COUNT;
}

function parseCsvLine(line: string): string[] | null {
  const values: string[] = [];
  let current = "";
  let inQuotes = false;
  let fieldStarted = false;

  for (let i = 0; i < line.length; i += 1) {
    const ch = line[i];

    if (ch === '"') {
      if (!inQuotes) {
        if (fieldStarted) return null;
        inQuotes = true;
        fieldStarted = true;
        continue;
      }

      if (line[i + 1] === '"') {
        current += '"';
        i += 1;
        fieldStarted = true;
        continue;
      }

      const next = line[i + 1];
      if (next !== "," && next !== undefined) {
        return null;
      }
      inQuotes = false;
      fieldStarted = true;
      continue;
    }

    if (ch === "," && !inQuotes) {
      values.push(current);
      current = "";
      fieldStarted = false;
      continue;
    }

    current += ch;
    fieldStarted = true;
  }

  if (inQuotes) return null;
  values.push(current);
  return values;
}

function normalizeHeader(header: string): string {
  return header.replace(/^\uFEFF/, "").replace(/\s+/g, "").toLowerCase();
}


function parseTotalAmount(raw: string): number {
  const normalized = toHalfWidth(raw)
    .replace(/[¥￥]/g, "")
    .replace(/,/g, "")
    .trim();

  if (!/^[-+]?\d+(?:\.\d+)?$/.test(normalized)) return Number.NaN;
  return Number(normalized);
}

function splitItemsAndAmount(columns: string[]): { itemsRaw: string; totalAmountRaw: string } {
  if (columns.length === 0) return { itemsRaw: "", totalAmountRaw: "" };
  if (columns.length === 1) return { itemsRaw: "", totalAmountRaw: columns[0] ?? "" };

  for (let amountStart = 1; amountStart < columns.length; amountStart += 1) {
    const amountCandidate = columns.slice(amountStart).join(",");
    if (Number.isFinite(parseTotalAmount(amountCandidate))) {
      return {
        itemsRaw: columns.slice(0, amountStart).join(","),
        totalAmountRaw: amountCandidate
      };
    }
  }

  return {
    itemsRaw: columns.slice(0, -1).join(","),
    totalAmountRaw: columns.at(-1) ?? ""
  };
}

function toHalfWidth(text: string): string {
  return text.replace(/[！-～]/g, (char) =>
    String.fromCharCode(char.charCodeAt(0) - 0xFEE0)
  ).replace(/　/g, " ");
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
