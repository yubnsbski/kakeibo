import { useState } from "react";
import { previewCsv, commitCsv } from "../api";
import type { CsvPreviewResponse } from "../api";

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
    if (!file) return;
    if (!confirm(`${preview?.total ?? 0}件を取り込みますか?`)) return;
    setBusy(true);
    try {
      const r = await commitCsv(file);
      setImportResult(`取込完了: ${r.inserted}件 (エラー${r.error_count}件)`);
      setPreview(null); setFile(null);
      onImported();
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>CSV 一括取込</h2>
      <p className="hint">
        ヘッダ固定: <code>date,amount,category,memo</code><br />
        例: <code>2026-05-15,620,食費,セブンイレブン</code>
      </p>
      <input type="file" accept=".csv,text/csv" onChange={(e) => {
        setFile(e.target.files?.[0] || null);
        setPreview(null);
        setImportResult(null);
      }} />
      <button onClick={handlePreview} disabled={busy || !file}>
        プレビュー
      </button>
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
          <div style={{ maxHeight: 300, overflowY: "auto" }}>
            <table className="tx-table" style={{ fontSize: "0.82em" }}>
              <thead>
                <tr>
                  <th>日付</th>
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
                    <td style={{ textAlign: "right" }}>
                      {row.amount?.toLocaleString() ?? "-"}
                    </td>
                    <td>{row.category || "(空)"}</td>
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
