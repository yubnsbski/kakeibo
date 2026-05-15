import { describe, expect, test } from "vitest";
import { classifyReceipt } from "../src/classifyReceipt";

type ReceiptInput = Parameters<typeof classifyReceipt>[0];
type ClassificationResult = ReturnType<typeof classifyReceipt>;

type EvaluationCase = {
  name: string;
  input: ReceiptInput;
  expected: {
    category: ClassificationResult["category"];
    needsReview: boolean;
  };
};

const cases: EvaluationCase[] = [
  {
    name: "seven half-width alias is food",
    input: {
      merchantRaw: "ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
      items: ["おにぎり", "牛乳"],
      totalAmount: 620
    },
    expected: {
      category: "食費",
      needsReview: false
    }
  },
  {
    name: "matsumoto kiyoshi detergent is daily goods",
    input: {
      merchantRaw: "マツモトキヨシ 新宿店",
      items: ["洗剤"],
      totalAmount: 480
    },
    expected: {
      category: "日用品",
      needsReview: false
    }
  },
  {
    name: "eneos gasoline is transportation",
    input: {
      merchantRaw: "ENEOS",
      items: ["ガソリン"],
      totalAmount: 3000
    },
    expected: {
      category: "交通",
      needsReview: false
    }
  },
  {
    name: "amazon without items requires review",
    input: {
      merchantRaw: "Amazon.co.jp",
      items: [],
      totalAmount: 3000
    },
    expected: {
      category: null,
      needsReview: true
    }
  },
  {
    name: "rakuten without items requires review",
    input: {
      merchantRaw: "楽天市場",
      items: [],
      totalAmount: 2500
    },
    expected: {
      category: null,
      needsReview: true
    }
  },
  {
    name: "unknown merchant without items requires review",
    input: {
      merchantRaw: "不明店舗",
      items: [],
      totalAmount: 1200
    },
    expected: {
      category: null,
      needsReview: true
    }
  }
];

describe("classification evaluation matrix", () => {
  for (const evaluationCase of cases) {
    test(evaluationCase.name, () => {
      const result = classifyReceipt(evaluationCase.input);

      expect(result.category).toBe(evaluationCase.expected.category);
      expect(result.needsReview).toBe(evaluationCase.expected.needsReview);

      if ("confidence" in result && typeof result.confidence === "number") {
        expect(result.confidence).toBeGreaterThanOrEqual(0);
        expect(result.confidence).toBeLessThanOrEqual(1);
      }
    });
  }
});
