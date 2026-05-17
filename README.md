# backup/data branch

このブランチは kakeibo 家計簿アプリのデータバックアップ専用です.
コード変更はここに含めません.

## 内容
- `data.db.YYYYMMDD_HHMMSS`: 各時点の SQLite データベーススナップショット

## 復元
1. 任意のスナップショットファイルをダウンロード
2. ローカルで `backend/data.db` にリネームコピー
3. uvicorn を再起動
