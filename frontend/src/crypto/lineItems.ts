export type LineItemDraft = {
  name: string;
  amount: string;
  category: string;
};

export type ValidatedLineItem = {
  name: string;
  amount: number;
  category: string;
  memo?: string;
};

export function emptyLineItemDraft(
  category: string,
  initialAmount = 0,
): LineItemDraft {
  if (!Number.isFinite(initialAmount) || !Number.isInteger(initialAmount)) {
    throw new Error("明細の初期金額は整数で指定してください");
  }

  return {
    name: "",
    amount: String(initialAmount),
    category: category.trim() || "未分類",
  };
}

export function lineItemTotal(items: Array<{ amount: number }>): number {
  return items.reduce((sum, item) => sum + item.amount, 0);
}

export function buildManualLineItems(
  drafts: LineItemDraft[],
  options: {
    totalAmount: number;
    fallbackName: string;
    fallbackCategory: string;
    memo?: string;
  },
): ValidatedLineItem[] {
  const fallbackCategory = options.fallbackCategory.trim() || "未分類";

  if (drafts.length === 0) {
    return [
      {
        name: options.fallbackName.trim() || "手入力",
        amount: options.totalAmount,
        category: fallbackCategory,
        memo: options.memo,
      },
    ];
  }

  const items = drafts.map((draft, index): ValidatedLineItem => {
    const name = draft.name.trim();
    if (!name) {
      throw new Error(`明細${index + 1}の品目名を入力してください`);
    }

    const rawAmount = draft.amount.trim();
    if (!rawAmount) {
      throw new Error(`明細${index + 1}の金額を入力してください`);
    }

    const amount = Number(rawAmount);
    if (!Number.isFinite(amount) || !Number.isInteger(amount)) {
      throw new Error(`明細${index + 1}の金額は整数で入力してください`);
    }

    return {
      name,
      amount,
      category: draft.category.trim() || fallbackCategory,
      memo: options.memo,
    };
  });

  assertLineItemTotal(items, options.totalAmount);
  return items;
}

export function assertLineItemTotal(
  items: Array<{ amount: number }>,
  totalAmount: number,
): void {
  const detailTotal = lineItemTotal(items);
  if (detailTotal === totalAmount) return;

  const difference = totalAmount - detailTotal;
  const adjustmentExample =
    difference < 0
      ? `割引明細を${difference.toLocaleString()}円で追加`
      : `調整明細を+${difference.toLocaleString()}円で追加`;

  throw new Error(
    `明細合計${detailTotal.toLocaleString()}円と取引金額` +
      `${totalAmount.toLocaleString()}円が一致しません。${adjustmentExample}してください`,
  );
}
