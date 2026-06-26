import {
  categoryOptionsWithCurrent,
  normalizeCategory,
} from "../categories";
import {
  emptyLineItemDraft,
  lineItemTotal,
  type LineItemDraft,
} from "../lineItems";
import type { EncryptedLineItem, TxType } from "../txPayload";

const rowStyle: React.CSSProperties = {
  display: "grid",
  gridTemplateColumns: "minmax(160px, 2fr) minmax(120px, 1fr) minmax(100px, 1fr) auto",
  gap: 8,
  alignItems: "center",
};

function adjustmentLabel(difference: number): string {
  return difference < 0 ? "割引" : "調整";
}

function TotalStatus({
  total,
  expectedAmount,
}: {
  total: number | null;
  expectedAmount?: number;
}) {
  if (total === null) {
    return <span className="hint">明細合計: 入力確認中</span>;
  }

  if (expectedAmount === undefined) {
    return <span className="hint">明細合計: {total.toLocaleString()}円</span>;
  }

  const difference = expectedAmount - total;
  return (
    <span className={difference === 0 ? "hint" : "err"}>
      明細合計: {total.toLocaleString()}円 / 計算結果: {expectedAmount.toLocaleString()}円
      {difference !== 0 && ` / 差額: ${difference.toLocaleString()}円`}
    </span>
  );
}

type DraftEditorProps = {
  items: LineItemDraft[];
  txType: TxType;
  defaultCategory: string;
  expectedAmount?: number;
  disabled?: boolean;
  onChange: (items: LineItemDraft[]) => void;
};

export function DraftLineItemsEditor({
  items,
  txType,
  defaultCategory,
  expectedAmount,
  disabled = false,
  onChange,
}: DraftEditorProps) {
  const parsedAmounts = items.map((item) => Number(item.amount));
  const canShowTotal = parsedAmounts.every(
    (amount) => Number.isFinite(amount) && Number.isInteger(amount),
  );
  const total = canShowTotal
    ? parsedAmounts.reduce((sum, amount) => sum + amount, 0)
    : null;
  const difference =
    expectedAmount !== undefined && total !== null
      ? expectedAmount - total
      : null;

  function addLineItem() {
    const initialAmount =
      items.length === 0 && expectedAmount !== undefined
        ? expectedAmount
        : 0;
    onChange([
      ...items,
      emptyLineItemDraft(defaultCategory, initialAmount),
    ]);
  }

  return (
    <div style={{ display: "grid", gap: 8 }}>
      <h4 style={{ marginBottom: 0 }}>明細（任意）</h4>
      <p className="hint" style={{ margin: 0 }}>
        最初の明細には現在の税込計算結果を自動入力します。
        2件目以降は0円から追加し、割引・調整はマイナス金額で入力できます。
      </p>

      {items.map((item, index) => (
        <div key={index} style={rowStyle}>
          <input
            value={item.name}
            placeholder={`品目${index + 1}`}
            disabled={disabled}
            onChange={(event) => {
              const next = [...items];
              next[index] = { ...item, name: event.target.value };
              onChange(next);
            }}
          />
          <select
            value={normalizeCategory(item.category)}
            disabled={disabled}
            onChange={(event) => {
              const next = [...items];
              next[index] = { ...item, category: event.target.value };
              onChange(next);
            }}
          >
            {categoryOptionsWithCurrent(txType, item.category).map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
          <input
            type="number"
            step="1"
            value={item.amount}
            placeholder="金額"
            disabled={disabled}
            onChange={(event) => {
              const next = [...items];
              next[index] = { ...item, amount: event.target.value };
              onChange(next);
            }}
          />
          <button
            type="button"
            disabled={disabled}
            onClick={() => onChange(items.filter((_item, i) => i !== index))}
          >
            削除
          </button>
        </div>
      ))}

      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <button
          type="button"
          disabled={disabled || expectedAmount === undefined}
          onClick={addLineItem}
        >
          明細を追加
        </button>
        {expectedAmount === undefined && items.length === 0 && (
          <span className="hint">先に金額を計算してください。</span>
        )}
        {items.length > 0 && (
          <TotalStatus total={total} expectedAmount={expectedAmount} />
        )}
        {items.length > 0 && difference !== null && difference !== 0 && (
          <button
            type="button"
            disabled={disabled}
            onClick={() =>
              onChange([
                ...items,
                {
                  name: adjustmentLabel(difference),
                  amount: String(difference),
                  category: normalizeCategory(defaultCategory),
                },
              ])
            }
          >
            差額{difference.toLocaleString()}円を明細に追加
          </button>
        )}
      </div>
    </div>
  );
}

type StoredEditorProps = {
  items: EncryptedLineItem[];
  txType: TxType;
  defaultCategory: string;
  expectedAmount?: number;
  disabled?: boolean;
  onChange: (items: EncryptedLineItem[]) => void;
};

export function StoredLineItemsEditor({
  items,
  txType,
  defaultCategory,
  expectedAmount,
  disabled = false,
  onChange,
}: StoredEditorProps) {
  const total = lineItemTotal(items);
  const difference =
    expectedAmount === undefined ? null : expectedAmount - total;

  return (
    <div style={{ display: "grid", gap: 8 }}>
      <h4 style={{ marginBottom: 0 }}>明細</h4>
      <p className="hint" style={{ margin: 0 }}>
        手入力取引は保存時に明細合計と取引金額を照合します。
        割引・調整はマイナス金額で入力できます。
      </p>

      {items.map((item, index) => (
        <div key={index} style={rowStyle}>
          <input
            value={item.name}
            placeholder={`品目${index + 1}`}
            disabled={disabled}
            onChange={(event) => {
              const next = [...items];
              next[index] = { ...item, name: event.target.value };
              onChange(next);
            }}
          />
          <select
            value={normalizeCategory(item.category)}
            disabled={disabled}
            onChange={(event) => {
              const next = [...items];
              next[index] = { ...item, category: event.target.value };
              onChange(next);
            }}
          >
            {categoryOptionsWithCurrent(txType, item.category).map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
          <input
            type="number"
            step="1"
            value={item.amount}
            placeholder="金額"
            disabled={disabled}
            onChange={(event) => {
              const next = [...items];
              next[index] = {
                ...item,
                amount: Number(event.target.value) || 0,
              };
              onChange(next);
            }}
          />
          <button
            type="button"
            disabled={disabled}
            onClick={() => {
              const next = items.filter((_item, i) => i !== index);
              onChange(
                next.length > 0
                  ? next
                  : [
                      {
                        name: "",
                        amount: expectedAmount ?? 0,
                        category: normalizeCategory(defaultCategory),
                      },
                    ],
              );
            }}
          >
            削除
          </button>
        </div>
      ))}

      <div style={{ display: "flex", gap: 8, alignItems: "center", flexWrap: "wrap" }}>
        <button
          type="button"
          disabled={disabled}
          onClick={() =>
            onChange([
              ...items,
              {
                name: "",
                amount: 0,
                category: normalizeCategory(defaultCategory),
              },
            ])
          }
        >
          明細を追加
        </button>
        <TotalStatus total={total} expectedAmount={expectedAmount} />
        {difference !== null && difference !== 0 && (
          <button
            type="button"
            disabled={disabled}
            onClick={() =>
              onChange([
                ...items,
                {
                  name: adjustmentLabel(difference),
                  amount: difference,
                  category: normalizeCategory(defaultCategory),
                },
              ])
            }
          >
            差額{difference.toLocaleString()}円を明細に追加
          </button>
        )}
      </div>
    </div>
  );
}
