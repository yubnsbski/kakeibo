export type TutorialScene = {
  title: string;
  description: string;
  accent: "mode" | "keypad" | "tax" | "summary" | "items" | "save";
  amountText: string;
};

export const TUTORIAL_SCENES: readonly TutorialScene[] = [
  {
    title: "1. 税込・税抜を選ぶ",
    description: "入力する金額の種類を最初に選択します。",
    accent: "mode",
    amountText: "¥0",
  },
  {
    title: "2. 数字キーで金額を入力",
    description: "0円から開始し、押した数字がすぐ画面へ反映されます。",
    accent: "keypad",
    amountText: "¥1,000",
  },
  {
    title: "3. 税率を選ぶ",
    description: "0%、8%、10%はワンタップ。その他の税率も入力できます。",
    accent: "tax",
    amountText: "¥1,100",
  },
  {
    title: "4. 金額の内訳を確認",
    description: "税抜・消費税・税込支払額を同時に確認します。",
    accent: "summary",
    amountText: "¥1,100",
  },
  {
    title: "5. 明細を追加",
    description: "最初の明細には現在の税込計算結果が自動で入ります。",
    accent: "items",
    amountText: "¥1,100",
  },
  {
    title: "6. 保存して集計",
    description: "暗号化保存後、日・月・年のカテゴリ別合計を確認できます。",
    accent: "save",
    amountText: "¥1,100",
  },
] as const;

export const TUTORIAL_SCENE_DURATION_MS = 1500;
export const TUTORIAL_WIDTH = 1280;
export const TUTORIAL_HEIGHT = 720;

const MIME_CANDIDATES = [
  "video/webm;codecs=vp9",
  "video/webm;codecs=vp8",
  "video/webm",
  "video/mp4",
] as const;

type MimeSupport = (mimeType: string) => boolean;

type CanvasWithCaptureStream = HTMLCanvasElement & {
  captureStream(frameRate?: number): MediaStream;
};

export function selectTutorialMimeType(
  isSupported: MimeSupport,
): string | null {
  return MIME_CANDIDATES.find((mimeType) => isSupported(mimeType)) ?? null;
}

export function tutorialFileExtension(mimeType: string): "mp4" | "webm" {
  return mimeType.includes("mp4") ? "mp4" : "webm";
}

export function tutorialDurationMs(): number {
  return TUTORIAL_SCENES.length * TUTORIAL_SCENE_DURATION_MS;
}

export function isTutorialVideoSupported(): boolean {
  return (
    typeof window !== "undefined" &&
    typeof MediaRecorder !== "undefined" &&
    typeof HTMLCanvasElement !== "undefined" &&
    "captureStream" in HTMLCanvasElement.prototype &&
    selectTutorialMimeType((mimeType) =>
      MediaRecorder.isTypeSupported(mimeType),
    ) !== null
  );
}

function roundedRect(
  context: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
  fill: string,
  stroke?: string,
) {
  context.beginPath();
  context.roundRect(x, y, width, height, radius);
  context.fillStyle = fill;
  context.fill();
  if (stroke) {
    context.strokeStyle = stroke;
    context.lineWidth = 2;
    context.stroke();
  }
}

function text(
  context: CanvasRenderingContext2D,
  value: string,
  x: number,
  y: number,
  size: number,
  weight: number,
  color: string,
  align: CanvasTextAlign = "left",
) {
  context.save();
  context.font = `${weight} ${size}px -apple-system, BlinkMacSystemFont, "Hiragino Sans", "Yu Gothic", sans-serif`;
  context.fillStyle = color;
  context.textAlign = align;
  context.textBaseline = "middle";
  context.fillText(value, x, y);
  context.restore();
}

function drawModeButtons(
  context: CanvasRenderingContext2D,
  highlighted: boolean,
) {
  roundedRect(
    context,
    740,
    205,
    190,
    58,
    14,
    highlighted ? "#1f6feb" : "#e8edf3",
  );
  roundedRect(context, 945, 205, 190, 58, 14, "#ffffff", "#b6bec8");
  text(
    context,
    "税込で入力",
    835,
    234,
    23,
    750,
    highlighted ? "#ffffff" : "#1f2328",
    "center",
  );
  text(context, "税抜で入力", 1040, 234, 23, 750, "#1f2328", "center");
}

function drawTaxButtons(
  context: CanvasRenderingContext2D,
  highlighted: boolean,
) {
  const values = ["0%", "8%", "10%"];
  values.forEach((value, index) => {
    const selected = value === "10%";
    roundedRect(
      context,
      760 + index * 110,
      286,
      94,
      48,
      24,
      selected && highlighted ? "#dafbe1" : "#ffffff",
      selected && highlighted ? "#2da44e" : "#b6bec8",
    );
    text(
      context,
      value,
      807 + index * 110,
      310,
      21,
      750,
      selected && highlighted ? "#116329" : "#1f2328",
      "center",
    );
  });
}

function drawKeypad(
  context: CanvasRenderingContext2D,
  highlighted: boolean,
  sceneProgress: number,
) {
  const keys = [
    "7", "8", "9", "÷",
    "4", "5", "6", "×",
    "1", "2", "3", "−",
    "00", "0", ".", "+",
  ];
  const typedSequence = ["1", "0", "0", "0"];
  const activeIndex = Math.min(
    typedSequence.length - 1,
    Math.floor(sceneProgress * typedSequence.length),
  );

  keys.forEach((key, index) => {
    const column = index % 4;
    const row = Math.floor(index / 4);
    const x = 735 + column * 102;
    const y = 360 + row * 64;
    const isOperator = column === 3;
    const active = highlighted && key === typedSequence[activeIndex];
    roundedRect(
      context,
      x,
      y,
      88,
      52,
      12,
      active ? "#fde68a" : isOperator ? "#dbeafe" : "#ffffff",
      active ? "#d97706" : isOperator ? "#93c5fd" : "#b6bec8",
    );
    text(
      context,
      key,
      x + 44,
      y + 27,
      23,
      800,
      isOperator ? "#075985" : "#111827",
      "center",
    );
  });
}

function drawSummary(
  context: CanvasRenderingContext2D,
  highlighted: boolean,
) {
  const cells = [
    ["税抜", "1,000円"],
    ["消費税", "100円"],
    ["税込", "1,100円"],
  ] as const;

  cells.forEach(([label, value], index) => {
    roundedRect(
      context,
      735 + index * 138,
      630,
      126,
      66,
      10,
      highlighted && index === 2 ? "#eefbf2" : "#ffffff",
      highlighted && index === 2 ? "#2da44e" : "#d8dee4",
    );
    text(context, label, 798 + index * 138, 650, 16, 650, "#57606a", "center");
    text(context, value, 798 + index * 138, 678, 18, 800, "#1f2328", "center");
  });
}

function drawLineItem(
  context: CanvasRenderingContext2D,
  highlighted: boolean,
) {
  roundedRect(
    context,
    720,
    548,
    440,
    68,
    12,
    highlighted ? "#fff8c5" : "#ffffff",
    highlighted ? "#d4a72c" : "#d8dee4",
  );
  text(context, "品目名", 748, 582, 18, 650, "#57606a");
  text(context, "食費", 940, 582, 18, 700, "#1f2328", "center");
  text(context, "1,100円", 1128, 582, 21, 850, "#1f2328", "right");
}

function drawSaveButton(
  context: CanvasRenderingContext2D,
  highlighted: boolean,
) {
  roundedRect(
    context,
    795,
    548,
    300,
    62,
    31,
    highlighted ? "#2da44e" : "#8c959f",
  );
  text(
    context,
    "税込1,100円を暗号化保存",
    945,
    580,
    21,
    800,
    "#ffffff",
    "center",
  );
}

function drawTutorialFrame(
  context: CanvasRenderingContext2D,
  elapsedMs: number,
) {
  const totalDuration = tutorialDurationMs();
  const boundedElapsed = Math.min(Math.max(elapsedMs, 0), totalDuration - 1);
  const sceneIndex = Math.min(
    TUTORIAL_SCENES.length - 1,
    Math.floor(boundedElapsed / TUTORIAL_SCENE_DURATION_MS),
  );
  const scene = TUTORIAL_SCENES[sceneIndex];
  const sceneProgress =
    (boundedElapsed % TUTORIAL_SCENE_DURATION_MS) /
    TUTORIAL_SCENE_DURATION_MS;
  const fade = Math.min(1, sceneProgress / 0.12, (1 - sceneProgress) / 0.12);

  const gradient = context.createLinearGradient(0, 0, TUTORIAL_WIDTH, TUTORIAL_HEIGHT);
  gradient.addColorStop(0, "#f6f8fa");
  gradient.addColorStop(1, "#e8f3ff");
  context.fillStyle = gradient;
  context.fillRect(0, 0, TUTORIAL_WIDTH, TUTORIAL_HEIGHT);

  text(context, "kakeibo 操作ガイド", 68, 58, 28, 850, "#1f2328");
  text(
    context,
    `${sceneIndex + 1} / ${TUTORIAL_SCENES.length}`,
    1210,
    58,
    18,
    700,
    "#57606a",
    "right",
  );

  roundedRect(context, 68, 96, 560, 550, 24, "#ffffff", "#d0d7de");
  context.save();
  context.globalAlpha = Math.max(0.35, fade);
  text(context, scene.title, 104, 180, 38, 850, "#0969da");
  text(context, scene.description, 104, 250, 24, 600, "#1f2328");
  text(context, scene.amountText, 104, 390, 74, 900, "#111827");
  text(
    context,
    scene.accent === "items"
      ? "明細金額は自動入力"
      : scene.accent === "save"
        ? "保存後は集計タブへ"
        : "入力内容をその場で確認",
    104,
    500,
    24,
    750,
    "#116329",
  );
  context.restore();

  roundedRect(context, 684, 96, 528, 610, 24, "#ffffff", "#d0d7de");
  text(context, "金額を計算", 720, 150, 27, 850, "#1f2328");
  drawModeButtons(context, scene.accent === "mode");
  drawTaxButtons(context, scene.accent === "tax");
  drawKeypad(context, scene.accent === "keypad", sceneProgress);

  if (scene.accent === "items") {
    drawLineItem(context, true);
  } else if (scene.accent === "save") {
    drawSaveButton(context, true);
  } else {
    drawSummary(context, scene.accent === "summary");
  }

  const progress = Math.min(1, elapsedMs / totalDuration);
  context.fillStyle = "#d0d7de";
  context.fillRect(68, 680, 560, 8);
  context.fillStyle = "#1f6feb";
  context.fillRect(68, 680, 560 * progress, 8);
}

function nextAnimationFrame(): Promise<void> {
  return new Promise((resolve) => requestAnimationFrame(() => resolve()));
}

function wait(milliseconds: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, milliseconds));
}

export async function createTutorialVideo(
  onProgress?: (progress: number) => void,
): Promise<{ blob: Blob; mimeType: string }> {
  if (!isTutorialVideoSupported()) {
    throw new Error("このブラウザはチュートリアル動画の生成に対応していません");
  }

  const mimeType = selectTutorialMimeType((candidate) =>
    MediaRecorder.isTypeSupported(candidate),
  );
  if (!mimeType) {
    throw new Error("利用可能な動画形式がありません");
  }

  const canvas = document.createElement("canvas") as CanvasWithCaptureStream;
  canvas.width = TUTORIAL_WIDTH;
  canvas.height = TUTORIAL_HEIGHT;

  const context = canvas.getContext("2d");
  if (!context) throw new Error("動画描画用Canvasを作成できません");

  const stream = canvas.captureStream(30);
  const chunks: BlobPart[] = [];
  const recorder = new MediaRecorder(stream, {
    mimeType,
    videoBitsPerSecond: 3_000_000,
  });

  const stopped = new Promise<void>((resolve, reject) => {
    recorder.addEventListener("dataavailable", (event) => {
      if (event.data.size > 0) chunks.push(event.data);
    });
    recorder.addEventListener("stop", () => resolve(), { once: true });
    recorder.addEventListener(
      "error",
      () => reject(new Error("動画の記録中にエラーが発生しました")),
      { once: true },
    );
  });

  const duration = tutorialDurationMs();
  drawTutorialFrame(context, 0);
  recorder.start(250);
  const startedAt = performance.now();

  while (true) {
    const elapsed = performance.now() - startedAt;
    if (elapsed >= duration) break;
    drawTutorialFrame(context, elapsed);
    onProgress?.(Math.min(0.99, elapsed / duration));
    await nextAnimationFrame();
  }

  drawTutorialFrame(context, duration - 1);
  onProgress?.(1);
  await wait(120);
  recorder.stop();
  await stopped;
  stream.getTracks().forEach((track) => track.stop());

  const blob = new Blob(chunks, { type: recorder.mimeType || mimeType });
  if (blob.size === 0) throw new Error("生成された動画が空です");

  return {
    blob,
    mimeType: recorder.mimeType || mimeType,
  };
}
