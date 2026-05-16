import { useState } from "react";
import "./App.css";

type ClassificationResult = {
  merchantNormalized: string;
  category: string | null;
  confidence: number;
  reason: string;
  reasons: string[];
  needsReview: boolean;
};

export default function App() {
  const [merchantRaw, setMerchantRaw] = useState("");
  const [itemsText, setItemsText] = useState("");
  const [totalAmount, setTotalAmount] = useState("");
  const [purchasedAt, setPurchasedAt] = useState("");

  const [error, setError] = useState("");
  const [result, setResult] = useState<ClassificationResult | null>(null);
  const [loading, setLoading] = useState(false);

  function validate(): string | null {
    if (!merchantRaw.trim()) return "店舗名を入力してください";
    if (Number(totalAmount) <= 0) return "金額は0より大きい値を入力してください";
    if (!/^\d{4}-\d{2}-\d{2}$/.test(purchasedAt)) return "日付はYYYY-MM-DD形式で入力してください";
    return null;
  }

  async function runClassification() {
    setError("");
    setResult(null);

    const validationError = validate();
    if (validationError) {
      setError(validationError);
      return;
    }

    setLoading(true);
    try {
      const payload = {
        merchantRaw,
        items: itemsText
          .split("|")
          .map((s) => s.trim())
          .filter(Boolean),
        totalAmount: Number(totalAmount),
        purchasedAt
      };

      const res = await fetch("http://localhost:3000/classify", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload)
      });

      if (!res.ok) {
        throw new Error(`APIエラー: ${res.status}`);
      }

      const data = (await res.json()) as ClassificationResult;
      setResult(data);
    } catch (e: any) {
      setError(e.message ?? "分類実行に失敗しました");
    } finally {
      setLoading(false);
    }
  }

  return (
    <main style={{ maxWidth: 720, margin: "24px auto", padding: 16 }}>
      <h1>家計簿 分類フロント</h1>

      <div style={{ display: "grid", gap: 8 }}>
        <input
          placeholder="店舗名 merchantRaw"
          value={merchantRaw}
          onChange={(e) => setMerchantRaw(e.target.value)}
        />
        <input
          placeholder="明細 items（例: おにぎり|牛乳）"
          value={itemsText}
          onChange={(e) => setItemsText(e.target.value)}
        />
        <input
          placeholder="金額 totalAmount"
          value={totalAmount}
          onChange={(e) => setTotalAmount(e.target.value)}
        />
        <input
          placeholder="日付 purchasedAt（YYYY-MM-DD）"
          value={purchasedAt}
          onChange={(e) => setPurchasedAt(e.target.value)}
        />

        <button onClick={runClassification} disabled={loading}>
          {loading ? "実行中..." : "分類実行"}
        </button>
      </div>

      {error && <p style={{ color: "crimson", fontWeight: 700 }}>{error}</p>}

      {result && (
        <pre style={{ marginTop: 16, background: "#111827", color: "#dbeafe", padding: 12, borderRadius: 8 }}>
          {JSON.stringify(result, null, 2)}
        </pre>
      )}
    </main>
  );
}