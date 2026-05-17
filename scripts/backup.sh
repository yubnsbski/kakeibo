#!/usr/bin/env bash
# kakeibo データのローカルスナップショット.
#
# 出力先: backups/YYYYMMDD_HHMMSS/
#   - data.db       (VACUUM INTO で整合性保証コピー)
#   - uploads.tar.gz (uploads/ 全体を圧縮、空なら未生成)
#   - manifest.json (件数・サイズ・タイムスタンプ)

set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

STAMP=$(date +%Y%m%d_%H%M%S)
DEST="backups/$STAMP"
mkdir -p "$DEST"

DB_SRC="backend/data.db"
UPLOADS_SRC="backend/uploads"

# --- 1. DB を VACUUM INTO でコピー (書込中でも安全な整合性コピー) ---
if [ -f "$DB_SRC" ]; then
  echo "[backup] copy DB -> $DEST/data.db"
  python3 -c "
import sqlite3, sys
src = sqlite3.connect('$DB_SRC')
src.execute(\"VACUUM INTO '$DEST/data.db'\")
src.close()
"
  DB_BYTES=$(stat -c%s "$DEST/data.db" 2>/dev/null || stat -f%z "$DEST/data.db")
  # 取引件数
  TX_COUNT=$(python3 -c "
import sqlite3
c = sqlite3.connect('$DEST/data.db')
try:
    n = c.execute('SELECT COUNT(*) FROM transactions').fetchone()[0]
    print(n)
except Exception:
    print(0)
")
else
  echo "[backup] WARN: $DB_SRC not found, skip DB"
  DB_BYTES=0
  TX_COUNT=0
fi

# --- 2. uploads/ を tar.gz 圧縮 ---
if [ -d "$UPLOADS_SRC" ] && [ -n "$(ls -A "$UPLOADS_SRC" 2>/dev/null)" ]; then
  echo "[backup] archive uploads -> $DEST/uploads.tar.gz"
  tar -czf "$DEST/uploads.tar.gz" -C backend uploads
  UP_BYTES=$(stat -c%s "$DEST/uploads.tar.gz" 2>/dev/null || stat -f%z "$DEST/uploads.tar.gz")
  UP_COUNT=$(ls -1 "$UPLOADS_SRC" 2>/dev/null | wc -l | tr -d ' ')
else
  echo "[backup] uploads/ is empty, skip"
  UP_BYTES=0
  UP_COUNT=0
fi

# --- 3. manifest.json ---
cat > "$DEST/manifest.json" <<JSON
{
  "stamp": "$STAMP",
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "db": {
    "bytes": $DB_BYTES,
    "transactions": $TX_COUNT
  },
  "uploads": {
    "bytes": $UP_BYTES,
    "count": $UP_COUNT
  }
}
JSON

echo ""
echo "[backup] OK: $DEST"
echo "  DB:     $TX_COUNT 件 / $DB_BYTES bytes"
echo "  uploads: $UP_COUNT 個 / $UP_BYTES bytes"
