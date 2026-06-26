# データ保存・復元

## 保存先

既定のSQLite保存先は、リポジトリの外にある次のパスです。

```text
~/.kakeibo/data.db
```

`git pull`、ブランチ切替、リポジトリの再cloneでこのファイルは変更されません。

初回起動時に現在のclone内に `backend/data.db` があり、安定保存先がまだ存在しない場合は、SQLiteのバックアップAPIで自動コピーします。既存の安定保存先は自動上書きしません。

## 現在の状態

アプリを停止してから実行します。

```bash
bash scripts/data_manager.sh status
```

## 旧DB候補を探す

```bash
bash scripts/data_manager.sh scan
```

取引件数、暗号設定件数、更新日時、パスだけを表示します。saltや暗号文の中身は表示しません。

## バックアップ

```bash
bash scripts/data_manager.sh backup
```

バックアップ先:

```text
~/.kakeibo/backups/
```

## 旧DBを復元

アプリを `Ctrl-C` で停止してから、scanで見つけたパスを指定します。

```bash
bash scripts/data_manager.sh restore "/旧clone/backend/data.db"
```

復元前の現在DBは自動でバックアップされます。復元元は変更しません。復元後は、旧データで使用していたパスフレーズが必要です。

## 禁止事項

- `encrypted_transactions` テーブルだけをコピーしない
- `app_crypto_config` のsaltだけを作り直さない
- 異なるsaltのDBを単純結合しない
- アプリ起動中にDBファイルをFinderや `cp` で上書きしない

暗号化取引と鍵導出設定は同じDB全体として移動する必要があります。

## 明示的な保存先

必要な場合だけ環境変数で変更できます。

```bash
KAKEIBO_DB_PATH="/absolute/path/data.db" bash scripts/start.sh
```

または:

```bash
KAKEIBO_DATA_DIR="/absolute/directory" bash scripts/start.sh
```
