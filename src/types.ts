export type Category =
  | "食費"
  | "日用品"
  | "交通"
  | "医療"
  | "通信"
  | "娯楽"
  | "教育"
  | "その他";

export type ReceiptInput = {
  merchantRaw: string;
  items?: string[];
  totalAmount?: number;
  purchasedAt?: string;
  userCategoryOverrides?: Partial<Record<string, Category>>;
};

export type CategoryScore = {
  category: Category;
  score: number;
};

export type ClassificationResult = {
  merchantNormalized: string;
  category: Category | null;
  confidence: number;
  needsReview: boolean;
  reason: string;
  reasons: string[];
  scores: CategoryScore[];
};
