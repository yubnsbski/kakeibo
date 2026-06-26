import { useEffect, useMemo, useState } from "react";
import {
  calculateAmount,
  type AmountCalculationResponse,
  type AmountMode,
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
  assertLineItemTotal,
  buildManualLineItems,
  type LineItemDraft,
} from "../lineItems";
import {
  normalizeEncryptedPayload,
  type EncryptedLineItem,
  type EncryptedTxPayload,
  type ManualEncryptedPayload,
  type ManualNoReceiptKind,
  type NormalizedEncryptedTx,
  type TxType,
} from "../txPayload";
import { AmountCalculator } from "./AmountCalculator";
import { DataIntegrityCheck } from "./DataIntegrityCheck";
import {
  DraftLineItemsEditor,
  StoredLineItemsEditor,
} from "./LineItemsEditor";

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
  amount_mode: AmountMode;
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

function amountModeLabel(mode: AmountMode): string {
  return mode === "tax_excluded" ? "税抜入力" : "税込入力";
}

function parseTaxRate(value: string): number {
  const parsed = Number(value);
  if (!Number.isInteger(parsed) || parsed < 0 || parsed > 100) {
    throw new Error("税率は0〜100の整数で入力してください");
  }
  return parsed;
}

async function calculateExpression(
  expression: string,
  taxRateValue: string,
  amountMode: AmountMode,
): Promise<AmountCalculationResponse> {
  if (!expression.trim()) {
    throw new Error("値段式を入力してください");
  }
  return calculateAmount(expression, parseTaxRate(taxRateValue), amountMode);
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
  const items = edit.line_items.map((item, index) => {
    const amount = Number(item.amount);
    if (!Number.isFinite(amount) || !Number.isInteger(amount)) {
      throw new Error(`明細${index + 1}の金額は整数で入力してください`);
    }

    return {
      ...item,
      name: item.name.trim() || edit.merchant.trim() || `明細${index + 1}`,
      amount,
      category: normalizeCategory(item.category || category),
    };
  });

  if (edit.payload.source === "manual") {
    if (items.length === 1) {
      items[0] = { ...items[0], amount: calculation.amount };
    }
    assertLineItemTotal(items, calculation.amount);
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
        amount_expression: edit.amount_expression.trim(),
        amount_mode: calculation.amount_mode,
        amount: calculation.amount,
        net_amount: calculation.net_amount,
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
    amount_mode: calculation.amount_mode,
    amount: calculation.amount,
    net_amount: calculation.net_amount,
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

export function TaxAwareEncryptedTxView({
  refreshKey = 0,
}: EncryptedTxViewProps) {
  const [date, setDate] = useState(todayLocalIsoDate());
  const [txType, setTxType] = useState<TxType>("expense");
  const [merchant, setMerchant] = useState("");
  const [category, setCategory] = useState("未分類");
  const [amountExpression, setAmountExpression] = useState("1000");
  const [amountMode, setAmountMode] = useState<AmountMode>("tax_included");
  const [taxRate, setTaxRate] = useState(
    String(defaultTaxRate("expense", "未分類")),
  );
  const [memo, setMemo] = useState("");
  const [paymentMethod, setPaymentMethod] =
    useState<ManualNoReceiptKind>("cash");
  const [manualLineItems, setManualLineItems] = useState<LineItemDraft[]>([]);
  const [manualCalculation, setManualCalculation] =
    useState<AmountCalculationResponse | null>(null);

  const [rows, setRows] = useState<DecryptedRow[]>([]);
  const [editing, setEditing] = useState<EditingState | null>(null);
  const [editingCalculation, setEditingCalculation] =
    useState<AmountCalculationResponse | null>(null);
  const [message, setMessage] = useState("");
  const [saving, setSaving] = useState(false);

  const sortedRows = useMemo(() => {
    return [...rows].sort((left, right) => {
      const leftDate = left.normalized?.date ?? "";
      const rightDate = right.normalized?.date ?? "";
      return rightDate.localeCompare(leftDate);
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
        } catch (error) {
          return {
            id: row.id,
            raw: row,
            error: error instanceof Error ? error.message : String(error),
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
    setManualLineItems((items) =>
      items.map((item) => ({ ...item, category: nextCategory })),
    );
  }

  function changeCategory(nextCategory: string) {
    setCategory(nextCategory);
    setTaxRate(String(defaultTaxRate(txType, nextCategory)));
  }

  async function handleCreateManual() {
    setMessage("");
    setSaving(true);

    try {
      const calculation = await calculateExpression(
        amountExpression,
        taxRate,
        amountMode,
      );
      const normalizedCategory = normalizeCategory(category);
      const lineItems = buildManualLineItems(manualLineItems, {
        totalAmount: calculation.amount,
        fallbackName: merchant || paymentMethodLabel(paymentMethod) || "手入力",
        fallbackCategory: normalizedCategory,
        memo,
      });

      const payload: ManualEncryptedPayload = {
        source: "manual",
        version: 1,
        date,
        tx_type: txType,
        merchant,
        amount_expression: amountExpression.trim(),
        amount_mode: calculation.amount_mode,
        amount: calculation.amount,
        net_amount: calculation.net_amount,
        tax_rate: calculation.tax_rate,
        tax_amount: calculation.tax_amount,
        category: normalizedCategory,
        memo,
        payment_method: paymentMethod,
        line_items: lineItems,
      };

      const encryptedRecord = await encryptJson(requireKey(), payload);
      await createEncryptedTx(JSON.stringify(encryptedRecord), 1);

      setMerchant("");
      setMemo("");
      setManualLineItems([]);
      await loadRows();
      setMessage(
        `保存しました（税込${yen(calculation.amount)}・` +
          `税抜${yen(calculation.net_amount)}・税${yen(calculation.tax_amount)}）`,
      );
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
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

    setEditingCalculation(null);
    setEditing({
      id: row.id,
      payload: row.payload,
      date: row.normalized.date,
      tx_type: row.normalized.tx_type,
      merchant: row.normalized.merchant,
      category: normalizeCategory(row.normalized.category),
      amount_expression:
        row.normalized.amount_expression ?? String(row.normalized.amount),
      amount_mode: row.normalized.amount_mode,
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

  function cancelEdit() {
    setEditing(null);
    setEditingCalculation(null);
  }

  function changeEditingTxType(nextType: TxType) {
    if (!editing || editing.payload.source === "receipt_ocr") return;
    const nextCategory = categoryOptions(nextType)[0] ?? "未分類";
    setEditing({
      ...editing,
      tx_type: nextType,
      category: nextCategory,
      tax_rate: String(defaultTaxRate(nextType, nextCategory)),
      line_items: editing.line_items.map((item) => ({
        ...item,
        category: nextCategory,
      })),
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
      const calculation = await calculateExpression(
        editing.amount_expression,
        editing.tax_rate,
        editing.amount_mode,
      );
      const updatedPayload = buildPayloadFromEdit(editing, calculation);
      const encryptedRecord = await encryptJson(requireKey(), updatedPayload);

      await updateEncryptedTx(editing.id, JSON.stringify(encryptedRecord), 1);

      setEditing(null);
      setEditingCalculation(null);
      await loadRows();
      setMessage(
        `更新しました（税込${yen(calculation.amount)}・` +
          `税抜${yen(calculation.net_amount)}・税${yen(calculation.tax_amount)}）`,
      );
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
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
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setSaving(false);
    }
  }

  useEffect(() => {
    void loadRows().catch((error) => {
      setMessage(error instanceof Error ? error.message : String(error));
    });
  }, [refreshKey]);

  return (
    <section style={{ border: "1px solid #ddd", padding: 16, marginTop: 16 }}>
      <h2>取引一覧</h2>
      <DataIntegrityCheck />
      <p className="hint">
        取引はブラウザ側で復号します。金額計算時にバックエンドへ送るのは
        値段式・税率・税込／税抜の入力方式だけです。
      </p>

      <div style={{ display: "grid", gap: 10, maxWidth: 780 }}>
        <h3>レシートなし手入力</h3>

        <label>
          日付
          <input
            type="date"
            value={date}
            onChange={(event) => setDate(event.target.value)}
          />
        </label>

        <label>
          種別
          <select
            value={txType}
            onChange={(event) => changeTxType(event.target.value as TxType)}
          >
            <option value="expense">支出</option>
            <option value="income">収入</option>
          </select>
        </label>

        <label>
          種類
          <select
            value={paymentMethod}
            onChange={(event) =>
              setPaymentMethod(event.target.value as ManualNoReceiptKind)
            }
          >
            <option value="cash">現金</option>
            <option value="other">その他</option>
          </select>
        </label>

        <label>
          店舗・相手先
          <input
            value={merchant}
            onChange={(event) => setMerchant(event.target.value)}
          />
        </label>

        <label>
          カテゴリ
          <select
            value={category}
            onChange={(event) => changeCategory(event.target.value)}
          >
            {categoryOptionsWithCurrent(txType, category).map((option) => (
              <option key={option} value={option}>
                {option}
              </option>
            ))}
          </select>
        </label>

        <AmountCalculator
          id="manual-amount-expression"
          expression={amountExpression}
          taxRate={taxRate}
          amountMode={amountMode}
          disabled={saving}
          onExpressionChange={setAmountExpression}
          onTaxRateChange={setTaxRate}
          onAmountModeChange={setAmountMode}
          onResultChange={setManualCalculation}
        />

        <DraftLineItemsEditor
          items={manualLineItems}
          txType={txType}
          defaultCategory={category}
          expectedAmount={manualCalculation?.amount}
          disabled={saving}
          onChange={setManualLineItems}
        />

        <label>
          メモ
          <input value={memo} onChange={(event) => setMemo(event.target.value)} />
        </label>

        <button
          onClick={() => void handleCreateManual()}
          disabled={saving || manualCalculation === null}
        >
          {saving
            ? "処理中..."
            : manualCalculation
              ? `税込${manualCalculation.amount.toLocaleString()}円を暗号化保存`
              : "計算結果を確認してください"}
        </button>

        <button
          onClick={() =>
            void loadRows().catch((error) =>
              setMessage(error instanceof Error ? error.message : String(error)),
            )
          }
          disabled={saving}
        >
          再読み込み
        </button>
      </div>

      {message && <p>{message}</p>}

      {editing && (
        <div style={{ border: "1px solid #aaa", padding: 12, marginTop: 16 }}>
          <h3>編集</h3>

          <div style={{ display: "grid", gap: 10, maxWidth: 780 }}>
            <label>
              日付
              <input
                type="date"
                value={editing.date}
                onChange={(event) =>
                  setEditing({ ...editing, date: event.target.value })
                }
              />
            </label>

            <label>
              種別
              <select
                value={editing.tx_type}
                disabled={editing.payload.source === "receipt_ocr"}
                onChange={(event) =>
                  changeEditingTxType(event.target.value as TxType)
                }
              >
                <option value="expense">支出</option>
                <option value="income">収入</option>
              </select>
              {editing.payload.source === "receipt_ocr" && (
                <span className="hint">OCR取引は支出として固定されます。</span>
              )}
            </label>

            {editing.payload.source === "manual" && (
              <label>
                種類
                <select
                  value={editing.payment_method}
                  onChange={(event) =>
                    setEditing({
                      ...editing,
                      payment_method: event.target.value as ManualNoReceiptKind,
                    })
                  }
                >
                  <option value="cash">現金</option>
                  <option value="other">その他</option>
                </select>
              </label>
            )}

            <label>
              店舗・相手先
              <input
                value={editing.merchant}
                onChange={(event) =>
                  setEditing({ ...editing, merchant: event.target.value })
                }
              />
            </label>

            <label>
              カテゴリ
              <select
                value={editing.category}
                onChange={(event) => changeEditingCategory(event.target.value)}
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

            <AmountCalculator
              id={`editing-amount-expression-${editing.id}`}
              expression={editing.amount_expression}
              taxRate={editing.tax_rate}
              amountMode={editing.amount_mode}
              disabled={saving}
              onExpressionChange={(nextExpression) =>
                setEditing({
                  ...editing,
                  amount_expression: nextExpression,
                })
              }
              onTaxRateChange={(nextTaxRate) =>
                setEditing({ ...editing, tax_rate: nextTaxRate })
              }
              onAmountModeChange={(nextMode) =>
                setEditing({ ...editing, amount_mode: nextMode })
              }
              onResultChange={setEditingCalculation}
            />

            <StoredLineItemsEditor
              items={editing.line_items}
              txType={editing.tx_type}
              defaultCategory={editing.category}
              expectedAmount={editingCalculation?.amount}
              disabled={saving}
              onChange={(lineItems) =>
                setEditing({ ...editing, line_items: lineItems })
              }
            />

            <label>
              メモ
              <input
                value={editing.memo}
                onChange={(event) =>
                  setEditing({ ...editing, memo: event.target.value })
                }
              />
            </label>

            <div style={{ display: "flex", gap: 8 }}>
              <button
                onClick={() => void handleUpdate()}
                disabled={saving || editingCalculation === null}
              >
                {saving
                  ? "処理中..."
                  : editingCalculation
                    ? `税込${editingCalculation.amount.toLocaleString()}円で更新`
                    : "計算結果を確認してください"}
              </button>
              <button onClick={cancelEdit} disabled={saving}>
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
                <th>明細</th>
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
                      <td colSpan={11} className="err">
                        ID {row.id}: 復号失敗 {row.error || "不明なエラー"}
                      </td>
                    </tr>
                  );
                }

                const expression = row.normalized.amount_expression?.trim();
                const showExpression =
                  expression && expression !== String(row.normalized.amount);

                return (
                  <tr key={row.id}>
                    <td>{row.normalized.date}</td>
                    <td>
                      {row.normalized.tx_type === "income" ? "収入" : "支出"}
                    </td>
                    <td>{paymentMethodLabel(row.normalized.payment_method)}</td>
                    <td>{row.normalized.merchant}</td>
                    <td>{row.normalized.category}</td>
                    <td>
                      <div style={{ fontWeight: 700 }}>
                        税込 {yen(row.normalized.amount)}
                      </div>
                      <div className="hint">
                        税抜 {yen(row.normalized.net_amount)}・
                        {amountModeLabel(row.normalized.amount_mode)}
                      </div>
                      {showExpression && (
                        <div className="hint" style={{ whiteSpace: "nowrap" }}>
                          式: {expression}
                        </div>
                      )}
                    </td>
                    <td>{row.normalized.line_items.length}件</td>
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
