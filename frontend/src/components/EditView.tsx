import { useEffect, useState } from "react";
import {
  updateTransaction, createOverride, listCategories,
  getTransaction, createItem, updateItem, deleteItem,
} from "../api";
import type { Transaction, TransactionItem, CategoryMaster } from "../types";
import { CATEGORIES, DEFAULT_TAX_RATE } from "../types";

interface Props {
  tx: Transaction;
  onClose: () => void;
  onSaved: () => void;
}

export function EditView({ tx, onClose, onSaved }: Props) {
  const [merchantNormalized, setMerchantNormalized] = useState(tx.merchant_normalized);
  const [category, setCategory] = useState<string>(tx.screening_category || "");
  const [amount, setAmount] = useState(String(tx.amount));
  const [purchasedAt, setPurchasedAt] = useState(tx.purchased_at);
  const [memo, setMemo] = useState(tx.memo || "");
  const [txType, setTxType] = useState<string>(tx.tx_type || "expense");
  const [needsReview, setNeedsReview] = useState(tx.needs_review);
  const [registerOverride, setRegisterOverride] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [catMaster, setCatMaster] = useState<CategoryMaster[]>([]);
  const [items, setItems] = useState<TransactionItem[]>([]);
  const [itemsBusy, setItemsBusy] = useState(false);

  useEffect(() => {
    listCategories().then(setCatMaster).catch(() => {});
    // 明細を取得
    getTransaction(tx.id).then((full) => {
      setItems(full.items || []);
    }).catch(() => {});
  }, [tx.id]);

  const taxRateFor = (cat: string | null): number => {
    if (!cat) return 10;
    const found = catMaster.find((c) => c.name === cat);
    if (found) return found.tax_rate;
    return DEFAULT_TAX_RATE[cat as keyof typeof DEFAULT_TAX_RATE] ?? 10;
  };

  const taxRate = taxRateFor(category);
  const amountNum = parseInt(amount, 10) || 0;
  const headerTaxAmt = amountNum > 0 && taxRate > 0
    ? Math.round((amountNum * taxRate) / (100 + taxRate)) : 0;
  const headerExTax = amountNum - headerTaxAmt;

  const itemsTotal = items.reduce((s, it) => s + it.amount, 0);
  const itemsTaxTotal = items.reduce((s, it) => s + it.tax_amount, 0);
  const hasItems = items.length > 0;
  const totalMatch = !hasItems || amountNum === itemsTotal;

  async function handleAddItem() {
    setItemsBusy(true);
    try {
      const created = await createItem(tx.id, {
        name: "新しい明細", amount: 0, category: null,
        sort_order: items.length,
      });
      setItems([...items, created]);
      // ヘッダ再取得
      const fresh = await getTransaction(tx.id);
      setAmount(String(fresh.amount));
      setCategory(fresh.screening_category || "");
    } catch (e) { setError(String(e)); }
    finally { setItemsBusy(false); }
  }

  async function handleItemChange(
    itemId: number, patch: Partial<TransactionItem>
  ) {
    setItemsBusy(true);
    try {
      await updateItem(tx.id, itemId, patch);
      const fresh = await getTransaction(tx.id);
      setItems(fresh.items || []);
      setAmount(String(fresh.amount));
      setCategory(fresh.screening_category || "");
    } catch (e) { setError(String(e)); }
    finally { setItemsBusy(false); }
  }

  async function handleItemDelete(itemId: number) {
    setItemsBusy(true);
    try {
      await deleteItem(tx.id, itemId);
      const fresh = await getTransaction(tx.id);
      setItems(fresh.items || []);
      setAmount(String(fresh.amount));
      setCategory(fresh.screening_category || "");
    } catch (e) { setError(String(e)); }
    finally { setItemsBusy(false); }
  }

  async function handleSave() {
    setBusy(true); setError(null);
    try {
      await updateTransaction(tx.id, {
        merchant_normalized: merchantNormalized,
        // 明細がある場合はサーバ側で再計算されるので送信不要だが、明示で送る
        screening_category: hasItems ? undefined : (category || null),
        amount: hasItems ? undefined : amountNum,
        purchased_at: purchasedAt,
        memo: memo || null,
        needs_review: needsReview,
        status: "user_confirmed",
        tx_type: txType,
      });
      if (registerOverride && category && merchantNormalized) {
        await createOverride(merchantNormalized, category);
      }
      onSaved();
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()}>
        <h3>取引編集 (ID: {tx.id})</h3>
        <div className="form-grid">
          <label>種別</label>
          <select value={txType} onChange={(e) => setTxType(e.target.value)}>
            <option value="expense">支出</option>
            <option value="income">収入</option>
          </select>
          <label>日付</label>
          <input type="date" value={purchasedAt}
                 onChange={(e) => setPurchasedAt(e.target.value)} />
          <label>店舗(正規化)</label>
          <input type="text" value={merchantNormalized}
                 onChange={(e) => setMerchantNormalized(e.target.value)} />
          <label>主カテゴリ</label>
          <div className="tax-info">
            {hasItems
              ? `${category || "(未分類)"} ※明細から自動`
              : (
                <select value={category} onChange={(e) => setCategory(e.target.value)}>
                  <option value="">(未分類)</option>
                  {CATEGORIES.map((c) => (<option key={c} value={c}>{c}</option>))}
                </select>
              )}
          </div>
          <label>合計金額(税込)</label>
          <div className="tax-info">
            {hasItems
              ? `${amountNum.toLocaleString()}円 ※明細から自動`
              : (
                <input type="number" value={amount}
                       onChange={(e) => setAmount(e.target.value)} />
              )}
          </div>
          <label>税抜換算 (主)</label>
          <div className="tax-info">
            {amountNum > 0
              ? `${headerExTax.toLocaleString()}円 (税額 ${headerTaxAmt.toLocaleString()}円, ${taxRate}%)`
              : "-"}
          </div>
          <label>メモ</label>
          <input type="text" value={memo}
                 onChange={(e) => setMemo(e.target.value)} />
          <label>要確認</label>
          <input type="checkbox" checked={needsReview}
                 onChange={(e) => setNeedsReview(e.target.checked)} />
          <label>この店舗→カテゴリを記憶</label>
          <input type="checkbox" checked={registerOverride}
                 onChange={(e) => setRegisterOverride(e.target.checked)}
                 disabled={!category || !merchantNormalized || hasItems} />
        </div>

        {/* 明細セクション */}
        <div className="items-section">
          <h4>明細 ({items.length}件)</h4>
          {!hasItems && (
            <p className="hint">
              明細を追加するとカテゴリごとの分類ができます。
              明細を追加した瞬間、ヘッダの金額・カテゴリは明細から自動算出されます。
            </p>
          )}
          {items.length > 0 && (
            <table className="items-table">
              <thead>
                <tr>
                  <th>品目</th>
                  <th style={{ width: 90 }}>金額(税込)</th>
                  <th style={{ width: 110 }}>カテゴリ</th>
                  <th style={{ width: 60 }}>税率</th>
                  <th style={{ width: 70 }}>税額</th>
                  <th></th>
                </tr>
              </thead>
              <tbody>
                {items.map((it) => (
                  <tr key={it.id}>
                    <td>
                      <input
                        type="text" value={it.name}
                        onChange={(e) => setItems(items.map(
                          (x) => x.id === it.id ? { ...x, name: e.target.value } : x
                        ))}
                        onBlur={(e) => handleItemChange(it.id, { name: e.target.value })}
                      />
                    </td>
                    <td>
                      <input
                        type="number" value={it.amount}
                        onChange={(e) => setItems(items.map(
                          (x) => x.id === it.id
                            ? { ...x, amount: parseInt(e.target.value, 10) || 0 }
                            : x
                        ))}
                        onBlur={(e) =>
                          handleItemChange(it.id, { amount: parseInt(e.target.value, 10) || 0 })
                        }
                      />
                    </td>
                    <td>
                      <select
                        value={it.category || ""}
                        onChange={(e) =>
                          handleItemChange(it.id, { category: e.target.value || null })
                        }
                      >
                        <option value="">未分類</option>
                        {CATEGORIES.map((c) => (
                          <option key={c} value={c}>{c}</option>
                        ))}
                      </select>
                    </td>
                    <td>{taxRateFor(it.category)}%</td>
                    <td style={{ textAlign: "right" }}>{it.tax_amount}</td>
                    <td>
                      <button className="danger" onClick={() => handleItemDelete(it.id)}>
                        削除
                      </button>
                    </td>
                  </tr>
                ))}
              </tbody>
              <tfoot>
                <tr>
                  <td>合計</td>
                  <td style={{ textAlign: "right" }}><b>{itemsTotal.toLocaleString()}</b></td>
                  <td colSpan={2}></td>
                  <td style={{ textAlign: "right" }}>{itemsTaxTotal.toLocaleString()}</td>
                  <td></td>
                </tr>
              </tfoot>
            </table>
          )}
          <button onClick={handleAddItem} disabled={itemsBusy}>+ 明細を追加</button>
          {!totalMatch && (
            <p className="err">
              ⚠ ヘッダ合計({amountNum.toLocaleString()}円)と明細合計({itemsTotal.toLocaleString()}円)が一致しません
            </p>
          )}
        </div>

        {tx.ocr_raw_text && (
          <details>
            <summary>OCR raw text (参考)</summary>
            <pre>{tx.ocr_raw_text}</pre>
          </details>
        )}
        {error && <p className="err">{error}</p>}
        <div className="actions">
          <button onClick={handleSave} disabled={busy}>保存(確認済にする)</button>
          <button onClick={onClose}>キャンセル</button>
        </div>
      </div>
    </div>
  );
}
