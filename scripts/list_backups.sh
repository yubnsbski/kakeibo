#!/usr/bin/env bash
# バックアップ一覧表示.

set -euo pipefail
REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

if [ ! -d backups ] || [ -z "$(ls -A backups 2>/dev/null)" ]; then
  echo "(バックアップなし)"
  exit 0
fi

printf "%-22s %-10s %-12s %-12s\n" "STAMP" "TXNS" "DB_BYTES" "UP_BYTES"
printf "%-22s %-10s %-12s %-12s\n" "----------------------" "----------" "------------" "------------"
for d in backups/*/; do
  stamp=$(basename "$d")
  if [ -f "$d/manifest.json" ]; then
    tx=$(python3 -c "import json; print(json.load(open('$d/manifest.json'))['db']['transactions'])" 2>/dev/null || echo "?")
    db_bytes=$(python3 -c "import json; print(json.load(open('$d/manifest.json'))['db']['bytes'])" 2>/dev/null || echo "?")
    up_bytes=$(python3 -c "import json; print(json.load(open('$d/manifest.json'))['uploads']['bytes'])" 2>/dev/null || echo "?")
  else
    tx="?"; db_bytes="?"; up_bytes="?"
  fi
  printf "%-22s %-10s %-12s %-12s\n" "$stamp" "$tx" "$db_bytes" "$up_bytes"
done

echo ""
echo "復元: bash scripts/restore.sh backups/<STAMP>"
echo "削除: rm -rf backups/<STAMP>"
