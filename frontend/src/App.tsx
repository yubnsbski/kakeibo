import { useState } from "react";
import {
  bytesToBase64,
  decryptBytes,
  encryptBytes,
  generateKey,
  type EncryptedBlob,
} from "./encrypt";

type State =
  | { kind: "idle" }
  | { kind: "encrypted"; blob: EncryptedBlob; key: CryptoKey; mime: string; originalSize: number }
  | { kind: "decrypted"; url: string; mime: string };

export function App() {
  const [state, setState] = useState<State>({ kind: "idle" });
  const [error, setError] = useState<string | null>(null);

  async function handleFile(file: File) {
    setError(null);
    try {
      const bytes = await file.arrayBuffer();
      const key = await generateKey();
      const blob = await encryptBytes(key, bytes);
      setState({
        kind: "encrypted",
        blob,
        key,
        mime: file.type || "application/octet-stream",
        originalSize: file.size,
      });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  async function handleDecrypt() {
    if (state.kind !== "encrypted") return;
    setError(null);
    try {
      const plain = await decryptBytes(state.key, state.blob);
      const blob = new Blob([plain], { type: state.mime });
      const url = URL.createObjectURL(blob);
      setState({ kind: "decrypted", url, mime: state.mime });
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  }

  return (
    <main>
      <h1>kakeibo</h1>

      <section>
        <h2>レシート画像をフロントで暗号化</h2>
        <p className="muted">
          画像はブラウザ内で AES-GCM 暗号化されます。鍵はメモリ上のみで保持し、サーバーには送信しません。
        </p>
        <input
          type="file"
          accept="image/*"
          onChange={(e) => {
            const file = e.target.files?.[0];
            if (file) void handleFile(file);
          }}
        />
        {error && <p style={{ color: "#b91c1c" }}>error: {error}</p>}
      </section>

      {state.kind === "encrypted" && (
        <section>
          <h2>暗号化結果</h2>
          <p className="muted">
            元サイズ: {state.originalSize.toLocaleString()} B / 暗号文サイズ:{" "}
            {state.blob.ciphertext.byteLength.toLocaleString()} B
          </p>
          <p className="muted">MIME: {state.mime}</p>
          <pre>
            iv (base64): {bytesToBase64(state.blob.iv)}
            {"\n"}
            ciphertext (head): {bytesToBase64(
              new Uint8Array(state.blob.ciphertext).slice(0, 24),
            )}
            ...
          </pre>
          <button onClick={() => void handleDecrypt()}>
            メモリ上の鍵で復号して表示
          </button>
        </section>
      )}

      {state.kind === "decrypted" && (
        <section>
          <h2>復号プレビュー</h2>
          {state.mime.startsWith("image/") ? (
            <img
              src={state.url}
              alt="decrypted"
              style={{ maxWidth: "100%", borderRadius: 6 }}
            />
          ) : (
            <a href={state.url} download>
              ダウンロード
            </a>
          )}
        </section>
      )}
    </main>
  );
}
