#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -x "$ROOT_DIR/backend/.venv/bin/python" ]; then
  PYTHON="$ROOT_DIR/backend/.venv/bin/python"
elif command -v python3 >/dev/null 2>&1; then
  PYTHON="$(command -v python3)"
else
  echo "python3 が見つかりません。" >&2
  exit 1
fi

exec "$PYTHON" "$ROOT_DIR/scripts/data_manager.py" "$@"
