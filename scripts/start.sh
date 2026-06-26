#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BACKEND_DIR="$ROOT_DIR/backend"
FRONTEND_DIR="$ROOT_DIR/frontend"
BACKEND_LOG="/tmp/kakeibo-backend.log"
FRONTEND_LOG="/tmp/kakeibo-frontend.log"
CERT_SERVER_LOG="/tmp/kakeibo-certificate-server.log"
REQUESTED_LAN_IP="${KAKEIBO_LAN_IP:-192.168.3.5}"
HTTPS_KEY="${KAKEIBO_HTTPS_KEY:-}"
HTTPS_CERT="${KAKEIBO_HTTPS_CERT:-}"
CERT_SERVER_ENABLED="${KAKEIBO_CERT_SERVER:-0}"
CA_CERT_FILE="${KAKEIBO_CA_CERT_FILE:-}"
CERT_PORT="${KAKEIBO_CERT_PORT:-5174}"

BACKEND_PID=""
FRONTEND_PID=""
CERT_SERVER_PID=""
SCHEME="http"

if [ -n "$HTTPS_KEY" ] || [ -n "$HTTPS_CERT" ]; then
  if [ -z "$HTTPS_KEY" ] || [ -z "$HTTPS_CERT" ]; then
    echo "KAKEIBO_HTTPS_KEY と KAKEIBO_HTTPS_CERT は両方指定してください。" >&2
    exit 1
  fi
  if [ ! -r "$HTTPS_KEY" ] || [ ! -r "$HTTPS_CERT" ]; then
    echo "HTTPS証明書または秘密鍵を読み込めません。" >&2
    exit 1
  fi
  SCHEME="https"
fi

LOCAL_URL="${SCHEME}://127.0.0.1:5173/"
LAN_URL="${SCHEME}://${REQUESTED_LAN_IP}:5173/"

cleanup() {
  status=$?
  trap - EXIT INT TERM HUP

  if [ -n "$CERT_SERVER_PID" ]; then
    kill "$CERT_SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "$FRONTEND_PID" ]; then
    kill "$FRONTEND_PID" 2>/dev/null || true
  fi
  if [ -n "$BACKEND_PID" ]; then
    kill "$BACKEND_PID" 2>/dev/null || true
  fi

  if [ -n "$CERT_SERVER_PID" ]; then
    wait "$CERT_SERVER_PID" 2>/dev/null || true
  fi
  if [ -n "$FRONTEND_PID" ]; then
    wait "$FRONTEND_PID" 2>/dev/null || true
  fi
  if [ -n "$BACKEND_PID" ]; then
    wait "$BACKEND_PID" 2>/dev/null || true
  fi

  exit "$status"
}

trap cleanup EXIT INT TERM HUP

find_python() {
  if [ -x "$BACKEND_DIR/.venv/bin/python" ]; then
    printf '%s\n' "$BACKEND_DIR/.venv/bin/python"
    return 0
  fi

  for candidate in python3.13 python3.12 python3; do
    if command -v "$candidate" >/dev/null 2>&1; then
      command -v "$candidate"
      return 0
    fi
  done

  return 1
}

port_in_use() {
  port="$1"
  "$PYTHON" - "$port" <<'PY' >/dev/null 2>&1
import socket
import sys

with socket.socket() as sock:
    sock.settimeout(0.2)
    raise SystemExit(0 if sock.connect_ex(("127.0.0.1", int(sys.argv[1]))) == 0 else 1)
PY
}

fetch_url() {
  url="$1"
  case "$url" in
    https://*) curl -kfsS "$url" >/dev/null 2>&1 ;;
    *) curl -fsS "$url" >/dev/null 2>&1 ;;
  esac
}

wait_for_url() {
  label="$1"
  url="$2"
  pid="$3"
  log="$4"
  count=0

  while [ "$count" -lt 45 ]; do
    if fetch_url "$url"; then
      return 0
    fi

    if ! kill -0 "$pid" 2>/dev/null; then
      echo "$label が起動前に終了しました。" >&2
      tail -n 80 "$log" >&2 || true
      return 1
    fi

    count=$((count + 1))
    sleep 1
  done

  echo "$label の起動確認がタイムアウトしました。" >&2
  tail -n 80 "$log" >&2 || true
  return 1
}

if ! command -v npm >/dev/null 2>&1; then
  echo "npm が見つかりません。Node.js 22以降を用意してください。" >&2
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "curl が見つかりません。" >&2
  exit 1
fi

BASE_PYTHON="$(find_python || true)"
if [ -z "$BASE_PYTHON" ]; then
  echo "Python 3.10以降が見つかりません。" >&2
  exit 1
fi

"$BASE_PYTHON" - <<'PY'
import sys

if sys.version_info < (3, 10):
    raise SystemExit(f"Python 3.10以降が必要です: {sys.version.split()[0]}")
PY

if [ ! -x "$BACKEND_DIR/.venv/bin/python" ]; then
  echo "[setup] backend/.venv を作成します"
  "$BASE_PYTHON" -m venv "$BACKEND_DIR/.venv"
fi

PYTHON="$BACKEND_DIR/.venv/bin/python"

if ! "$PYTHON" -c 'import fastapi, multipart, sqlmodel, uvicorn' >/dev/null 2>&1; then
  echo "[setup] バックエンドの基本依存をインストールします"
  "$PYTHON" -m pip install \
    --disable-pip-version-check \
    -r "$BACKEND_DIR/requirements-core.txt"
fi

if [ ! -x "$FRONTEND_DIR/node_modules/.bin/vite" ]; then
  echo "[setup] フロントエンド依存をインストールします"
  (
    cd "$FRONTEND_DIR"
    npm install --no-audit --no-fund
  )
fi

if port_in_use 8000; then
  echo "TCP 8000番が既に使用中です。既存プロセスを停止してから再実行してください。" >&2
  exit 1
fi

if port_in_use 5173; then
  echo "TCP 5173番が既に使用中です。既存プロセスを停止してから再実行してください。" >&2
  exit 1
fi

if [ "$CERT_SERVER_ENABLED" = "1" ]; then
  if [ "$SCHEME" != "https" ]; then
    echo "証明書配布サーバーはHTTPS起動時だけ利用できます。" >&2
    exit 1
  fi
  if [ ! -r "$CA_CERT_FILE" ]; then
    echo "公開CA証明書を読み込めません: $CA_CERT_FILE" >&2
    exit 1
  fi
  if port_in_use "$CERT_PORT"; then
    echo "TCP ${CERT_PORT}番が既に使用中です。既存プロセスを停止してから再実行してください。" >&2
    exit 1
  fi
fi

: > "$BACKEND_LOG"
: > "$FRONTEND_LOG"
: > "$CERT_SERVER_LOG"

echo "[start] Backend: 127.0.0.1:8000"
(
  cd "$BACKEND_DIR"
  exec "$PYTHON" -m uvicorn app.main:app \
    --host 127.0.0.1 \
    --port 8000
) > "$BACKEND_LOG" 2>&1 &
BACKEND_PID=$!

wait_for_url \
  "バックエンド" \
  "http://127.0.0.1:8000/api/health" \
  "$BACKEND_PID" \
  "$BACKEND_LOG"

if [ "$CERT_SERVER_ENABLED" = "1" ]; then
  echo "[start] Certificate bootstrap: 0.0.0.0:${CERT_PORT}"
  "$PYTHON" "$ROOT_DIR/scripts/cert_server.py" \
    --cert "$CA_CERT_FILE" \
    --app-url "$LAN_URL" \
    --host 0.0.0.0 \
    --port "$CERT_PORT" \
    > "$CERT_SERVER_LOG" 2>&1 &
  CERT_SERVER_PID=$!

  wait_for_url \
    "証明書配布サーバー" \
    "http://127.0.0.1:${CERT_PORT}/health" \
    "$CERT_SERVER_PID" \
    "$CERT_SERVER_LOG"
fi

echo "[start] Frontend: ${SCHEME}://0.0.0.0:5173"
(
  cd "$FRONTEND_DIR"
  export KAKEIBO_HTTPS_KEY="$HTTPS_KEY"
  export KAKEIBO_HTTPS_CERT="$HTTPS_CERT"
  exec "$FRONTEND_DIR/node_modules/.bin/vite" \
    --host 0.0.0.0 \
    --port 5173 \
    --strictPort
) > "$FRONTEND_LOG" 2>&1 &
FRONTEND_PID=$!

wait_for_url \
  "フロントエンド" \
  "${LOCAL_URL}api/health" \
  "$FRONTEND_PID" \
  "$FRONTEND_LOG"

LAN_IPS=""
if command -v ifconfig >/dev/null 2>&1; then
  LAN_IPS="$(ifconfig 2>/dev/null | awk '$1 == "inet" && $2 !~ /^127\./ {print $2}' | sort -u || true)"
fi

cat <<EOF

起動しました。
  このMac: $LOCAL_URL
  スマホ  : $LAN_URL

停止: このターミナルで Ctrl-C
ログ:
  $BACKEND_LOG
  $FRONTEND_LOG
EOF

if [ "$CERT_SERVER_ENABLED" = "1" ]; then
  cat <<EOF

スマホの初回証明書設定:
  http://${REQUESTED_LAN_IP}:${CERT_PORT}/
証明書配布ログ:
  $CERT_SERVER_LOG
EOF
fi

if [ -n "$LAN_IPS" ]; then
  echo
  echo "検出したLAN URL:"
  printf '%s\n' "$LAN_IPS" | while IFS= read -r ip; do
    [ -n "$ip" ] && echo "  ${SCHEME}://${ip}:5173/"
  done
fi

if ! printf '%s\n' "$LAN_IPS" | grep -qx "$REQUESTED_LAN_IP"; then
  echo
  echo "注意: このMacに ${REQUESTED_LAN_IP} が現在割り当てられていません。" >&2
  echo "上の『検出したLAN URL』を使うか、MacのIP固定設定を確認してください。" >&2
fi

if [ "${KAKEIBO_NO_OPEN:-0}" != "1" ] && command -v open >/dev/null 2>&1; then
  open "$LOCAL_URL" || true
fi

while kill -0 "$BACKEND_PID" 2>/dev/null && kill -0 "$FRONTEND_PID" 2>/dev/null; do
  if [ -n "$CERT_SERVER_PID" ] && ! kill -0 "$CERT_SERVER_PID" 2>/dev/null; then
    break
  fi
  sleep 2
done

echo "バックエンド、フロントエンド、または証明書配布サーバーが終了しました。" >&2
tail -n 40 "$BACKEND_LOG" >&2 || true
tail -n 40 "$FRONTEND_LOG" >&2 || true
if [ -n "$CERT_SERVER_PID" ]; then
  tail -n 40 "$CERT_SERVER_LOG" >&2 || true
fi
exit 1
