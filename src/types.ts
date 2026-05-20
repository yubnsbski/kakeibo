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

export type ClassificationResult = {
  merchantNormalized: string;
  category: Category | null;
  confidence: number;
  needsReview: boolean;
  reason: string;
  reasons: string[];
  screeningLabel: "recordable" | "needs_review";
};

export type ItemClassification = {
  text: string;
  category: Category | null;
  reason: string;
  matchedKeyword: string | null;
};

export type ReceiptBreakdown = {
  merchantNormalized: string;
  items: ItemClassification[];
  dominantCategory: Category | null;
  isMixed: boolean;
  needsReview: boolean;
};

export type CategoryAllocation = {
  category: Category | null;
  amount: number;
  itemTexts: string[];
};

export type AmountAllocationResult = {
  totalAmount: number;
  allocations: CategoryAllocation[];
  strategy: "per_item_amounts" | "equal_split";
  unclassifiedAmount: number;
};
