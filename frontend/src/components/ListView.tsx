import { useEffect, useState, useCallback } from "react";
import { listTransactions, deleteTransaction } from "../api";
import type { Transaction } from "../types";
import { EditView } from "./EditView";

interface Props { refreshKey: number; }
type FilterMode = "unconfirmed" | "all";

export function ListView({ refreshKey }: Props) {
  const [items, setItems] = useState<Transaction[]>([]);
  const [mode, setMode] = useState<FilterMode>("unconfirmed");
  const [merchantQ, setMerchantQ] = useState("");
  const [editing, setEditing] = useState<Transaction | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const load = useCallback(async () => {
    setLoading(true); setError(null);
    try {
      const data = await listTransactions({
        status: mode === "unconfirmed" ? "auto_saved" : undefined,
        merchant: merchantQ || undefined,
        limit: 200,
      });
      setItems(data);
    } catch (e) { setError(String(e)); }
    finally { setLoading(false); }
  }, [mode, merchantQ]);

  useEffect(() => { load(); }, [load, refreshKey]);

  async function handleDelete(id: number) {
    if (!confirm(`取引ID ${id} を削除しますか?`)) return;
    try { await deleteTransaction(id); await load(); }
    catch (e) { setError(String(e)); }
  }

  return (
    <div className="card">
      <h2>取引一覧</h2>
      <div className="filters">
        <label><input type="radio" checked={mode === "unconfirmed"}
                       onChange={() => setMode("unconfirmed")} />未確認のみ</label>
        <label><input type="radio" checked={mode === "all"}
                       onChange={() => setMode("all")} />すべて</label>
        <input type="text" placeholder="店舗名で検索" value={merchantQ}
               onChange={(e) => setMerchantQ(e.target.value)} />
        <button onClick={load}>再読込</button>
      </div>
      {error && <p className="err">{error}</p>}
      {loading && <p>読込中...</p>}
      {!loading && items.length === 0 && <p>該当する取引なし</p>}
      {items.length > 0 && (
        <table className="tx-table">
          <thead>
            <tr>
              <th>日付</th><th>店舗</th><th>カテゴリ</th>
              <th style={{ textAlign: "right" }}>金額(税込)</th>
              <th style={{ textAlign: "right" }}>税額</th>
              <th>状態</th><th></th>
            </tr>
          </thead>
          <tbody>
            {items.map((t) => (
              <tr key={t.id} className={t.needs_review ? "needs-review" : ""}>
                <td>{t.purchased_at}</td>
                <td>{t.merchant_normalized || t.merchant_raw}</td>
                <td>{t.screening_category || "(未分類)"}</td>
                <td style={{ textAlign: "right" }}>{t.amount.toLocaleString()}</td>
                <td style={{ textAlign: "right" }}>{t.tax_amount.toLocaleString()}</td>
                <td>
                  {t.status === "auto_saved" && <span className="badge auto">未確認</span>}
                  {t.status === "user_confirmed" && <span className="badge ok">確認済</span>}
                  {t.status === "manually_added" && <span className="badge ok">手動</span>}
                  {t.needs_review && <span className="badge review">要確認</span>}
                </td>
                <td>
                  <button onClick={() => setEditing(t)}>編集</button>
                  <button onClick={() => handleDelete(t.id)} className="danger">削除</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
      {editing && (
        <EditView tx={editing} onClose={() => setEditing(null)}
                  onSaved={() => { setEditing(null); load(); }} />
      )}
    </div>
  );
}
