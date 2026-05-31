import { useState } from "react";
import { previewCsv } from "../api";
import type { CsvPreviewResponse } from "../api";
import { createEncryptedTx } from "../crypto/encryptedTxApi";
import { encryptJson } from "../crypto/cipher";
import { requireKey } from "../crypto/keyStore";
import type { ManualEncryptedPayload } from "../crypto/txPayload";

interface Props {
  onImported: () => void;
}

export function CsvImportCard({ onImported }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<CsvPreviewResponse | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [importResult, setImportResult] = useState<string | null>(null);

  async function handlePreview() {
    if (!file) { setError("CSV未選択"); return; }
    setError(null); setImportResult(null); setBusy(true);
    try {
      setPreview(await previewCsv(file));
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  async function handleCommit() {

    if (!preview) {
      return;
    }

    const validRows = preview.rows.filter((row) => !row.validation_error);

    if (validRows.length === 0) {
      setError("取り込める行がありません");
      return;
    }

    if (!confirm(`${validRows.length}件を暗号化して取り込みますか?`)) {
      return;
    }

    setBusy(true);
    setError(null);

    try {
      const key = requireKey();

      let savedCount = 0;

      for (const row of validRows) {
        const amount = Math.abs(row.amount ?? 0);
        const category = row.category || "未分類";
        const memo = row.memo || "";

        const payload: ManualEncryptedPayload = {
          source: "manual",
          version: 1,
          date: row.date,
          tx_type: row.tx_type === "income" ? "income" : "expense",
          merchant: memo || "CSV取込",
          amount,
          category,
          memo,
          payment_method: "other",
          line_items: [
            {
              name: memo || "CSV取込",
              amount,
              category,
              memo,
            },
          ],
        };

        const encryptedRecord = await encryptJson(key, payload);

        await createEncryptedTx(JSON.stringify(encryptedRecord), 1);

        savedCount += 1;
      }

      setImportResult(`暗号化取込完了: ${savedCount}件`);
      setPreview(null);
      setFile(null);
      onImported();
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      setError(message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="card">
      <h2>CSV 一括取込</h2>
      <p className="hint">
        ヘッダ: <code>date,amount,category,memo</code><br />
        金額: 負数=支出 / 正数=収入<br />
        例: <code>2026-05-15,-620,食費,セブン</code> / <code>2026-05-25,250000,給与,会社</code>
      </p>
      <input type="file" accept=".csv,text/csv" onChange={(e) => {
        setFile(e.target.files?.[0] || null);
        setPreview(null);
        setImportResult(null);
      }} />
      <button onClick={handlePreview} disabled={busy || !file}>プレビュー</button>
      {error && <p className="err">{error}</p>}
      {importResult && <p style={{ color: "#1a7f37" }}>{importResult}</p>}

      {preview?.header_error && (
        <p className="err">ヘッダエラー: {preview.header_error}</p>
      )}

      {preview && !preview.header_error && (
        <div className="csv-preview">
          <p>
            総件数: <b>{preview.total}</b> /
            エラー件数: <b className={preview.error_count > 0 ? "err" : ""}>{preview.error_count}</b>
          </p>
          <div style={{ maxHeight: 320, overflowY: "auto" }}>
            <table className="tx-table" style={{ fontSize: "0.82em" }}>
              <thead>
                <tr>
                  <th>日付</th>
                  <th>種別</th>
                  <th style={{ textAlign: "right" }}>金額</th>
                  <th>カテゴリ</th>
                  <th>メモ</th>
                  <th>状態</th>
                </tr>
              </thead>
              <tbody>
                {preview.rows.map((row, i) => (
                  <tr key={i} className={row.validation_error ? "needs-review" : ""}>
                    <td>{row.date}</td>
                    <td>
                      <span style={{
                        color: row.tx_type === "income" ? "#1a7f37" : "#cf222e",
                        fontWeight: "bold",
                      }}>
                        {row.tx_type === "income" ? "収入" : "支出"}
                      </span>
                    </td>
                    <td style={{ textAlign: "right" }}>
                      {row.amount?.toLocaleString() ?? "-"}
                    </td>
                    <td>
                      {row.category || "(空)"}
                      {row.category && row.category !== row.category_raw && (
                        <small style={{ color: "#57606a" }}> ←{row.category_raw}</small>
                      )}
                    </td>
                    <td>{row.memo || "-"}</td>
                    <td>
                      {row.validation_error
                        ? <span className="badge review">{row.validation_message}</span>
                        : <span className="badge ok">OK</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="actions" style={{ marginTop: 12 }}>
            <button onClick={handleCommit} disabled={busy}>取込実行</button>
          </div>
        </div>
      )}
    </div>
  );
}
