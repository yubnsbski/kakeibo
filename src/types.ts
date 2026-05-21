import type { AllocationInput } from "./walletEngine";

export type Category =
  | "食費"
  | "日用品"
  | "交通"
  | "医療"
  | "通信"
  | "娯楽"
  | "教育"
  | "その他";

export type TransactionType = "expense" | "income";

export type ManualTransactionItemInput = {
  name: string;
  amount: number;
  category?: Category;
};

export type ManualTransactionInput = {
  type: TransactionType;
  merchantRaw: string;
  purchasedAt: string;
  items: ManualTransactionItemInput[];
  memo?: string;
};

export type ManualTransactionConversionResult =
  | { ok: true; value: AllocationInput }
  | {
    ok: false;
    error:
      | "UNSUPPORTED_TRANSACTION_TYPE"
      | "missing_merchant"
      | "invalid_total_amount"
      | "invalid_purchased_at"
      | "invalid_transaction_type"
      | "missing_items"
      | "missing_item_name"
      | "invalid_item_amount"
      | "invalid_item_category";
  };

export type ReceiptInput = {
  merchantRaw: string;
  items?: string[];
  totalAmount?: number;
  purchasedAt?: string;
  userCategoryOverrides?: Partial<Record<string, Category>>;
};

export type ClassificationResult = {
  merchantNormalized: string;
  category: Category | null;
  confidence: number;
  needsReview: boolean;
  reason: string;
  reasons: string[];
  screeningLabel: "recordable" | "needs_review";
};
