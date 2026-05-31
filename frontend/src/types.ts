export type Category =
  | "食費" | "酒類" | "外食" | "日用品"
  | "交通費" | "医療費" | "娯楽費" | "衣料費" | "その他";

export const CATEGORIES: Category[] = [
  "食費", "酒類", "外食", "日用品",
  "交通費", "医療費", "娯楽費", "衣料費", "その他",
];

export const DEFAULT_TAX_RATE: Record<Category, number> = {
  "食費": 8, "酒類": 10, "外食": 10, "日用品": 10,
  "交通費": 10, "医療費": 10, "娯楽費": 10, "衣料費": 10, "その他": 10,
};

export interface CategoryMaster {
  name: string;
  description: string;
  tax_rate: number;
  sort_order: number;
  is_income: boolean;
}

export type TxStatus = "auto_saved" | "user_confirmed" | "manually_added";

export type TxKind = "expense" | "income";

export interface TransactionItem {
  id: number;
  transaction_id: number;
  name: string;
  amount: number;
  tax_amount: number;
  category: string | null;
  sort_order: number;
}

export interface Transaction {
  id: number;
  receipt_id: string | null;
  merchant_raw: string;
  merchant_normalized: string;
  items_text: string;
  screening_category: string | null;
  needs_review: boolean;
  reason: string;
  confidence: number;
  amount: number;
  tax_amount: number;
  purchased_at: string;
  memo: string | null;
  receipt_image_id: number | null;
  status: TxStatus;
  tx_type: TxKind;
  ocr_raw_text: string | null;
  created_at: string;
  updated_at: string;
  items?: TransactionItem[];
}


export interface UserCategoryOverride {
  id: number;
  merchant_pattern: string;
  category: string;
  created_at: string;
}
