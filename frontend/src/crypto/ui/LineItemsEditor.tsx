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

type DraftEditorProps = {
  items: LineItemDraft[];
  txType: TxType;
  defaultCategory: string;
  disabled?: boolean;
  onChange: (items: LineItemDraft[]) => void;
};

export function DraftLineItemsEditor({
  items,
  txType,
  defaultCategory,
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

  return (
    <div style={{ display: "grid", gap: 8 }}>
      <h4 style={{ marginBottom: 0 }}>明細（任意）</h4>
      <p className="hint" style={{ margin: 0 }}>
        明細を追加しない場合は取引金額と同額の明細を自動生成します。
        割引・調整はマイナス金額の明細として追加できます。
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
          disabled={disabled}
          onClick={() =>
            onChange([...items, emptyLineItemDraft(defaultCategory)])
          }
        >
          明細を追加
        </button>
        {items.length > 0 && (
          <span className="hint">
            明細合計: {total === null ? "入力確認中" : `${total.toLocaleString()}円`}
          </span>
        )}
      </div>
    </div>
  );
}

type StoredEditorProps = {
  items: EncryptedLineItem[];
  txType: TxType;
  defaultCategory: string;
  disabled?: boolean;
  onChange: (items: EncryptedLineItem[]) => void;
};

export function StoredLineItemsEditor({
  items,
  txType,
  defaultCategory,
  disabled = false,
  onChange,
}: StoredEditorProps) {
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
                        amount: 0,
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
        <span className="hint">
          明細合計: {lineItemTotal(items).toLocaleString()}円
        </span>
      </div>
    </div>
  );
}
