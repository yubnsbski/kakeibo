type ClassifyResponse = {
  merchantNormalized: string;
  category: string;
  confidence: number;
  needsReview: boolean;
  reason: string;
};

const app = document.querySelector<HTMLDivElement>("#app");

if (!app) {
  throw new Error("#app element not found");
}

app.innerHTML = `
  <main style="max-width: 720px; margin: 2rem auto; font-family: sans-serif; line-height: 1.6;">
    <h1>家計簿 レシート分類デモ</h1>
    <p>Vite フロントエンド（標準ポート: 5173）から分類APIを呼び出します。</p>

    <form id="classify-form">
      <label>
        店舗名
        <input name="merchantRaw" required style="display:block; width: 100%; margin-top: .25rem;" />
      </label>

      <label style="display:block; margin-top: 1rem;">
        明細（1行に1明細）
        <textarea name="items" rows="6" style="display:block; width: 100%; margin-top: .25rem;"></textarea>
      </label>

      <button type="submit" style="margin-top: 1rem;">分類する</button>
    </form>

    <pre id="result" style="background: #f5f5f5; padding: 1rem; margin-top: 1rem;">ここに結果が表示されます</pre>
  </main>
`;

const form = document.querySelector<HTMLFormElement>("#classify-form");
const result = document.querySelector<HTMLPreElement>("#result");

if (!form || !result) {
  throw new Error("required elements not found");
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();

  const formData = new FormData(form);
  const merchantRaw = String(formData.get("merchantRaw") ?? "").trim();
  const itemsRaw = String(formData.get("items") ?? "");
  const items = itemsRaw
    .split("\n")
    .map((line) => line.trim())
    .filter((line) => line.length > 0);

  try {
    const response = await fetch("http://localhost:3000/classify", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ merchantRaw, items }),
    });

    if (!response.ok) {
      throw new Error(`API error: ${response.status}`);
    }

    const json = (await response.json()) as ClassifyResponse;
    result.textContent = JSON.stringify(json, null, 2);
  } catch (error) {
    result.textContent = `分類失敗: ${error instanceof Error ? error.message : String(error)}`;
  }
});
