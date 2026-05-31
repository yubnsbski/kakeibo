export type TxType = "expense" | "income";

export type ManualNoReceiptKind =
  | "cash"
  | "split_bill"
  | "vending_machine"
  | "other";

export type EncryptedLineItem = {
  name: string;
  amount: number;
  category: string;
  memo?: string;
};

export type ManualEncryptedPayload = {
  source: "manual";
  version: 1;
  date: string;
  tx_type: TxType;
  merchant: string;
  amount: number;
  category: string;
  memo: string;
  payment_method: ManualNoReceiptKind;
  line_items: EncryptedLineItem[];
};

export type ReceiptOcrEncryptedPayload = {
  source: "receipt_ocr";
  saved_mode: "encrypted";
  version: 1;
  preview: {
    purchased_at: string;
    merchant_raw: string;
    amount: number;
    tax_amount: number;
    category: string | null;
    raw_text?: string;
    line_items: Array<{
      item: string;
      amount: number;
      category: string | null;
    }>;
  };
};

export type EncryptedTxPayload =
  | ManualEncryptedPayload
  | ReceiptOcrEncryptedPayload;

export type NormalizedEncryptedTx = {
  date: string;
  tx_type: TxType;
  merchant: string;
  amount: number;
  category: string;
  memo: string;
  source: "manual" | "receipt_ocr";
  payment_method?: ManualNoReceiptKind;
  line_items: EncryptedLineItem[];
};

export function normalizeEncryptedPayload(
  payload: EncryptedTxPayload,
): NormalizedEncryptedTx {
  if (payload.source === "receipt_ocr") {
    const lineItems: EncryptedLineItem[] = payload.preview.line_items.map((item) => ({
      name: item.item,
      amount: item.amount,
      category: item.category || payload.preview.category || "未分類",
    }));

    return {
      date: payload.preview.purchased_at,
      tx_type: "expense",
      merchant: payload.preview.merchant_raw || "(不明)",
      amount: payload.preview.amount,
      category: payload.preview.category || "未分類",
      memo: `OCR明細 ${lineItems.length}件`,
      source: "receipt_ocr",
      line_items: lineItems,
    };
  }

  return {
    date: payload.date,
    tx_type: payload.tx_type,
    merchant: payload.merchant || "(手入力)",
    amount: payload.amount,
    category: payload.category || "未分類",
    memo: payload.memo || "",
    source: "manual",
    payment_method: payload.payment_method,
    line_items:
      payload.line_items && payload.line_items.length > 0
        ? payload.line_items
        : [
            {
              name: payload.merchant || "手入力",
              amount: payload.amount,
              category: payload.category || "未分類",
              memo: payload.memo,
            },
          ],
  };
}

export function categoryExpenseSummary(
  rows: NormalizedEncryptedTx[],
): Array<{ category: string; amount: number }> {
  const byCategory = new Map<string, number>();

  for (const row of rows) {
    if (row.tx_type !== "expense") continue;

    for (const item of row.line_items) {
      const category = item.category || row.category || "未分類";
      byCategory.set(category, (byCategory.get(category) ?? 0) + item.amount);
    }
  }

  return [...byCategory.entries()]
    .map(([category, amount]) => ({ category, amount }))
    .sort((a, b) => b.amount - a.amount);
}

export function totalIncome(rows: NormalizedEncryptedTx[]): number {
  return rows
    .filter((row) => row.tx_type === "income")
    .reduce((sum, row) => sum + row.amount, 0);
}

export function totalExpense(rows: NormalizedEncryptedTx[]): number {
  return rows
    .filter((row) => row.tx_type === "expense")
    .reduce((sum, row) => sum + row.amount, 0);
}
