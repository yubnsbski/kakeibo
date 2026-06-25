#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WITH_GEMINI=false

usage() {
  cat <<'EOF'
Usage: bash scripts/setup_local.sh [--with-gemini]

  --with-gemini  Install the optional Gemini OCR SDK and create backend/.env
EOF
}

for arg in "$@"; do
  case "$arg" in
    --with-gemini)
      WITH_GEMINI=true
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "$1 が見つかりません。README.md の前提ツールを確認してください。" >&2
    exit 1
  fi
}

require_command node
require_command npm
require_command python3

NODE_MAJOR="$(node -p 'Number(process.versions.node.split(".")[0])')"
if (( NODE_MAJOR < 22 )); then
  echo "Node.js 22 以降が必要です。現在: $(node --version)" >&2
  exit 1
fi

read -r PY_MAJOR PY_MINOR < <(
  python3 -c 'import sys; print(sys.version_info.major, sys.version_info.minor)'
)
if (( PY_MAJOR < 3 || (PY_MAJOR == 3 && PY_MINOR < 12) )); then
  echo "Python 3.12 以降が必要です。現在: $(python3 --version)" >&2
  exit 1
fi

printf '\n[1/5] Python 仮想環境\n'
VENV_DIR="$ROOT_DIR/backend/.venv"
if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  if ! python3 -m venv "$VENV_DIR"; then
    echo "仮想環境を作成できませんでした。Debian/Ubuntuでは python3-venv を確認してください。" >&2
    exit 1
  fi
fi
PYTHON="$VENV_DIR/bin/python"
"$PYTHON" -m pip install --disable-pip-version-check --upgrade pip

REQUIREMENTS="$ROOT_DIR/backend/requirements.txt"
if [[ "$WITH_GEMINI" == true ]]; then
  REQUIREMENTS="$ROOT_DIR/backend/requirements-gemini.txt"
fi
"$PYTHON" -m pip install --disable-pip-version-check -r "$REQUIREMENTS"

if [[ "$WITH_GEMINI" == true && ! -f "$ROOT_DIR/backend/.env" ]]; then
  cp "$ROOT_DIR/backend/.env.example" "$ROOT_DIR/backend/.env"
  echo "backend/.env を作成しました。GEMINI_API_KEY は手動で設定してください。"
fi

printf '\n[2/5] ルート依存関係\n'
(
  cd "$ROOT_DIR"
  npm ci --no-audit --no-fund
)

printf '\n[3/5] フロントエンド依存関係\n'
(
  cd "$ROOT_DIR/frontend"
  npm ci --no-audit --no-fund
)

printf '\n[4/5] OCR実行環境の確認\n'
if command -v tesseract >/dev/null 2>&1; then
  if tesseract --list-langs 2>/dev/null | grep -qx 'jpn'; then
    echo "Tesseract 日本語データ: 利用可能"
  else
    echo "注意: Tesseract はありますが日本語データ jpn がありません。OCR利用前に追加してください。" >&2
  fi
else
  echo "注意: Tesseract本体がありません。Gemini未設定時のOCRは利用できません。" >&2
fi

printf '\n[5/5] 検証\n'
bash "$ROOT_DIR/scripts/verify_local.sh"

cat <<'EOF'

セットアップ完了。
起動: bash scripts/start.sh
停止: 起動中のターミナルで Ctrl-C
EOF
