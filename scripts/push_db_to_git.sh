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
