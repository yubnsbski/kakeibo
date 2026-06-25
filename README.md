# kakeibo

ブラウザ側で取引を暗号化して保存する家計簿アプリです。React/Viteフロントエンド、FastAPI/SQLiteバックエンド、TypeScript/Python分類エンジンで構成されています。

## 主な機能

- レシートOCRプレビューと確認後の暗号化保存
- レシートなし手入力
- カテゴリ、値段、税率、税額の表示・編集
- 値段欄の加減乗除と括弧計算
- 日・月・年ごとのカテゴリ別合計
- 収入、支出、収支の集計
- ブラウザ内の暗号化・復号

## 重要な設計

- 取引JSONはブラウザで暗号化され、サーバーは暗号文だけを保存します。
- パスフレーズを失うと既存取引は復号できません。
- 金額式は制限付きバックエンドパーサで計算し、`eval` は使用しません。
- 演算APIへ送るのは金額式と税率だけです。
- OCR previewは画像をバックエンドへ送りますが、画像・OCR文字列・平文取引をDB保存しません。

詳細な制約は `AGENTS.md` と `docs/danger-points.md` を参照してください。

## 前提

- Git
- Node.js 22以降
- Python 3.12以降
- Bashを使えるLinuxまたはmacOS
- WindowsではWSL上での実行を推奨

Tesseract OCRを使う場合は、Pythonパッケージとは別にTesseract本体と日本語データが必要です。

### Debian / Ubuntu

```bash
sudo apt-get update
sudo apt-get install -y tesseract-ocr tesseract-ocr-jpn
```

### macOS Homebrew

```bash
brew install tesseract tesseract-lang
```

## 初回セットアップ

以下をターミナルへ貼り付けます。

```bash
set -euo pipefail
mkdir -p "$HOME/src"
cd "$HOME/src"
git clone https://github.com/yubnsbski/kakeibo.git
cd kakeibo
bash scripts/setup_local.sh
```

セットアップは次を行います。

- `backend/.venv` の作成
- 固定済みPython依存関係のインストール
- ルートとフロントエンドの `npm ci`
- TypeScriptテスト、フロントビルド、全バックエンドテスト、FastAPI import確認

## 起動

```bash
cd "$HOME/src/kakeibo"
bash scripts/start.sh
```

- フロントエンド: `http://127.0.0.1:5173`
- バックエンド: `http://127.0.0.1:8000`
- 停止: 起動中のターミナルで `Ctrl-C`

起動スクリプトは既存プロセスを強制終了せず、このリポジトリから起動した2プロセスだけを停止します。

## mainの更新をローカルへ反映

未コミット変更がない状態で実行します。

```bash
cd "$HOME/src/kakeibo"
bash scripts/sync_local.sh
```

このスクリプトは次を安全側で実行します。

1. 未コミット変更があれば停止
2. `origin` をfetch
3. `main` へ切替
4. `git pull --ff-only origin main`
5. 依存関係の再現と全検証

変更がある場合は自動stash・reset・cleanを行いません。先にcommitまたは手動stashしてください。

```bash
git status --short
git stash push --include-untracked -m "before kakeibo sync"
bash scripts/sync_local.sh
```

## Gemini OCRを有効にする場合

通常セットアップでは外部AI SDKを入れません。必要な場合だけ実行します。

```bash
cd "$HOME/src/kakeibo"
bash scripts/setup_local.sh --with-gemini
```

`backend/.env` がなければテンプレートから作成されます。実キーはローカルで設定し、Gitへ追加しないでください。

```text
GEMINI_API_KEY=ここにローカルのキーを設定
```

キー未設定またはGemini失敗時はTesseractへフォールバックします。

## 値段式

利用可能な例:

```text
1000 + 250
(1200 + 300) / 2
（１００＋５０）×２
```

利用不可:

- 累乗
- 指数表記
- 変数や関数
- 任意コード
- 0除算

計算結果は1円以上の有限値である必要があります。

## 手動検証

```bash
cd "$HOME/src/kakeibo"
bash scripts/verify_local.sh
```

CIも同じ境界を確認します。

- ルートTypeScript型検査とテスト
- フロントエンド本番ビルド
- Python 3.12上の全バックエンドテスト
- FastAPIアプリ全体のimport

## AI利用制限前の引継ぎ

作業中の状態をChatGPTなどの別会話へ渡す前に実行します。

```bash
cd "$HOME/src/kakeibo"
bash scripts/verify_local.sh
bash scripts/create_handoff.sh
```

生成される `AI_HANDOFF.local.md` に、次の依頼・受入条件・検証結果・未解決事項を追記してから内容を確認し、新しい会話へ貼り付けます。

生成物には環境変数、秘密鍵、ファイル本文、差分本文を含めません。ただしブランチ名、コミットメッセージ、変更ファイル名は含みます。

再利用する小スプリント手順は `.claude/skills/kakeibo-small-sprint/SKILL.md` にあります。

## ローカルデータ

- SQLite: `backend/data.db`
- OCR一時領域: `backend/uploads/`
- APIキー: `backend/.env`

これらはGit管理外です。DBモデル変更前はバックアップしてください。

```bash
cd "$HOME/src/kakeibo"
test ! -f backend/data.db || cp backend/data.db "backend/data.db.bak.$(date +%Y%m%d-%H%M%S)"
```
