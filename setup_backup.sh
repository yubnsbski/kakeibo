#!/usr/bin/env bash
# kakeibo バックアップシステムセットアップ.
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_backup.sh
#
# 作成物:
#   scripts/backup.sh         ローカルスナップショット (DB+画像)
#   scripts/restore.sh        スナップショットから復元
#   scripts/list_backups.sh   バックアップ一覧
#   scripts/push_db_to_git.sh DBのみ Git バックアップブランチへ push
#   scripts/README.md         運用手順
#   .gitignore                backups/ 追記
#   AGENTS.md                 バックアップ運用ルール追記

set -euo pipefail

REPO=/workspaces/kakeibo
cd "$REPO"

echo "==> create scripts/ directory"
mkdir -p scripts backups

# ===========================================================================
# scripts/backup.sh: ローカルスナップショット
# ===========================================================================
echo "==> write scripts/backup.sh"
cat > scripts/backup.sh <<'EOF'
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
EOF
chmod +x scripts/backup.sh

# ===========================================================================
# scripts/restore.sh: スナップショットから復元
# ===========================================================================
echo "==> write scripts/restore.sh"
cat > scripts/restore.sh <<'EOF'
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
EOF
chmod +x scripts/restore.sh

# ===========================================================================
# scripts/list_backups.sh: 一覧
# ===========================================================================
echo "==> write scripts/list_backups.sh"
cat > scripts/list_backups.sh <<'EOF'
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
EOF
chmod +x scripts/list_backups.sh

# ===========================================================================
# scripts/push_db_to_git.sh: DB のみ Git バックアップブランチへ push
# ===========================================================================
echo "==> write scripts/push_db_to_git.sh"
cat > scripts/push_db_to_git.sh <<'EOF'
#!/usr/bin/env bash
# data.db を Git の専用ブランチ backup/data へ push する.
#
# 設計:
#   - backup/data は通常の開発ブランチと分離 (orphan branch)
#   - 1コミットに 1 DB スナップショット (data.db.YYYYMMDD_HHMMSS という命名)
#   - 容量肥大化を避けるため画像は対象外
#
# 重要:
#   このスクリプトは GitHub リポジトリが *プライベート* であることを前提とする.
#   公開リポジトリで実行すると取引データが世界に公開される.
#   実行前に必ず確認プロンプトに従うこと.

set -euo pipefail

REPO=$(cd "$(dirname "$0")/.." && pwd)
cd "$REPO"

DB_SRC="backend/data.db"
if [ ! -f "$DB_SRC" ]; then
  echo "ERROR: $DB_SRC が存在しません"
  exit 1
fi

STAMP=$(date +%Y%m%d_%H%M%S)

# --- 安全確認 ---
echo "=============================================="
echo "重要: GitHub Git push バックアップ"
echo "=============================================="
echo "リポジトリ確認:"
git remote -v | head -2
echo ""
echo "このコマンドは backend/data.db (家計データ) を"
echo "Git の 'backup/data' ブランチに push します."
echo ""
echo "リポジトリがプライベートでない場合、データが世界に公開されます."
echo ""
read -p "リポジトリは *プライベート* ですか? [yes/NO]: " ans
if [ "$ans" != "yes" ]; then
  echo "中止 (明示的に 'yes' と入力してください)"
  exit 1
fi

# --- 現在ブランチ記憶 ---
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "[push] 現在ブランチ: $CURRENT_BRANCH"

# --- 一時ディレクトリで DB スナップショット作成 ---
TMP_DIR=$(mktemp -d)
trap "rm -rf $TMP_DIR" EXIT
TMP_DB="$TMP_DIR/data.db.$STAMP"
python3 -c "
import sqlite3
src = sqlite3.connect('$DB_SRC')
src.execute(\"VACUUM INTO '$TMP_DB'\")
src.close()
"
TX_COUNT=$(python3 -c "
import sqlite3
c = sqlite3.connect('$TMP_DB')
print(c.execute('SELECT COUNT(*) FROM transactions').fetchone()[0])
")
DB_BYTES=$(stat -c%s "$TMP_DB" 2>/dev/null || stat -f%z "$TMP_DB")
echo "[push] スナップショット: $TX_COUNT 件 / $DB_BYTES bytes"

# --- backup/data ブランチへ切替 (なければ orphan で新規作成) ---
if git show-ref --quiet refs/heads/backup/data; then
  git checkout backup/data
else
  echo "[push] backup/data ブランチを新規作成 (orphan)"
  git checkout --orphan backup/data
  git rm -rf . 2>/dev/null || true
  # README を 1 つだけ置く
  cat > README.md <<'README_EOF'
# backup/data branch

このブランチは kakeibo 家計簿アプリのデータバックアップ専用です.
コード変更はここに含めません.

## 内容
- `data.db.YYYYMMDD_HHMMSS`: 各時点の SQLite データベーススナップショット

## 復元
1. 任意のスナップショットファイルをダウンロード
2. ローカルで `backend/data.db` にリネームコピー
3. uvicorn を再起動
README_EOF
  git add README.md
  git commit -m "init: backup/data branch"
fi

# --- DB ファイル配置・コミット ---
cp "$TMP_DB" "data.db.$STAMP"
git add "data.db.$STAMP"
git commit -m "backup: $STAMP ($TX_COUNT txns, $DB_BYTES bytes)"

# --- push ---
echo "[push] git push origin backup/data"
git push -u origin backup/data

# --- 元ブランチに戻る ---
git checkout "$CURRENT_BRANCH"
echo "[push] 元ブランチ復帰: $CURRENT_BRANCH"

echo ""
echo "[push] 完了: backup/data ブランチに data.db.$STAMP として保存"
EOF
chmod +x scripts/push_db_to_git.sh

# ===========================================================================
# scripts/README.md: 運用手順
# ===========================================================================
echo "==> write scripts/README.md"
cat > scripts/README.md <<'EOF'
# kakeibo バックアップ運用

## 概要
3つのスクリプトでデータを保護する.

| スクリプト | 目的 | 頻度 |
|---|---|---|
| `backup.sh` | ローカルスナップショット (DB+画像) | 週次〜随時 |
| `push_db_to_git.sh` | プライベートリポジトリへDBプッシュ | 週次 |
| `restore.sh` | スナップショットから復元 | 障害発生時 |
| `list_backups.sh` | バックアップ一覧表示 | 確認時 |

## 日常運用 (推奨ペース)

### 1. 毎週: ローカルスナップショット + Git push (約30秒)
```bash
cd /workspaces/kakeibo
bash scripts/backup.sh
bash scripts/push_db_to_git.sh
```

### 2. 確認
```bash
bash scripts/list_backups.sh
git log backup/data --oneline | head -10
```

## 障害時の復元

### ケース1: data.db を間違えて削除した
```bash
bash scripts/list_backups.sh
bash scripts/restore.sh backups/<最新STAMP>
```

### ケース2: Codespaces 自体が消えた → 新しい環境から Git で復元
```bash
git clone <repo-url>
cd kakeibo
git checkout backup/data
ls data.db.*  # 最新を選ぶ
cp data.db.20260517_103000 ../data.db.recovered  # 新環境のbackend/ へ
git checkout feature/python-backend  # 元ブランチへ
cp ../data.db.recovered backend/data.db
```

## 設計の原則

- **3つの独立した保護層**: ローカルディレクトリ / Gitプライベートリポジトリ / (将来) 外付けHDDやクラウド
- **自動削除しない**: 古いバックアップは手動で削除. 容量が問題になるまで保持
- **VACUUM INTO**: SQLite の整合性保証コピー. 書き込み中でも安全
- **画像は Git に push しない**: バイナリ肥大化を避ける. 画像はローカルバックアップ層のみ
- **`backup/data` は orphan ブランチ**: 通常の開発ブランチと完全に分離

## 自宅PCデプロイ時の追加設定 (将来)

cron で日次自動バックアップ:
```cron
# 毎日 03:00 にローカルスナップショット
0 3 * * * cd /home/user/kakeibo && bash scripts/backup.sh >> /tmp/kakeibo-backup.log 2>&1

# 毎週日曜 03:30 に Git プッシュ (プロンプト自動化注意)
30 3 * * 0 cd /home/user/kakeibo && yes yes | bash scripts/push_db_to_git.sh >> /tmp/kakeibo-git.log 2>&1
```

注意: cron での `push_db_to_git.sh` 自動化は確認プロンプトを `yes yes |` で突破するので,
公開リポジトリでないことを厳重に確認してから設定すること.

## トラブルシューティング

### `VACUUM INTO` でエラー
SQLite のバージョンが古い (3.27 未満). Python 3.13 同梱版なら問題なし.

### Git push で容量警告
`data.db` が肥大化している. 不要な receipts/uploads を整理して再試行.
GitHub の警告は 1GB, 上限は実質 5GB.

### Codespaces で `git push` が認証エラー
Codespaces は GitHub 認証が自動設定済みのはず. ダメな場合:
```bash
gh auth status
gh auth login
```
EOF

# ===========================================================================
# .gitignore 更新 (backups/ 追加)
# ===========================================================================
echo "==> update .gitignore"
if [ -f .gitignore ]; then
  if ! grep -q "^backups/" .gitignore; then
    echo "" >> .gitignore
    echo "# Local backup snapshots (do not commit; managed via scripts/)" >> .gitignore
    echo "backups/" >> .gitignore
  fi
else
  cat > .gitignore <<EOF
backups/
EOF
fi

# ===========================================================================
# AGENTS.md 更新 (バックアップ運用ルール追記)
# ===========================================================================
echo "==> update AGENTS.md (backup section)"
if [ -f AGENTS.md ] && ! grep -q "## バックアップ運用" AGENTS.md; then
  cat >> AGENTS.md <<'EOF'

## バックアップ運用
3層モデル. 詳細は `scripts/README.md`.

| 層 | 対象 | 頻度 | 保管先 |
|---|---|---|---|
| L1 ローカル | data.db + uploads | 週次〜随時 | `backups/YYYYMMDD_HHMMSS/` |
| L2 Git | data.db のみ | 週次 | `backup/data` ブランチ (プライベートリポジトリ) |
| L3 外部 (将来) | L1全体 | 月次 | 外付けHDD or クラウド |

### 運用ルール
- `backup/data` ブランチは取引データのみ. コード変更は混入させない.
- 公開リポジトリでは `push_db_to_git.sh` を絶対に実行しない.
- `backups/` ディレクトリは `.gitignore` 済み. `git add backups/` 禁止.
- バックアップの自動削除は実装しない. 容量問題が出るまで全世代保持.

### 各スクリプト
- `scripts/backup.sh` ローカルスナップショット (DB + uploads)
- `scripts/push_db_to_git.sh` Gitプライベートリポジトリへ DB push
- `scripts/restore.sh` スナップショットから復元
- `scripts/list_backups.sh` 一覧表示
EOF
fi

# ===========================================================================
# 動作確認: 試行 backup を1回回す
# ===========================================================================
echo ""
echo "==> dry-run: scripts/backup.sh を1回実行"
bash scripts/backup.sh

echo ""
echo "==> dry-run: scripts/list_backups.sh"
bash scripts/list_backups.sh

# ===========================================================================
# 完了表示
# ===========================================================================
cat <<EOM

============================================================
バックアップシステムセットアップ完了.

作成物:
  scripts/backup.sh           - ローカルスナップショット (DB + 画像)
  scripts/restore.sh          - 復元
  scripts/list_backups.sh     - 一覧
  scripts/push_db_to_git.sh   - Git push (プライベートリポジトリ前提)
  scripts/README.md           - 運用手順
  .gitignore                  - backups/ 追記
  AGENTS.md                   - バックアップ運用ルール追記

日常運用:
  bash scripts/backup.sh           # 週次目安
  bash scripts/push_db_to_git.sh   # 週次目安 (確認プロンプトあり)
  bash scripts/list_backups.sh     # 確認

詳細: scripts/README.md
============================================================
EOM
