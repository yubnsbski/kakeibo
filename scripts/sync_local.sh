#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ -n "$(git status --porcelain --untracked-files=normal)" ]]; then
  cat >&2 <<'EOF'
未コミット変更があります。自動退避や破棄は行いません。
先に commit、stash、または不要ファイルの削除を行ってください。
EOF
  git status --short >&2
  exit 1
fi

CURRENT_BRANCH="$(git branch --show-current)"
echo "現在のブランチ: ${CURRENT_BRANCH:-detached HEAD}"

git fetch --prune origin

if git show-ref --verify --quiet refs/heads/main; then
  git switch main
else
  git switch --create main --track origin/main
fi

git pull --ff-only origin main

bash "$ROOT_DIR/scripts/setup_local.sh" "$@"
