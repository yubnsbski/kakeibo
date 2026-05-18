import { useState } from "react";
import { uploadReceipt } from "../api";
import type { ReceiptUploadResponse } from "../types";
import { CsvImportCard } from "./CsvImportCard";

interface Props { onUploaded: () => void; }

export function UploadView({ onUploaded }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<ReceiptUploadResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit() {
    if (!file) { setError("ファイル未選択"); return; }
    setError(null); setBusy(true);
    try {
      const r = await uploadReceipt(file);
      setResult(r);
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="two-col">
      {/* 左カラム: 画像アップロード */}
      <div className="card">
        <h2>レシート画像アップロード</h2>
        <p className="hint">OCR + 分類 + DB保存まで自動.</p>
        <input type="file" accept="image/*" onChange={(e) => {
          setFile(e.target.files?.[0] || null); setResult(null);
        }} />
        <button onClick={handleSubmit} disabled={busy || !file}>
          {busy ? "処理中..." : "送信"}
        </button>
        {error && <p className="err">{error}</p>}
        {result && (
          <div className="result">
            <h3>保存完了 (ID: {result.transaction_id})</h3>
            <table>
              <tbody>
                <tr><th>店舗</th><td>{result.merchant_raw || "(空)"}</td></tr>
                <tr><th>合計(税込)</th><td>{result.total_amount?.toLocaleString() || "-"}円</td></tr>
                <tr><th>税額</th><td>{result.tax_amount.toLocaleString()}円</td></tr>
                <tr><th>カテゴリ</th><td>{result.classification.category || "(未分類)"}</td></tr>
              </tbody>
            </table>
            <button onClick={onUploaded}>一覧で確認・編集</button>
          </div>
        )}
      </div>

      {/* 右カラム: CSV取込 */}
      <CsvImportCard onImported={onUploaded} />
    </div>
  );
}
