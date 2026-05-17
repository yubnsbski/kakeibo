# AGENTS.md

## 目的
家族共有の家計簿アプリ. レシート画像をOCR・分類エンジン経由で取引登録, 明細単位でカテゴリ管理.

## 構成 (Python一本化)
- **フロント**: React 19 + Vite + TypeScript (`frontend/`)
- **バック**: Python 3.13 + FastAPI + SQLite + SQLModel (`backend/`)
- **OCR**: Tesseract 5 + OpenCV
- **分類**: ルールベース (`backend/app/classifier/`)
- **デプロイ**: 自宅PC, uvicorn 単一プロセス
- **認証**: なし (信頼LAN前提)

## ディレクトリ (確定)
- `backend/` Python本体
- `backend/app/classifier/` 分類エンジン (rules.py がルール正書)
- `backend/app/ocr/` OCR
- `backend/app/routers/` REST API
- `backend/tests/` pytest
- `frontend/` React UI
- `docs/` 仕様書
- `fixtures/receipts/` 分類テストデータ
- `scripts/` バックアップ等
- `.github/workflows/` CI/CD

## 廃止 (Python一本化に伴う削除)
以下は **archive/ts-engine ブランチに退避済み**, ルートからは削除:
- `src/` (TS分類エンジン旧版)
- `tests/` (TS テスト)
- `package.json`, `tsconfig.json`, `node_modules/`

旧TSコードへの依存は禁止. ロジック追加・修正は **Python 側のみ**で行う.

## カテゴリ (9種, 税率付き)
食費(8%) / 酒類(10%) / 外食(10%) / 日用品(10%) / 交通費(10%) / 医療費(10%) / 娯楽費(10%) / 衣料費(10%) / その他(10%)

税率の正書: `backend/app/database.py` の `_INITIAL_CATEGORIES` + DB `category_master` テーブル.

## 分類ルール優先順位
1. ユーザー修正ルール (DB `user_category_overrides`)
2. 店舗名ルール (`backend/app/classifier/rules.py` の `merchant_rules`)
3. 明細キーワードルール (`item_keyword_rules`)
4. 曖昧店舗判定 (`ambiguous_merchants` で needs_review=true)
5. 分類不能 → needs_review=true

### 危険店舗 (明細なし時 needs_review 必須)
Amazon / 楽天 / イオン / ドンキホーテ / メルカリ

## データモデル (C4: 明細単位対応)
- `transactions` (ヘッダ: 店舗, 日付, 合計, 主カテゴリ)
- `transaction_items` (明細: 品目, 金額, カテゴリ, 税率)
- `receipts` (OCR画像メタ)
- `user_category_overrides` (ユーザー修正履歴)
- `category_master` (カテゴリ + 税率)

明細を追加した取引は, ヘッダの amount / screening_category がサーバ側で**自動再計算**される.

## CSV列契約 (`docs/operation-playbook.md` §3, 列名・順序固定)
1. receipt_id
2. merchant_normalized
3. items_text
4. screening_category
5. needs_review
6. reason
7. confidence
8. amount
9. purchased_at

DB列・API レスポンスもこの命名 (snake_case) に準拠.
変更時は `docs/` と DB マイグレーションを**同時実施**.

## バックアップ運用
- L1 ローカル: `scripts/backup.sh` で `backups/YYYYMMDD_HHMMSS/` (DB + uploads)
- L2 Git: `scripts/push_db_to_git.sh` で `backup/data` ブランチへ DB push (プライベートリポジトリ前提)
- 詳細: `scripts/README.md`

## 禁止事項
- ルート `src/`, `tests/`, `package.json` 等を**復活させない** (Python一本化方針)
- TS分類エンジンを再実装しない (ロジック追加は `backend/app/classifier/`)
- APIキーをコードに直書き
- DB スキーマ変更を Alembic / 手動マイグレーション無しに行う
- CSV列契約の列名・順序変更を docs 更新なしに行う
- OCR結果を勝手に補完する
- 依存パッケージを pyproject.toml / package.json 経由以外で追加

## CI/CD
GitHub Actions:
- `backend-ci.yml`: backend/ 変更時に pytest + ruff
- `frontend-ci.yml`: frontend/ 変更時に typecheck + lint
- `policy-guard.yml`: AGENTS.md / rules.py / models.py / database.py / pyproject.toml 変更時に `needs-human-approval` ラベル
- `automerge.yml`: `auto-merge-safe` ラベル + `needs-human-approval` 不在で自動マージ

## エージェント運用ルール
実装前:
- `AGENTS.md`, `docs/classification-policy.md`, `docs/operation-playbook.md` を読む
- 変更対象ファイルを列挙してから着手

実装後:
- backend 変更時: `cd backend && uv run pytest -v && uv run ruff check .`
- frontend 変更時: `cd frontend && npx tsc --noEmit && npm run lint`

破壊禁止:
- 既存テスト (test_classify.py, test_tax.py, test_items_api.py 等) を**期待値変更なしに**失敗させない
- DB スキーマを互換性なく変更しない (`data.db` リセットが必要な変更は docs 更新と同時)
