#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

OUTPUT_ARG="${1:-AI_HANDOFF.local.md}"
if [[ "$OUTPUT_ARG" = /* ]]; then
  OUTPUT_PATH="$OUTPUT_ARG"
else
  OUTPUT_PATH="$ROOT_DIR/$OUTPUT_ARG"
fi

BRANCH="$(git branch --show-current)"
HEAD_SHA="$(git rev-parse --short=12 HEAD)"
BASE_REF="main"
if git show-ref --verify --quiet refs/remotes/origin/main; then
  BASE_REF="origin/main"
fi

if AHEAD_BEHIND="$(git rev-list --left-right --count "$BASE_REF"...HEAD 2>/dev/null)"; then
  BEHIND="${AHEAD_BEHIND%%[[:space:]]*}"
  AHEAD="${AHEAD_BEHIND##*[[:space:]]}"
else
  BEHIND="不明"
  AHEAD="不明"
fi

if git diff --check >/dev/null 2>&1 && git diff --cached --check >/dev/null 2>&1; then
  DIFF_CHECK="OK"
else
  DIFF_CHECK="NG（空白エラー等を確認）"
fi

TMP_FILE="$(mktemp)"
trap 'rm -f "$TMP_FILE"' EXIT

{
  cat <<EOF
# kakeibo AI引継ぎ

生成日時（UTC）: $(date -u '+%Y-%m-%dT%H:%M:%SZ')

## 継続時の指示

- 最初に \`AGENTS.md\`、\`.claude/skills/kakeibo-small-sprint/SKILL.md\`、\`docs/danger-points.md\` を読む。
- 1スプリント1責務で進め、変更前に対象ファイルと検証方法を示す。
- 暗号化ペイロードの後方互換、カテゴリ集計の二重計上、金額式の安全性を壊さない。
- 金額式の実装に \`eval\` を使わない。
- 実装後は \`bash scripts/verify_local.sh\` を実行する。
- CI成功を確認してからsquash mergeする。

## 現在の依頼

- TODO: ここに次の作業内容、受入条件、未解決事項を記入する。

## Git状態

- リポジトリ: $(basename "$ROOT_DIR")
- ブランチ: ${BRANCH:-detached HEAD}
- HEAD: $HEAD_SHA
- 比較基準: $BASE_REF
- 基準よりahead: $AHEAD
- 基準よりbehind: $BEHIND
- diff check: $DIFF_CHECK

### status

\`\`\`text
$(git status --short --branch)
\`\`\`

### 直近コミット

\`\`\`text
$(git log --oneline --decorate -8)
\`\`\`

### $BASE_REF からの変更統計

\`\`\`text
$(git diff --stat "$BASE_REF"...HEAD 2>/dev/null || echo '(比較できません)')
\`\`\`

### 未コミット変更統計

\`\`\`text
$(git diff --stat; git diff --cached --stat)
\`\`\`

## 検証記録

- TODO: 最後に実行したコマンドと結果を記入する。

## セキュリティ注意

この生成物は環境変数、秘密鍵、ファイル本文、差分本文を収集しない。
ただし、ブランチ名・コミットメッセージ・変更ファイル名は含むため、外部へ渡す前に確認する。
EOF
} > "$TMP_FILE"

mv "$TMP_FILE" "$OUTPUT_PATH"
trap - EXIT

echo "AI引継ぎを生成しました: $OUTPUT_PATH"
echo "内容を確認後、ChatGPT等の新しい会話へ貼り付けてください。"
