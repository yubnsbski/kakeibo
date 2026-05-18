import type {
  CategoryMaster, ReceiptUploadResponse, Transaction, TransactionItem,
  UserCategoryOverride,
} from "./types";

const BASE = "/api";

async function handle<T>(r: Response): Promise<T> {
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
  return r.json() as Promise<T>;
}

export async function uploadReceipt(file: File): Promise<ReceiptUploadResponse> {
  const fd = new FormData();
  fd.append("file", file);
  const r = await fetch(`${BASE}/receipts/upload`, { method: "POST", body: fd });
  return handle<ReceiptUploadResponse>(r);
}

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
  const r = await fetch(`${BASE}/transactions/${id}`);
  return handle<Transaction>(r);
}

export async function updateTransaction(
  id: number, patch: Partial<Transaction>
): Promise<Transaction> {
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

export async function listOverrides(): Promise<UserCategoryOverride[]> {
  const r = await fetch(`${BASE}/overrides`);
  return handle<UserCategoryOverride[]>(r);
}

export async function createOverride(
  merchant_pattern: string, category: string
): Promise<UserCategoryOverride> {
  const r = await fetch(`${BASE}/overrides`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ merchant_pattern, category }),
  });
  return handle<UserCategoryOverride>(r);
}

export async function listCategories(): Promise<CategoryMaster[]> {
  const r = await fetch(`${BASE}/categories`);
  return handle<CategoryMaster[]>(r);
}

// ===== Items =====

export async function createItem(
  txId: number,
  item: { name: string; amount: number; category: string | null; sort_order?: number }
): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items`, {
    method: "POST", headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ ...item, sort_order: item.sort_order ?? 0 }),
  });
  return handle<TransactionItem>(r);
}

export async function updateItem(
  txId: number, itemId: number, patch: Partial<TransactionItem>
): Promise<TransactionItem> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, {
    method: "PATCH", headers: { "Content-Type": "application/json" },
    body: JSON.stringify(patch),
  });
  return handle<TransactionItem>(r);
}

export async function deleteItem(txId: number, itemId: number): Promise<void> {
  const r = await fetch(`${BASE}/transactions/${txId}/items/${itemId}`, {
    method: "DELETE",
  });
  if (!r.ok) throw new Error(`${r.status}: ${await r.text()}`);
}
