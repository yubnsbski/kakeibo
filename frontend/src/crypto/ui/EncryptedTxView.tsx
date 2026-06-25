import { useEffect, useMemo, useState } from "react";
import {
  calculateAmount,
  type AmountCalculationResponse,
} from "../../api";
import { decryptJson, encryptJson, requireKey } from "../index";
import {
  createEncryptedTx,
  deleteEncryptedTx,
  fetchEncryptedTx,
  updateEncryptedTx,
  type EncryptedTxRow,
} from "../encryptedTxApi";
import {
  categoryOptions,
  categoryOptionsWithCurrent,
  defaultTaxRate,
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
import { DataIntegrityCheck } from "./DataIntegrityCheck";

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
  category: string;
  amount_expression: string;
  tax_rate: string;
  memo: string;
  payment_method: ManualNoReceiptKind;
  line_items: EncryptedLineItem[];
};

function todayLocalIsoDate(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function defaultLineItem(category = "未分類"): EncryptedLineItem {
  return {
    name: "",
    amount: 0,
    category,
  };
}

function paymentMethodLabel(method: ManualNoReceiptKind | undefined): string {
  switch (method) {
    case "cash":
      return "現金";
    case "split_bill":
    case "vending_machine":
    case "other":
      return "その他";
    default:
      return "";
  }
}

function parseTaxRate(value: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 100) {
    throw new Error("税率は0〜100の整数で入力してください");
  }
  return parsed;
}

function yen(value: number | undefined): string {
  return typeof value === "number" && Number.isFinite(value)
    ? `${value.toLocaleString()}円`
    : "-";
}

function taxRateLabel(value: number | undefined): string {
  return typeof value === "number" && Number.isFinite(value) ? `${value}%` : "-";
}

function normalizedLineItems(
  edit: EditingState,
  calculation: AmountCalculationResponse,
): EncryptedLineItem[] {
  const category = normalizeCategory(edit.category);
  const items = edit.line_items.map((item) => {
    const itemAmount = Number(item.amount);
    return {
      ...item,
      name: item.name || edit.merchant || "明細",
      amount:
        Number.isFinite(itemAmount) && itemAmount >= 0 ? Math.round(itemAmount) : 0,
      category: normalizeCategory(item.category || category),
    };
  });

  // 通常の手入力は単一明細なので、式の計算結果と明細額を同期する。
  if (edit.payload.source === "manual" && items.length === 1) {
    items[0] = { ...items[0], amount: calculation.amount };
  }

  return items;
}

function buildPayloadFromEdit(
  edit: EditingState,
  calculation: AmountCalculationResponse,
): EncryptedTxPayload {
  const category = normalizeCategory(edit.category);
  const lineItems = normalizedLineItems(edit, calculation);

  if (edit.payload.source === "receipt_ocr") {
    return {
      ...edit.payload,
      preview: {
        ...edit.payload.preview,
        purchased_at: edit.date,
        merchant_raw: edit.merchant,
        amount: calculation.amount,
        tax_rate: calculation.tax_rate,
        tax_amount: calculation.tax_amount,
        category,
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
    amount_expression: edit.amount_expression.trim(),
    amount: calculation.amount,
    tax_rate: calculation.tax_rate,
    tax_amount: calculation.tax_amount,
    category,
    memo: edit.memo,
    payment_method: edit.payment_method,
    line_items: lineItems,
  };
}

type EncryptedTxViewProps = {
  refreshKey?: number;
};

export function EncryptedTxView({ refreshKey = 0 }: EncryptedTxViewProps) {
  const [date, setDate] = useState(todayLocalIsoDate());
  const [txType, setTxType] = useState<TxType>("expense");
  const [merchant, setMerchant] = useState("");
  const [category, setCategory] = useState("未分類");
  const [amountExpression, setAmountExpression] = useState("1000");
  const [taxRate, setTaxRate] = useState(
    String(defaultTaxRate("expense", "未分類")),
  );
  const [memo, setMemo] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<ManualNoReceiptKind>("cash");

  const [rows, setRows] = useState<DecryptedRow[]>([]);
  const [editing, setEditing] = useState<EditingState | null>(null);
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  const sortedRows = useMemo(() => {
    return [...rows].sort((a, b) => {
      const ad = a.normalized?.date ?? "";
      const bd = b.normalized?.date ?? "";
      return bd.localeCompare(ad);
    });
  }, [rows]);

  async function loadRows() {
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

  function changeTxType(nextType: TxType) {
    const nextCategory = categoryOptions(nextType)[0] ?? "未分類";
    setTxType(nextType);
    setCategory(nextCategory);
    setTaxRate(String(defaultTaxRate(nextType, nextCategory)));
  }

  function changeCategory(nextCategory: string) {
    setCategory(nextCategory);
    setTaxRate(String(defaultTaxRate(txType, nextCategory)));
  }

  async function handleCreateManual() {
    setMessage("");
    setSaving(true);

    try {
      const parsedTaxRate = parseTaxRate(taxRate);
      const calculation = await calculateAmount(amountExpression, parsedTaxRate);
      const normalizedCategory = normalizeCategory(category);

      const payload: ManualEncryptedPayload = {
        source: "manual",
        version: 1,
        date,
        tx_type: txType,
        merchant,
        amount_expression: amountExpression.trim(),
        amount: calculation.amount,
        tax_rate: calculation.tax_rate,
        tax_amount: calculation.tax_amount,
        category: normalizedCategory,
        memo,
        payment_method: paymentMethod,
        line_items: [
          {
            name: merchant || paymentMethodLabel(paymentMethod) || "手入力",
            amount: calculation.amount,
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
      setMessage(
        `手入力取引を暗号化保存しました（${yen(calculation.amount)}・税額${yen(calculation.tax_amount)}）`,
      );
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  function startEdit(row: DecryptedRow) {
    if (!row.payload || !row.normalized) {
      setMessage("復号できない行は編集できません");
      return;
    }

    const fallbackTaxRate = defaultTaxRate(
      row.normalized.tx_type,
      row.normalized.category,
    );

    setEditing({
      id: row.id,
      payload: row.payload,
      date: row.normalized.date,
      tx_type: row.normalized.tx_type,
      merchant: row.normalized.merchant,
      category: normalizeCategory(row.normalized.category),
      amount_expression:
        row.normalized.amount_expression ?? String(row.normalized.amount),
      tax_rate: String(row.normalized.tax_rate ?? fallbackTaxRate),
      memo: row.normalized.memo,
      payment_method: row.normalized.payment_method || "cash",
      line_items:
        row.normalized.line_items.length > 0
          ? row.normalized.line_items.map((item) => ({
              ...item,
              category: normalizeCategory(item.category),
            }))
          : [defaultLineItem(row.normalized.category)],
    });
  }

  function changeEditingTxType(nextType: TxType) {
    if (!editing) return;
    const nextCategory = categoryOptions(nextType)[0] ?? "未分類";
    setEditing({
      ...editing,
      tx_type: nextType,
      category: nextCategory,
      tax_rate: String(defaultTaxRate(nextType, nextCategory)),
    });
  }

  function changeEditingCategory(nextCategory: string) {
    if (!editing) return;
    setEditing({
      ...editing,
      category: nextCategory,
      tax_rate: String(defaultTaxRate(editing.tx_type, nextCategory)),
    });
  }

  async function handleUpdate() {
    if (!editing) return;

    setMessage("");
    setSaving(true);

    try {
      const parsedTaxRate = parseTaxRate(editing.tax_rate);
      const calculation = await calculateAmount(
        editing.amount_expression,
        parsedTaxRate,
      );
      const updatedPayload = buildPayloadFromEdit(editing, calculation);
      const encryptedRecord = await encryptJson(requireKey(), updatedPayload);

      await updateEncryptedTx(editing.id, JSON.stringify(encryptedRecord), 1);

      setEditing(null);
      await loadRows();
      setMessage(
        `更新しました（${yen(calculation.amount)}・税額${yen(calculation.tax_amount)}）`,
      );
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  async function handleDelete(id: number) {
    if (!window.confirm("この取引を削除しますか？")) return;

    setMessage("");
    setSaving(true);
    try {
      await deleteEncryptedTx(id);
      await loadRows();
      setMessage("削除しました");
    } catch (e) {
      setMessage(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  useEffect(() => {
    void loadRows().catch((e) => {
      setMessage(e instanceof Error ? e.message : String(e));
    });
  }, [refreshKey]);

  return (
    <section style={{ border: "1px solid #ddd", padding: 16, marginTop: 16 }}>
      <h2>取引一覧</h2>
      <DataIntegrityCheck />
      <p className="hint">
        encrypted_transactions を取得し、ブラウザ側で復号して表示・編集します。
        金額計算時にバックエンドへ送るのは値段式と税率だけです。
      </p>

      <div style={{ display: "grid", gap: 8, maxWidth: 520 }}>
        <h3>レシートなし手入力</h3>

        <label>
          日付
          <input
            type="date"
            value={date}
            onChange={(e) => setDate(e.target.value)}
          />
        </label>

        <label>
          種別
          <select
            value={txType}
            onChange={(e) => changeTxType(e.target.value as TxType)}
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
          カテゴリ
          <select value={category} onChange={(e) => changeCategory(e.target.value)}>
            {categoryOptionsWithCurrent(txType, category).map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>

        <label>
          値段（税込・四則演算と括弧が使用可能）
          <input
            value={amountExpression}
            placeholder="例: (1200 + 300) / 2"
            inputMode="decimal"
            onChange={(e) => setAmountExpression(e.target.value)}
          />
        </label>

        <label>
          税率（%）
          <input
            type="number"
            min="0"
            max="100"
            step="1"
            value={taxRate}
            onChange={(e) => setTaxRate(e.target.value)}
          />
        </label>

        <label>
          メモ
          <input value={memo} onChange={(e) => setMemo(e.target.value)} />
        </label>

        <button onClick={() => void handleCreateManual()} disabled={saving}>
          {saving ? "処理中..." : "手入力を暗号化保存"}
        </button>

        <button onClick={() => void loadRows()} disabled={saving}>
          再読み込み
        </button>
      </div>

      {message && <p>{message}</p>}

      {editing && (
        <div style={{ border: "1px solid #aaa", padding: 12, marginTop: 16 }}>
          <h3>編集</h3>

          <div style={{ display: "grid", gap: 8, maxWidth: 620 }}>
            <label>
              日付
              <input
                type="date"
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
                  changeEditingTxType(e.target.value as TxType)
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
              カテゴリ
              <select
                value={editing.category}
                onChange={(e) => changeEditingCategory(e.target.value)}
              >
                {categoryOptionsWithCurrent(
                  editing.tx_type,
                  editing.category,
                ).map((option) => (
                  <option key={option} value={option}>
                    {option}
                  </option>
                ))}
              </select>
            </label>

            <label>
              値段（税込・四則演算と括弧が使用可能）
              <input
                value={editing.amount_expression}
                inputMode="decimal"
                onChange={(e) =>
                  setEditing({
                    ...editing,
                    amount_expression: e.target.value,
                  })
                }
              />
            </label>

            <label>
              税率（%）
              <input
                type="number"
                min="0"
                max="100"
                step="1"
                value={editing.tax_rate}
                onChange={(e) =>
                  setEditing({ ...editing, tax_rate: e.target.value })
                }
              />
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
                <select
                  value={normalizeCategory(item.category)}
                  onChange={(e) => {
                    const next = [...editing.line_items];
                    next[index] = { ...item, category: e.target.value };
                    setEditing({ ...editing, line_items: next });
                  }}
                >
                  {categoryOptionsWithCurrent(
                    editing.tx_type,
                    item.category,
                  ).map((option) => (
                    <option key={option} value={option}>
                      {option}
                    </option>
                  ))}
                </select>
                <input
                  type="number"
                  min="0"
                  step="1"
                  value={item.amount}
                  placeholder="値段"
                  onChange={(e) => {
                    const next = [...editing.line_items];
                    next[index] = {
                      ...item,
                      amount: Number(e.target.value) || 0,
                    };
                    setEditing({ ...editing, line_items: next });
                  }}
                />
                <button
                  onClick={() => {
                    const next = editing.line_items.filter(
                      (_lineItem, itemIndex) => itemIndex !== index,
                    );
                    setEditing({
                      ...editing,
                      line_items:
                        next.length > 0
                          ? next
                          : [defaultLineItem(editing.category)],
                    });
                  }}
                  disabled={saving}
                >
                  削除
                </button>
              </div>
            ))}

            <div style={{ display: "flex", gap: 8 }}>
              <button onClick={() => void handleUpdate()} disabled={saving}>
                {saving ? "処理中..." : "更新"}
              </button>
              <button onClick={() => setEditing(null)} disabled={saving}>
                キャンセル
              </button>
            </div>
          </div>
        </div>
      )}

      <div style={{ marginTop: 16, overflowX: "auto" }}>
        <h3>保存済み取引</h3>

        {sortedRows.length === 0 ? (
          <p>取引はまだありません。</p>
        ) : (
          <table>
            <thead>
              <tr>
                <th>日付</th>
                <th>種別</th>
                <th>種類</th>
                <th>店舗・相手先</th>
                <th>カテゴリ</th>
                <th>値段</th>
                <th>税率</th>
                <th>税額</th>
                <th>メモ</th>
                <th>操作</th>
              </tr>
            </thead>
            <tbody>
              {sortedRows.map((row) => {
                if (!row.normalized) {
                  return (
                    <tr key={row.id}>
                      <td colSpan={10} className="err">
                        ID {row.id}: 復号失敗 {row.error || "不明なエラー"}
                      </td>
                    </tr>
                  );
                }

                return (
                  <tr key={row.id}>
                    <td>{row.normalized.date}</td>
                    <td>
                      {row.normalized.tx_type === "income" ? "収入" : "支出"}
                    </td>
                    <td>{paymentMethodLabel(row.normalized.payment_method)}</td>
                    <td>{row.normalized.merchant}</td>
                    <td>{row.normalized.category}</td>
                    <td title={row.normalized.amount_expression || undefined}>
                      {yen(row.normalized.amount)}
                    </td>
                    <td>{taxRateLabel(row.normalized.tax_rate)}</td>
                    <td>{yen(row.normalized.tax_amount)}</td>
                    <td>{row.normalized.memo}</td>
                    <td>
                      <button onClick={() => startEdit(row)} disabled={saving}>
                        編集
                      </button>
                      <button
                        onClick={() => void handleDelete(row.id)}
                        disabled={saving}
                      >
                        削除
                      </button>
                    </td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        )}
      </div>
    </section>
  );
}
