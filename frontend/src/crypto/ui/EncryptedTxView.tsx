import { useEffect, useMemo, useState } from "react";
import { decryptJson, encryptJson, requireKey } from "../index";
import {
  createEncryptedTx,
  deleteEncryptedTx,
  fetchEncryptedTx,
  updateEncryptedTx,
  type EncryptedTxRow,
} from "../encryptedTxApi";
import {
  categoryOptionsWithCurrent,
  normalizeCategory,
} from "../categories";
import {
  normalizeEncryptedPayload,
  type EncryptedLineItem,
  type EncryptedTxPayload,
  type ManualEncryptedPayload,
  type ManualNoReceiptKind,
  type NormalizedEncryptedTx,
  type TxType,
} from "../txPayload";

type DecryptedRow = {
  id: number;
  raw: EncryptedTxRow;
  payload?: EncryptedTxPayload;
  normalized?: NormalizedEncryptedTx;
  error?: string;
};

type EditingState = {
  id: number;
  payload: EncryptedTxPayload;
  date: string;
  tx_type: TxType;
  merchant: string;
  amount: string;
  category: string;
  memo: string;
  payment_method: ManualNoReceiptKind;
  line_items: EncryptedLineItem[];
};

function todayIsoDate(): string {
  return new Date().toISOString().slice(0, 10);
}

function defaultLineItem(): EncryptedLineItem {
  return {
    name: "",
    amount: 0,
    category: "未分類",
  };
}

function paymentMethodLabel(method: ManualNoReceiptKind | undefined): string {
  switch (method) {
    case "cash":
      return "現金";
    case "split_bill":
    case "vending_machine":
      return "その他";
    case "other":
      return "その他";
    default:
      return "";
  }
}

function buildPayloadFromEdit(edit: EditingState): EncryptedTxPayload {
  const amount = Math.round(Number(edit.amount));

  const lineItems = edit.line_items.map((item) => ({
    ...item,
    name: item.name || edit.merchant || "明細",
    amount: Math.round(Number(item.amount) || 0),
    category: normalizeCategory(item.category || edit.category),
  }));

  if (edit.payload.source === "receipt_ocr") {
    return {
      ...edit.payload,
      preview: {
        ...edit.payload.preview,
        purchased_at: edit.date,
        merchant_raw: edit.merchant,
        amount,
        category: normalizeCategory(edit.category),
        line_items: lineItems.map((item) => ({
          item: item.name,
          amount: item.amount,
          category: item.category,
        })),
      },
    };
  }

  return {
    source: "manual",
    version: 1,
    date: edit.date,
    tx_type: edit.tx_type,
    merchant: edit.merchant,
    amount,
    category: normalizeCategory(edit.category),
    memo: edit.memo,
    payment_method: edit.payment_method,
    line_items: lineItems,
  };
}

type EncryptedTxViewProps = {
  refreshKey?: number;
};

export function EncryptedTxView({ refreshKey = 0 }: EncryptedTxViewProps) {
  const [date, setDate] = useState(todayIsoDate());
  const [txType, setTxType] = useState<TxType>("expense");
  const [merchant, setMerchant] = useState("");
  const [amount, setAmount] = useState("1000");
  const [category, setCategory] = useState("未分類");
  const [memo, setMemo] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<ManualNoReceiptKind>("cash");

  const [rows, setRows] = useState<DecryptedRow[]>([]);
  const [editing, setEditing] = useState<EditingState | null>(null);
  const [message, setMessage] = useState("");

  const sortedRows = useMemo(() => {
    return [...rows].sort((a, b) => {
      const ad = a.normalized?.date ?? "";
      const bd = b.normalized?.date ?? "";
      return bd.localeCompare(ad);
    });
  }, [rows]);

  async function loadRows() {
    setMessage("");
    const key = requireKey();
    const encryptedRows = await fetchEncryptedTx();

    const decryptedRows = await Promise.all(
      encryptedRows.map(async (row): Promise<DecryptedRow> => {
        try {
          const record = JSON.parse(row.encrypted_payload);
          const payload = await decryptJson<EncryptedTxPayload>(key, record);
          return {
            id: row.id,
            raw: row,
            payload,
            normalized: normalizeEncryptedPayload(payload),
          };
        } catch (e) {
          return {
            id: row.id,
            raw: row,
            error: e instanceof Error ? e.message : String(e),
          };
        }
      }),
    );

    setRows(decryptedRows);
  }

  async function handleCreateManual() {
    setMessage("");

    try {
      const n = Number(amount);
      if (!Number.isFinite(n) || n <= 0) {
        setMessage("金額は1以上の数値で入力してください");
        return;
      }

      const normalizedCategory = normalizeCategory(category);

      const payload: ManualEncryptedPayload = {
        source: "manual",
        version: 1,
        date,
        tx_type: txType,
        merchant,
        amount: Math.round(n),
        category: normalizedCategory,
        memo,
        payment_method: paymentMethod,
        line_items: [
          {
            name: merchant || paymentMethodLabel(paymentMethod) || "手入力",
            amount: Math.round(n),
            category: normalizedCategory,
            memo,
          },
        ],
      };

      const encryptedRecord = await encryptJson(requireKey(), payload);
      await createEncryptedTx(JSON.stringify(encryptedRecord), 1);

      setMerchant("");
      setMemo("");
      await loadRows();
      setMessage("手入力取引を暗号化保存しました");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    }
  }

  function startEdit(row: DecryptedRow) {
    if (!row.payload || !row.normalized) {
      setMessage("復号できない行は編集できません");
      return;
    }

    setEditing({
      id: row.id,
      payload: row.payload,
      date: row.normalized.date,
      tx_type: row.normalized.tx_type,
      merchant: row.normalized.merchant,
      amount: String(row.normalized.amount),
      category: normalizeCategory(row.normalized.category),
      memo: row.normalized.memo,
      payment_method: row.normalized.payment_method || "cash",
      line_items:
        row.normalized.line_items.length > 0
          ? row.normalized.line_items.map((item) => ({
              ...item,
              category: normalizeCategory(item.category),
            }))
          : [defaultLineItem()],
    });
  }

  async function handleUpdate() {
    if (!editing) return;

    const n = Number(editing.amount);
    if (!Number.isFinite(n) || n <= 0) {
      setMessage("金額は1以上の数値で入力してください");
      return;
    }

    const updatedPayload = buildPayloadFromEdit(editing);
    const encryptedRecord = await encryptJson(requireKey(), updatedPayload);

    await updateEncryptedTx(editing.id, JSON.stringify(encryptedRecord), 1);

    setEditing(null);
    await loadRows();
    setMessage("更新しました");
  }

  async function handleDelete(id: number) {
    await deleteEncryptedTx(id);
    await loadRows();
  }

  useEffect(() => {
    void loadRows().catch((e) => {
      setMessage(e instanceof Error ? e.message : String(e));
    });
  }, [refreshKey]);

  return (
    <section style={{ border: "1px solid #ddd", padding: 16, marginTop: 16 }}>
      <h2>取引一覧</h2>
      <p className="hint">
        encrypted_transactions を取得し、ブラウザ側で復号して表示・編集します。
      </p>

      <div style={{ display: "grid", gap: 8, maxWidth: 460 }}>
        <h3>レシートなし手入力</h3>

        <label>
          日付
          <input value={date} onChange={(e) => setDate(e.target.value)} />
        </label>

        <label>
          種別
          <select
            value={txType}
            onChange={(e) => setTxType(e.target.value as TxType)}
          >
            <option value="expense">支出</option>
            <option value="income">収入</option>
          </select>
        </label>

        <label>
          種類
          <select
            value={paymentMethod}
            onChange={(e) =>
              setPaymentMethod(e.target.value as ManualNoReceiptKind)
            }
          >
            <option value="cash">現金</option>
            
            <option value="other">その他</option>
          </select>
        </label>

        <label>
          店舗・相手先
          <input value={merchant} onChange={(e) => setMerchant(e.target.value)} />
        </label>

        <label>
          金額
          <input value={amount} onChange={(e) => setAmount(e.target.value)} />
        </label>

        <label>
          カテゴリ
          <select value={category} onChange={(e) => setCategory(e.target.value)}>
            {categoryOptionsWithCurrent(txType, category).map((c) => (
              <option key={c} value={c}>
                {c}
              </option>
            ))}
          </select>
        </label>

        <label>
          メモ
          <input value={memo} onChange={(e) => setMemo(e.target.value)} />
        </label>

        <button onClick={() => void handleCreateManual()}>
          手入力を暗号化保存
        </button>

        <button onClick={() => void loadRows()}>
          再読み込み
        </button>
      </div>

      {message && <p>{message}</p>}

      {editing && (
        <div style={{ border: "1px solid #aaa", padding: 12, marginTop: 16 }}>
          <h3>編集</h3>

          <div style={{ display: "grid", gap: 8, maxWidth: 560 }}>
            <label>
              日付
              <input
                value={editing.date}
                onChange={(e) =>
                  setEditing({ ...editing, date: e.target.value })
                }
              />
            </label>

            <label>
              種別
              <select
                value={editing.tx_type}
                onChange={(e) =>
                  setEditing({ ...editing, tx_type: e.target.value as TxType })
                }
              >
                <option value="expense">支出</option>
                <option value="income">収入</option>
              </select>
            </label>

            <label>
              種類
              <select
                value={editing.payment_method}
                onChange={(e) =>
                  setEditing({
                    ...editing,
                    payment_method: e.target.value as ManualNoReceiptKind,
                  })
                }
              >
                <option value="cash">現金</option>
                <option value="other">その他</option>
              </select>
            </label>

            <label>
              店舗・相手先
              <input
                value={editing.merchant}
                onChange={(e) =>
                  setEditing({ ...editing, merchant: e.target.value })
                }
              />
            </label>

            <label>
              金額
              <input
                value={editing.amount}
                onChange={(e) =>
                  setEditing({ ...editing, amount: e.target.value })
                }
              />
            </label>

            <label>
              カテゴリ
              <select
                value={editing.category}
                onChange={(e) =>
                  setEditing({ ...editing, category: e.target.value })
                }
              >
                {categoryOptionsWithCurrent(editing.tx_type, editing.category).map(
                  (c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ),
                )}
              </select>
            </label>

            <label>
              メモ
              <input
                value={editing.memo}
                onChange={(e) =>
                  setEditing({ ...editing, memo: e.target.value })
                }
              />
            </label>

            <h4>明細</h4>
            {editing.line_items.map((item, index) => (
              <div
                key={index}
                style={{
                  display: "grid",
                  gridTemplateColumns: "2fr 1fr 1fr auto",
                  gap: 8,
                }}
              >
                <input
                  value={item.name}
                  placeholder="品目"
                  onChange={(e) => {
                    const next = [...editing.line_items];
                    next[index] = { ...item, name: e.target.value };
                    setEditing({ ...editing, line_items: next });
                  }}
                />
                <input
                  value={item.amount}
                  placeholder="金額"
                  onChange={(e) => {
                    const next = [...editing.line_items];
                    next[index] = {
                      ...item,
                      amount: Number(e.target.value) || 0,
                    };
                    setEditing({ ...editing, line_items: next });
                  }}
                />
                <select
                  value={normalizeCategory(item.category)}
                  onChange={(e) => {
                    const next = [...editing.line_items];
                    next[index] = { ...item, category: e.target.value };
                    setEditing({ ...editing, line_items: next });
                  }}
                >
                  {categoryOptionsWithCurrent("expense", item.category).map((c) => (
                    <option key={c} value={c}>
                      {c}
                    </option>
                  ))}
                </select>
                <button
                  onClick={() => {
                    const next = editing.line_items.filter((_, i) => i !== index);
                    setEditing({
                      ...editing,
                      line_items: next.length > 0 ? next : [defaultLineItem()],
                    });
                  }}
                >
                  削除
                </button>
              </div>
            ))}


            <div style={{ display: "flex", gap: 8 }}>
                <button onClick={() => void handleUpdate()}>更新</button>
                <button onClick={() => setEditing(null)}>キャンセル</button>
              </div>
            </div>
          </div>
        )}

        <div style={{ marginTop: 16 }}>
          <h3>保存済み取引</h3>

          {rows.length === 0 ? (
            <p>取引はまだありません。</p>
          ) : (
            <table>
              <thead>
                <tr>
                  <th>日付</th>
                  <th>種別</th>
                  <th>種類</th>
                  <th>店舗・相手先</th>
                  <th>金額</th>
                  <th>カテゴリ</th>
                  <th>メモ</th>
                  <th>操作</th>
                </tr>
              </thead>
              <tbody>
                {sortedRows.map((row) => (
                  <tr key={row.id}>
                    <td>{row.normalized?.date ?? ""}</td>
                    <td>{row.normalized?.tx_type === "income" ? "収入" : "支出"}</td>
                    <td>{paymentMethodLabel(row.normalized?.payment_method)}</td>
                    <td>{row.normalized?.merchant ?? ""}</td>
                    <td>{row.normalized?.amount ?? ""}</td>
                    <td>{row.normalized?.category ?? ""}</td>
                    <td>{row.normalized?.memo ?? ""}</td>
                    <td>
                      <button onClick={() => startEdit(row)}>編集</button>
                      <button onClick={() => void handleDelete(row.id)}>削除</button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      </section>
    );
  }
