import type {
  CategoryMaster, ReceiptUploadResponse, Transaction, TransactionItem,
  UserCategoryOverride,
} from "./types";

const BASE = "/api";

async function handle<T>(r: Response): Promise<T> {
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
  return r.json() as Promise<T>;
}

// ===== Receipts =====
export async function uploadReceipt(file: File): Promise<ReceiptUploadResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/receipts/upload`, { method: "POST", body: fd });
  return handle<ReceiptUploadResponse>(r);
}

// ===== Transactions =====
export interface ListParams {
  status?: string;
  needs_review?: boolean;
  merchant?: string;
  start_date?: string;
  end_date?: string;
  limit?: number;
  offset?: number;
}

export async function listTransactions(p: ListParams = {}): Promise<Transaction[]> {
  const sp = new URLSearchParams();
  Object.entries(p).forEach(([k, v]) => {
    if (v !== undefined && v !== null && v !== "") sp.set(k, String(v));
  });
  const q = sp.toString() ? `?${sp.toString()}` : "";
  const r = await fetch(`${BASE}/transactions${q}`);
  return handle<Transaction[]>(r);
}

export async function getTransaction(id: number): Promise<Transaction> {
  return handle<Transaction>(await fetch(`${BASE}/transactions/${id}`));
}

export async function updateTransaction(id: number, patch: Partial<Transaction>): Promise<Transaction> {
  const r = await fetch(`${BASE}/transactions/${id}`, {
    method: "PATCH", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  return handle<Transaction>(r);
}

export async function deleteTransaction(id: number): Promise<void> {
  const r = await fetch(`${BASE}/transactions/${id}`, { method: "DELETE" });
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
}

// ===== Overrides =====
export async function listOverrides(): Promise<UserCategoryOverride[]> {
  return handle<UserCategoryOverride[]>(await fetch(`${BASE}/overrides`));
}

export async function createOverride(merchant_pattern: string, category: string): Promise<UserCategoryOverride> {
  const r = await fetch(`${BASE}/overrides`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ merchant_pattern, category }),
  });
  return handle<UserCategoryOverride>(r);
}

// ===== Categories =====
export async function listCategories(): Promise<CategoryMaster[]> {
  return handle<CategoryMaster[]>(await fetch(`${BASE}/categories`));
}

// ===== Items =====
export async function createItem(
  txId: number, item: { name: string; amount: number; category: string | null; sort_order?: number }
): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...item, sort_order: item.sort_order ?? 0 }),
  });
  return handle<TransactionItem>(r);
}

export async function updateItem(txId: number, itemId: number, patch: Partial<TransactionItem>): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, {
    method: "PATCH", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  return handle<TransactionItem>(r);
}

export async function deleteItem(txId: number, itemId: number): Promise<void> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, { method: "DELETE" });
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
}

// ===== CSV import =====
export interface CsvPreviewRow {
  date: string;
  amount: number | null;
  category: string;
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

// ===== Summary =====
export interface CategorySummary {
  ym: string;
  total: number;
  slices: { category: string; amount: number }[];
}

export interface MonthlySummary {
  months: number;
  slices: { ym: string; total: number }[];
}

export async function categorySummary(ym: string): Promise<CategorySummary> {
  return handle<CategorySummary>(await fetch(`${BASE}/summary/category?ym=${ym}`));
}

export async function monthlySummary(months = 6): Promise<MonthlySummary> {
  return handle<MonthlySummary>(await fetch(`${BASE}/summary/monthly?months=${months}`));
}

// ===== Cashflow extended =====
export interface MonthlyByCategoryRow {
  ym: string;
  by_category: Record<string, number>;
  total: number;
}
export interface MonthlyByCategoryResponse {
  months: number;
  categories: string[];
  rows: MonthlyByCategoryRow[];
}

export interface DailyCumulativePoint {
  date: string;
  cumulative: number;
}
export interface DailyCumulativeResponse {
  ym: string;
  points: DailyCumulativePoint[];
  total: number;
}

export interface TopTransactionItem {
  id: number;
  purchased_at: string;
  merchant: string;
  category: string | null;
  amount: number;
}
export interface TopTransactionsResponse {
  ym: string;
  limit: number;
  items: TopTransactionItem[];
}

export async function monthlyByCategory(months = 6): Promise<MonthlyByCategoryResponse> {
  return handle<MonthlyByCategoryResponse>(await fetch(`${BASE}/summary/monthly_by_category?months=${months}`));
}

export async function dailyCumulative(ym: string): Promise<DailyCumulativeResponse> {
  return handle<DailyCumulativeResponse>(await fetch(`${BASE}/summary/daily_cumulative?ym=${ym}`));
}

export async function topTransactions(ym: string, limit = 10): Promise<TopTransactionsResponse> {
  return handle<TopTransactionsResponse>(await fetch(`${BASE}/summary/top_transactions?ym=${ym}&limit=${limit}`));
}

// ===== Cashflow (income/expense) =====
export interface CashflowSummary {
  ym: string;
  income: number;
  expense: number;
  balance: number;
}

export interface CategoryDiff {
  category: string;
  current: number;
  previous: number;
  diff: number;
  ratio: number | null;
}

export interface MonthCompareResponse {
  current_ym: string;
  previous_ym: string;
  diffs: CategoryDiff[];
}

export async function cashflowSummary(ym: string): Promise<CashflowSummary> {
  return handle<CashflowSummary>(await fetch(`${BASE}/summary/cashflow?ym=${ym}`));
}

export async function monthCompare(ym: string): Promise<MonthCompareResponse> {
  return handle<MonthCompareResponse>(await fetch(`${BASE}/summary/month_compare?ym=${ym}`));
}
