#!/usr/bin/env bash
# 指定スナップショットから復元.
#
# 使い方:
#   bash scripts/restore.sh backups/20260517_103000
#
# 動作:
#   1. backend/data.db を上書き (確認プロンプト)
#   2. uploads.tar.gz があれば backend/uploads/ に展開
#   3. 現在の data.db は backend/data.db.before-restore-* として退避

set -euo pipefail

if [ $# -lt 1 ]; then
  echo "Usage: $0 <backup-dir>"
  echo "Example: $0 backups/20260517_103000"
  exit 1
fi

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

SRC="$1"
if [ ! -d "$SRC" ]; then
  echo "ERROR: $SRC not found"
  exit 1
fi
if [ ! -f "$SRC/data.db" ]; then
  echo "ERROR: $SRC/data.db not found"
  exit 1
fi

echo "復元元: $SRC"
if [ -f "$SRC/manifest.json" ]; then
  echo "--- manifest ---"
  cat "$SRC/manifest.json"
  echo
fi

echo ""
read -p "現在の backend/data.db を上書きします。続行しますか? [y/N]: " ans
case "$ans" in
  [yY]|[yY][eE][sS]) ;;
  *) echo "中止"; exit 1 ;;
esac

# 現在の DB を退避
if [ -f backend/data.db ]; then
  BAK="backend/data.db.before-restore-$(date +%Y%m%d_%H%M%S)"
  cp backend/data.db "$BAK"
  echo "[restore] 既存DB退避: $BAK"
fi

# 復元
cp "$SRC/data.db" backend/data.db
echo "[restore] DB復元: $SRC/data.db -> backend/data.db"

if [ -f "$SRC/uploads.tar.gz" ]; then
  read -p "uploads/ も復元しますか? [y/N]: " ans2
  case "$ans2" in
    [yY]|[yY][eE][sS])
      # 既存 uploads/ を退避
      if [ -d backend/uploads ] && [ -n "$(ls -A backend/uploads 2>/dev/null)" ]; then
        mv backend/uploads "backend/uploads.before-restore-$(date +%Y%m%d_%H%M%S)"
      fi
      mkdir -p backend
      tar -xzf "$SRC/uploads.tar.gz" -C backend
      echo "[restore] uploads/ 復元完了"
      ;;
    *)
      echo "[restore] uploads/ はスキップ"
      ;;
  esac
fi

echo ""
echo "[restore] 完了"
echo "サーバ稼働中の場合は再起動を推奨:"
echo "  pkill -f uvicorn && cd backend && uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 &"
