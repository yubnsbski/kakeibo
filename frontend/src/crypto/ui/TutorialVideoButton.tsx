import { useState } from "react";

type Status =
  | { kind: "idle" }
  | { kind: "recording" }
  | { kind: "done"; sizeBytes: number }
  | { kind: "error"; message: string };

const WIDTH = 540;
const HEIGHT = 304;
const FPS = 8;
const DURATION_MS = 7600;
const VIDEO_BITS_PER_SECOND = 220_000;

const steps = [
  {
    title: "1. 金額は0円からスタート",
    detail: "数字キーを押すと、支払額へすぐ反映されます。",
    amount: "¥0",
  },
  {
    title: "2. 税込／税抜を選択",
    detail: "税抜入力なら税込支払額を自動計算します。",
    amount: "¥1,100",
  },
  {
    title: "3. 明細を追加",
    detail: "最初の明細には計算結果がそのまま入ります。",
    amount: "明細 1,100円",
  },
  {
    title: "4. 保存・集計",
    detail: "保存後、日・月・年のカテゴリ別合計へ反映されます。",
    amount: "集計OK",
  },
];

function bestMimeType(): string {
  const candidates = [
    "video/webm;codecs=vp9",
    "video/webm;codecs=vp8",
    "video/webm",
    "video/mp4",
  ];

  return candidates.find((candidate) => MediaRecorder.isTypeSupported(candidate)) ?? "";
}

function drawRoundedRect(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
): void {
  const r = Math.min(radius, width / 2, height / 2);
  context.beginPath();
  context.moveTo(x + r, y);
  context.lineTo(x + width - r, y);
  context.quadraticCurveTo(x + width, y, x + width, y + r);
  context.lineTo(x + width, y + height - r);
  context.quadraticCurveTo(x + width, y + height, x + width - r, y + height);
  context.lineTo(x + r, y + height);
  context.quadraticCurveTo(x, y + height, x, y + height - r);
  context.lineTo(x, y + r);
  context.quadraticCurveTo(x, y, x + r, y);
  context.closePath();
}

function drawText(
  context: CanvasRenderingContext2D,
  text: string,
  x: number,
  y: number,
  options: {
    size: number;
    weight?: number;
    color?: string;
    align?: CanvasTextAlign;
  },
): void {
  context.fillStyle = options.color ?? "#1f2328";
  context.font = `${options.weight ?? 600} ${options.size}px -apple-system, BlinkMacSystemFont, Segoe UI, sans-serif`;
  context.textAlign = options.align ?? "left";
  context.textBaseline = "top";
  context.fillText(text, x, y);
}

function drawFrame(
  canvas: HTMLCanvasElement,
  elapsedMs: number,
): void {
  const context = canvas.getContext("2d");
  if (!context) throw new Error("Canvasを初期化できません");

  const progress = Math.min(elapsedMs / DURATION_MS, 0.999);
  const stepIndex = Math.min(
    Math.floor(progress * steps.length),
    steps.length - 1,
  );
  const step = steps[stepIndex];
  const localProgress = progress * steps.length - stepIndex;
  const eased = 1 - Math.pow(1 - localProgress, 3);

  context.fillStyle = "#f6f8fa";
  context.fillRect(0, 0, WIDTH, HEIGHT);

  context.fillStyle = "#1f6feb";
  context.fillRect(0, 0, WIDTH, 48);
  drawText(context, "kakeibo 操作チュートリアル", 22, 13, {
    size: 18,
    weight: 800,
    color: "#ffffff",
  });

  context.fillStyle = "#ffffff";
  drawRoundedRect(context, 24, 70, WIDTH - 48, 188, 18);
  context.fill();
  context.strokeStyle = "#d0d7de";
  context.lineWidth = 1;
  context.stroke();

  drawText(context, step.title, 46, 92, {
    size: 21,
    weight: 800,
  });
  drawText(context, step.detail, 46, 128, {
    size: 15,
    weight: 600,
    color: "#57606a",
  });

  context.save();
  context.globalAlpha = 0.18;
  context.fillStyle = "#2da44e";
  drawRoundedRect(context, 46, 172, 260 * eased, 42, 999);
  context.fill();
  context.restore();

  drawText(context, step.amount, 58, 177, {
    size: 28,
    weight: 900,
    color: "#116329",
  });

  steps.forEach((_step, index) => {
    context.fillStyle = index <= stepIndex ? "#1f6feb" : "#d8dee4";
    context.beginPath();
    context.arc(46 + index * 28, 234, 6, 0, Math.PI * 2);
    context.fill();
  });

  drawText(context, "軽量WebM / 音声なし", WIDTH - 28, HEIGHT - 28, {
    size: 11,
    weight: 600,
    color: "#6e7781",
    align: "right",
  });
}

function downloadBlob(blob: Blob): void {
  const extension = blob.type.includes("mp4") ? "mp4" : "webm";
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = `kakeibo-tutorial.${extension}`;
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 2_000);
}

async function createTutorialVideo(): Promise<Blob> {
  if (typeof MediaRecorder === "undefined") {
    throw new Error("このブラウザは動画作成に対応していません");
  }

  const mimeType = bestMimeType();
  if (!mimeType) {
    throw new Error("このブラウザで利用できる軽量動画形式が見つかりません");
  }

  const canvas = document.createElement("canvas");
  canvas.width = WIDTH;
  canvas.height = HEIGHT;
  drawFrame(canvas, 0);

  const stream = canvas.captureStream(FPS);
  const chunks: BlobPart[] = [];
  const recorder = new MediaRecorder(stream, {
    mimeType,
    videoBitsPerSecond: VIDEO_BITS_PER_SECOND,
  });

  const done = new Promise<Blob>((resolve, reject) => {
    recorder.ondataavailable = (event) => {
      if (event.data.size > 0) chunks.push(event.data);
    };
    recorder.onerror = () => reject(new Error("動画作成中にエラーが発生しました"));
    recorder.onstop = () => {
      stream.getTracks().forEach((track) => track.stop());
      resolve(new Blob(chunks, { type: mimeType }));
    };
  });

  const startedAt = performance.now();
  recorder.start(500);

  await new Promise<void>((resolve) => {
    function tick(now: number) {
      const elapsed = now - startedAt;
      drawFrame(canvas, elapsed);
      if (elapsed < DURATION_MS) {
        window.requestAnimationFrame(tick);
      } else {
        resolve();
      }
    }
    window.requestAnimationFrame(tick);
  });

  recorder.stop();
  return done;
}

export function TutorialVideoButton() {
  const [status, setStatus] = useState<Status>({ kind: "idle" });

  async function handleCreate() {
    setStatus({ kind: "recording" });
    try {
      const blob = await createTutorialVideo();
      downloadBlob(blob);
      setStatus({ kind: "done", sizeBytes: blob.size });
    } catch (error) {
      setStatus({
        kind: "error",
        message: error instanceof Error ? error.message : String(error),
      });
    }
  }

  return (
    <div style={{ display: "inline-flex", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
      <button
        type="button"
        onClick={() => void handleCreate()}
        disabled={status.kind === "recording"}
        title="操作方法の軽量動画を作成します"
      >
        {status.kind === "recording" ? "動画作成中..." : "操作動画を作成"}
      </button>
      {status.kind === "done" && (
        <span className="hint">{Math.ceil(status.sizeBytes / 1024)}KB</span>
      )}
      {status.kind === "error" && (
        <span className="err">{status.message}</span>
      )}
    </div>
  );
}
