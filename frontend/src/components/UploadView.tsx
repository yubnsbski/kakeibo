import { useState } from "react";
import { previewReceipt } from "../api";
import type { ReceiptPreviewResponse } from "../api";
import { encryptJson, requireKey } from "../crypto";
import { createEncryptedTx } from "../crypto/encryptedTxApi";
import { CsvImportCard } from "./CsvImportCard";

interface Props {
  onUploaded: () => void;
}

type EncryptedOcrPayload = {
  source: "receipt_ocr";
  saved_mode: "encrypted";
  version: 1;
  preview: ReceiptPreviewResponse;
};

export function UploadView({ onUploaded }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [busy, setBusy] = useState(false);
  const [saving, setSaving] = useState(false);
  const [preview, setPreview] = useState<ReceiptPreviewResponse | null>(null);
  const [error, setError] = useState<string | null>(null);

  async function handlePreview() {
    if (!file) {
      setError("ファイル未選択");
      return;
    }

    setError(null);
    setBusy(true);

    try {
      const result = await previewReceipt(file);
      setPreview(result);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  }

  async function handleConfirmEncryptedSave() {
    if (!preview) {
      setError("OCR結果がありません");
      return;
    }

    setError(null);
    setSaving(true);

    try {
      const payload: EncryptedOcrPayload = {
        source: "receipt_ocr",
        saved_mode: "encrypted",
        version: 1,
        preview,
      };

      const encryptedRecord = await encryptJson(requireKey(), payload);
      await createEncryptedTx(JSON.stringify(encryptedRecord), 1);

      setFile(null);
      setPreview(null);
      onUploaded();
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setSaving(false);
    }
  }

  return (
    <div className="two-col">
      <div className="card">
        <h2>レシートOCR取込</h2>

        <p className="hint">
          画像はOCR確認用に送信されます。preview endpointでは画像・OCR結果・取引をDB保存しません。
          内容を確認してから暗号化保存します。
        </p>

        <input
          type="file"
          accept="image/*"
          onChange={(e) => {
            setFile(e.target.files?.[0] || null);
            setPreview(null);
            setError(null);
          }}
        />

        <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginTop: 12 }}>
          <button onClick={handlePreview} disabled={busy || saving || !file}>
            {busy ? "OCR中..." : "OCRして確認"}
          </button>

          <button
            onClick={handleConfirmEncryptedSave}
            disabled={busy || saving || !preview}
          >
            {saving ? "暗号化保存中..." : "確認して暗号化保存"}
          </button>
        </div>

        {error && <p className="err">{error}</p>}

        {preview && (
          <div className="result">
            <h3>OCR確認</h3>

            <table>
              <tbody>
                <tr>
                  <th>店舗</th>
                  <td>{preview.merchant_raw || "(空)"}</td>
                </tr>
                <tr>
                  <th>日付</th>
                  <td>{preview.purchased_at}</td>
                </tr>
                <tr>
                  <th>合計(税込)</th>
                  <td>{preview.amount.toLocaleString()}円</td>
                </tr>
                <tr>
                  <th>税額</th>
                  <td>{preview.tax_amount.toLocaleString()}円</td>
                </tr>
                <tr>
                  <th>カテゴリ</th>
                  <td>{preview.category || "(未分類)"}</td>
                </tr>
                <tr>
                  <th>要確認</th>
                  <td>{preview.needs_review ? "はい" : "いいえ"}</td>
                </tr>
              </tbody>
            </table>

            <h4>明細</h4>
            {preview.line_items.length === 0 ? (
              <p className="hint">明細は検出されませんでした。</p>
            ) : (
              <table>
                <thead>
                  <tr>
                    <th>品目</th>
                    <th>金額</th>
                    <th>カテゴリ</th>
                  </tr>
                </thead>
                <tbody>
                  {preview.line_items.map((item, index) => (
                    <tr key={`${item.item}-${index}`}>
                      <td>{item.item}</td>
                      <td>{item.amount.toLocaleString()}円</td>
                      <td>{item.category || "(未分類)"}</td>
                    </tr>
                  ))}
                </tbody>
              </table>
            )}

            <p className="hint">
              内容に問題なければ「確認して暗号化保存」を押してください。
              保存後は encrypted_transactions に暗号文として保存されます。
            </p>
          </div>
        )}
      </div>

      <CsvImportCard onImported={onUploaded} />
    </div>
  );
}
