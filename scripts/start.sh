#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PYTHON="$ROOT_DIR/backend/.venv/bin/python"
VITE="$ROOT_DIR/frontend/node_modules/.bin/vite"

if [[ ! -x "$PYTHON" || ! -x "$VITE" ]]; then
  echo "依存関係が不足しています。先に bash scripts/setup_local.sh を実行してください。" >&2
  exit 1
fi

BACKEND_PID=""
FRONTEND_PID=""

cleanup() {
  local exit_code=$?
  trap - EXIT INT TERM

  if [[ -n "$FRONTEND_PID" ]]; then
    kill "$FRONTEND_PID" 2>/dev/null || true
  fi
  if [[ -n "$BACKEND_PID" ]]; then
    kill "$BACKEND_PID" 2>/dev/null || true
  fi

  [[ -z "$FRONTEND_PID" ]] || wait "$FRONTEND_PID" 2>/dev/null || true
  [[ -z "$BACKEND_PID" ]] || wait "$BACKEND_PID" 2>/dev/null || true
  exit "$exit_code"
}

trap cleanup EXIT INT TERM

cat <<'EOF'
Backend : http://127.0.0.1:8000
Frontend: http://127.0.0.1:5173
停止    : Ctrl-C
EOF

(
  cd "$ROOT_DIR/backend"
  exec "$PYTHON" -m uvicorn app.main:app \
    --host 127.0.0.1 \
    --port 8000
) &
BACKEND_PID=$!

(
  cd "$ROOT_DIR/frontend"
  exec "$VITE" \
    --host 127.0.0.1 \
    --port 5173 \
    --strictPort
) &
FRONTEND_PID=$!

while kill -0 "$BACKEND_PID" 2>/dev/null && kill -0 "$FRONTEND_PID" 2>/dev/null; do
  sleep 1
done

echo "バックエンドまたはフロントエンドが停止しました。上のログを確認してください。" >&2
exit 1
