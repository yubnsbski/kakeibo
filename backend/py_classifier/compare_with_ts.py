import json
import os
import subprocess
from app.classify import classify_receipt

# ここだけ環境に合わせて修正
# backend から見た TS ソースの場所
TS_SRC_PREFIX = "../src"   # 例: ../src もしくは src
TS_OUT_DIR = ".tmp-compare"

cases = [
    {"merchantRaw": "セブンイレブン 渋谷店", "items": ["おにぎり", "牛乳"], "totalAmount": 620},
    {"merchantRaw": "マツモトキヨシ 新宿店", "items": ["おにぎり"], "totalAmount": 480},
    {"merchantRaw": "Amazon.co.jp", "items": [], "totalAmount": 3000, "userCategoryOverrides": {"Amazon": "通信"}},
    {"merchantRaw": "不明店舗", "items": ["ガソリン"], "totalAmount": 3000},
    {"merchantRaw": "Amazon.co.jp", "items": [], "totalAmount": 3000},
    {"merchantRaw": "Amazon.co.jp", "items": ["イヤホン"], "totalAmount": 3000},
    {"merchantRaw": "未知の店舗", "items": ["未知の品目"], "totalAmount": 1000},
]

def compile_ts():
    files = [
        f"{TS_SRC_PREFIX}/classifyReceipt.ts",
        f"{TS_SRC_PREFIX}/normalizeMerchant.ts",
        f"{TS_SRC_PREFIX}/rules.ts",
        f"{TS_SRC_PREFIX}/types.ts",
    ]
    cmd = ["npx", "tsc", "--outDir", TS_OUT_DIR] + files
    subprocess.check_call(cmd, cwd="/workspaces/kakeibo/backend")

def run_ts(case):
    script = f"""
const {{ classifyReceipt }} = require('./{TS_OUT_DIR}/classifyReceipt.js');
const input = {json.dumps(case, ensure_ascii=False)};
console.log(JSON.stringify(classifyReceipt(input)));
"""
    out = subprocess.check_output(
        ["node", "-e", script],
        cwd="/workspaces/kakeibo/backend",
        text=True
    ).strip()
    return json.loads(out)

def normalize_result(r):
    return {
        "category": r.get("category"),
        "needsReview": r.get("needsReview"),
        "reason": r.get("reason"),
        "screeningLabel": r.get("screeningLabel"),
    }

def main():
    compile_ts()
    failed = 0
    for i, case in enumerate(cases, 1):
        py = classify_receipt(case)
        ts = run_ts(case)
        py_n = normalize_result(py)
        ts_n = normalize_result(ts)
        if py_n != ts_n:
            failed += 1
            print(f"[{i}] DIFF")
            print("  input:", case)
            print("  py   :", py_n)
            print("  ts   :", ts_n)
        else:
            print(f"[{i}] OK")

    if failed:
        raise SystemExit(f"NG: {failed} case(s) diff found")
    print("All cases matched")

if __name__ == "__main__":
    main()