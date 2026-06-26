import { useEffect, useState } from "react";
import type { CSSProperties } from "react";
import {
  createTutorialVideo,
  isTutorialVideoSupported,
  TUTORIAL_SCENES,
  tutorialFileExtension,
} from "./tutorialVideo";

type GenerationState =
  | { kind: "idle" }
  | { kind: "generating"; progress: number }
  | { kind: "ready"; mimeType: string }
  | { kind: "error"; message: string };

const overlayStyle: CSSProperties = {
  position: "fixed",
  inset: 0,
  zIndex: 1000,
  background: "rgba(0, 0, 0, 0.62)",
  display: "grid",
  placeItems: "center",
  padding: 16,
};

const modalStyle: CSSProperties = {
  width: "min(760px, 100%)",
  maxHeight: "92vh",
  overflowY: "auto",
  borderRadius: 16,
  background: "#ffffff",
  color: "#1f2328",
  padding: 20,
  boxShadow: "0 20px 60px rgba(0, 0, 0, 0.3)",
};

const primaryButtonStyle: CSSProperties = {
  background: "#8250df",
  color: "#ffffff",
  WebkitTextFillColor: "#ffffff",
  border: "none",
  borderRadius: 8,
  padding: "9px 14px",
  fontWeight: 750,
  cursor: "pointer",
  whiteSpace: "nowrap",
};

function downloadBlob(blob: Blob, mimeType: string): string {
  const objectUrl = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  const extension = tutorialFileExtension(mimeType);
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, "");
  anchor.href = objectUrl;
  anchor.download = `kakeibo-operation-guide-${date}.${extension}`;
  anchor.style.display = "none";
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  return objectUrl;
}

export function TutorialVideoButton() {
  const [state, setState] = useState<GenerationState>({ kind: "idle" });
  const [previewUrl, setPreviewUrl] = useState<string | null>(null);
  const [fallbackOpen, setFallbackOpen] = useState(false);
  const [fallbackStep, setFallbackStep] = useState(0);

  useEffect(() => {
    return () => {
      if (previewUrl) URL.revokeObjectURL(previewUrl);
    };
  }, [previewUrl]);

  function closePreview() {
    setState({ kind: "idle" });
    setPreviewUrl(null);
  }

  async function handleCreateVideo() {
    if (state.kind === "generating") return;

    if (!isTutorialVideoSupported()) {
      setFallbackStep(0);
      setFallbackOpen(true);
      setState({
        kind: "error",
        message: "このブラウザでは動画生成に対応していないため、画面ガイドを表示します。",
      });
      return;
    }

    setState({ kind: "generating", progress: 0 });

    try {
      const { blob, mimeType } = await createTutorialVideo((progress) => {
        setState({ kind: "generating", progress });
      });

      if (previewUrl) URL.revokeObjectURL(previewUrl);
      const objectUrl = downloadBlob(blob, mimeType);
      setPreviewUrl(objectUrl);
      setState({ kind: "ready", mimeType });
    } catch (error) {
      setState({
        kind: "error",
        message: error instanceof Error ? error.message : String(error),
      });
      setFallbackStep(0);
      setFallbackOpen(true);
    }
  }

  const currentFallbackScene = TUTORIAL_SCENES[fallbackStep];

  return (
    <>
      <button
        type="button"
        style={primaryButtonStyle}
        disabled={state.kind === "generating"}
        onClick={() => void handleCreateVideo()}
      >
        {state.kind === "generating"
          ? `操作動画を作成中 ${Math.round(state.progress * 100)}%`
          : "操作動画を1クリック作成"}
      </button>

      {state.kind === "ready" && previewUrl && (
        <div style={overlayStyle} role="dialog" aria-modal="true" aria-label="操作動画">
          <div style={modalStyle}>
            <h2 style={{ marginTop: 0 }}>操作動画を作成しました</h2>
            <p className="hint">
              動画ファイルを自動保存しました。スマホでは下の動画を再生し、共有メニューから保存できます。
            </p>
            <video
              src={previewUrl}
              controls
              autoPlay
              playsInline
              style={{ width: "100%", borderRadius: 12, background: "#111827" }}
            />
            <div
              style={{
                display: "flex",
                justifyContent: "flex-end",
                gap: 8,
                marginTop: 14,
              }}
            >
              <a
                href={previewUrl}
                download={`kakeibo-operation-guide.${tutorialFileExtension(state.mimeType)}`}
                style={{
                  ...primaryButtonStyle,
                  display: "inline-block",
                  textDecoration: "none",
                }}
              >
                動画を保存
              </a>
              <button type="button" onClick={closePreview}>
                閉じる
              </button>
            </div>
          </div>
        </div>
      )}

      {fallbackOpen && currentFallbackScene && (
        <div style={overlayStyle} role="dialog" aria-modal="true" aria-label="操作ガイド">
          <div style={modalStyle}>
            <div className="hint">
              {fallbackStep + 1} / {TUTORIAL_SCENES.length}
            </div>
            <h2>{currentFallbackScene.title}</h2>
            <p style={{ fontSize: "1.05rem" }}>{currentFallbackScene.description}</p>
            <div
              style={{
                margin: "24px 0",
                padding: 24,
                borderRadius: 14,
                background: "#f6f8fa",
                textAlign: "center",
                fontSize: "2.2rem",
                fontWeight: 850,
              }}
            >
              {currentFallbackScene.amountText}
            </div>
            {state.kind === "error" && (
              <p className="hint">{state.message}</p>
            )}
            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                gap: 8,
              }}
            >
              <button
                type="button"
                disabled={fallbackStep === 0}
                onClick={() => setFallbackStep((step) => Math.max(0, step - 1))}
              >
                前へ
              </button>
              {fallbackStep < TUTORIAL_SCENES.length - 1 ? (
                <button
                  type="button"
                  onClick={() =>
                    setFallbackStep((step) =>
                      Math.min(TUTORIAL_SCENES.length - 1, step + 1),
                    )
                  }
                >
                  次へ
                </button>
              ) : (
                <button
                  type="button"
                  onClick={() => {
                    setFallbackOpen(false);
                    setState({ kind: "idle" });
                  }}
                >
                  完了
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}
