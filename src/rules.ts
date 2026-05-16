import type { Category } from "./types";

export const merchantRules: Record<string, Category> = {
  セブンイレブン: "食費",
  ファミリーマート: "食費",
  ローソン: "食費",
  マツモトキヨシ: "日用品",
  ウエルシア: "日用品",
  ENEOS: "交通",
  JR東日本: "交通"
};

export const ambiguousMerchants = [
  "Amazon",
  "楽天",
  "イオン",
  "ドン・キホーテ",
  "ドンキホーテ",
  "メルカリ"
];

export const itemKeywordRules: Record<string, Category> = {
  おにぎり: "食費",
  弁当: "食費",
  牛乳: "食費",
  洗剤: "日用品",
  シャンプー: "日用品",
  薬: "医療",
  ガソリン: "交通",
  本: "教育"
};
