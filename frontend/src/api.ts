const BASE = "/api";

async function responseErrorMessage(r: Response): Promise<string> {
  const text = await r.text();
  if (!text) return `HTTP ${r.status}`;

  try {
    const body = JSON.parse(text) as {
      detail?: string | { message?: string };
    };
    if (typeof body.detail === "string") return body.detail;
    if (body.detail?.message) return body.detail.message;
  } catch {
    // Fall through to the original response text.
  }

  return text;
}

async function handle<T>(r: Response): Promise<T> {
  if (!r.ok) {
    throw new Error(`${r.status}: ${await responseErrorMessage(r)}`);
  }
  return r.json() as Promise<T>;
}

export interface CsvPreviewRow {
  date: string;
  amount: number | null;
  tx_type: string;
  category: string;
  category_raw: string;
  memo: string;
  validation_error: string | null;
  validation_message: string | null;
}

export interface CsvPreviewResponse {
  total: number;
  error_count: number;
  rows: CsvPreviewRow[];
  header_error: string | null;
}

export interface CsvCommitResponse {
  inserted: number;
  skipped: number;
  error_count: number;
}

export async function previewCsv(file: File): Promise<CsvPreviewResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/csv/preview`, { method: "POST", body: fd });
  return handle<CsvPreviewResponse>(r);
}

export async function commitCsv(file: File): Promise<CsvCommitResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/csv/commit`, { method: "POST", body: fd });
  return handle<CsvCommitResponse>(r);
}

export type AmountMode = "tax_included" | "tax_excluded";

export interface AmountCalculationResponse {
  // Final amount paid, always tax-inclusive.
  amount: number;
  net_amount: number;
  tax_rate: number;
  tax_amount: number;
  input_amount: number;
  amount_mode: AmountMode;
}

export async function calculateAmount(
  expression: string,
  taxRate: number,
  amountMode: AmountMode = "tax_included",
): Promise<AmountCalculationResponse> {
  const r = await fetch(`${BASE}/calculations/amount`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      expression,
      tax_rate: taxRate,
      amount_mode: amountMode,
    }),
  });
  return handle<AmountCalculationResponse>(r);
}

export interface ReceiptPreviewLineItem {
  item: string;
  amount: number;
  amount_extracted: boolean;
  category: string | null;
  reason: string;
}

export interface ReceiptPreviewResponse {
  ocr_engine: string;
  raw_text: string;
  merchant_raw: string;
  items: string[];
  total_amount: number | null;
  amount: number;
  tax_rate: number;
  tax_amount: number;
  purchased_at: string;
  classification: Record<string, unknown>;
  line_items: ReceiptPreviewLineItem[];
  category: string | null;
  needs_review: boolean;
  confidence: number;
  reason: string;
}

export async function previewReceipt(file: File): Promise<ReceiptPreviewResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/receipts/preview`, {
    method: "POST",
    body: fd,
  });
  return handle<ReceiptPreviewResponse>(r);
}
