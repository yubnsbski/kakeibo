import { describe, expect, test } from "vitest";
import {
  selectTutorialMimeType,
  TUTORIAL_SCENES,
  TUTORIAL_SCENE_DURATION_MS,
  tutorialDurationMs,
  tutorialFileExtension,
} from "../frontend/src/tutorial/tutorialVideo.js";

describe("tutorial video helpers", () => {
  test("利用可能な動画形式を優先順で選ぶ", () => {
    const supported = new Set(["video/webm", "video/mp4"]);
    expect(selectTutorialMimeType((mimeType) => supported.has(mimeType))).toBe(
      "video/webm",
    );
  });

  test("対応形式がなければnullを返す", () => {
    expect(selectTutorialMimeType(() => false)).toBeNull();
  });

  test("MIME形式から保存拡張子を選ぶ", () => {
    expect(tutorialFileExtension("video/mp4")).toBe("mp4");
    expect(tutorialFileExtension("video/webm;codecs=vp8")).toBe("webm");
  });

  test("全操作ステップを含む動画時間を計算する", () => {
    expect(TUTORIAL_SCENES).toHaveLength(6);
    expect(tutorialDurationMs()).toBe(
      TUTORIAL_SCENES.length * TUTORIAL_SCENE_DURATION_MS,
    );
    expect(TUTORIAL_SCENES.map((scene) => scene.accent)).toEqual([
      "mode",
      "keypad",
      "tax",
      "summary",
      "items",
      "save",
    ]);
  });
});
