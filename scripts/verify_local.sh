#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT_DIR/backend/.venv/bin/python"

if [[ ! -x "$PYTHON" ]]; then
  echo "backend/.venv がありません。先に bash scripts/setup_local.sh を実行してください。" >&2
  exit 1
fi

printf '\n[1/4] ルート TypeScript 型検査・テスト\n'
(
  cd "$ROOT_DIR"
  npm run verify
)

printf '\n[2/4] フロントエンド本番ビルド\n'
(
  cd "$ROOT_DIR/frontend"
  npm run build
)

printf '\n[3/4] バックエンド全テスト\n'
(
  cd "$ROOT_DIR/backend"
  "$PYTHON" -m unittest discover -s tests -p 'test_*.py'
)

printf '\n[4/4] バックエンド起動モジュール import\n'
(
  cd "$ROOT_DIR/backend"
  "$PYTHON" -c 'from app.main import app; assert app.title == "kakeibo API"'
)

printf '\n全検証が完了しました。\n'
