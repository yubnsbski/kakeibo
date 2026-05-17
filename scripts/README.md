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
