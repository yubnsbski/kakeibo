import { readFileSync } from "node:fs";
import { join } from "node:path";
import { describe, test } from "vitest";
import { mineKeywords, type LabeledExample } from "../src/keywordMiner";
import { itemKeywordRules } from "../src/rules";

const REPORT_MODE = process.env.MINE_KEYWORDS_REPORT === "1";

describe.skipIf(!REPORT_MODE)("keyword mining report", () => {
  test("prints candidate keywords (no assertions)", () => {
    const filePath = join(__dirname, "..", "fixtures", "training", "labeled-items.json");
    const examples = JSON.parse(readFileSync(filePath, "utf-8")) as LabeledExample[];

    const candidates = mineKeywords(examples, {
      minLength: 2,
      maxLength: 3,
      minSupport: 2,
      minPurity: 0.8,
      excludeExistingKeywords: Object.keys(itemKeywordRules)
    });

    console.log("\n# 明細キーワード候補（rules.tsへの反映は人手レビュー後に手動で）");
    console.log("# keyword\tcategory\tsupport\tpurity\tscore");
    if (candidates.length === 0) {
      console.log("(候補なし: minSupport/minPurityを緩めるか学習データを増やしてください)");
      return;
    }
    for (const c of candidates) {
      console.log(`${c.keyword}\t${c.category}\t${c.support}\t${c.purity.toFixed(2)}\t${c.score.toFixed(2)}`);
    }
  });
});
