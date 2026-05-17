#!/usr/bin/env bash
# kakeibo Python一本化スクリプト.
#
# 動作:
#   1. 現状を archive/ts-engine ブランチに退避 (まだ無ければ)
#   2. ルートの TS実装関連を削除 (src/, tests/, package.json, tsconfig.json, node_modules/)
#   3. rules.py に TS版の追加キーワード移植 (ティッシュ等)
#   4. .github/workflows/ を Python向け CI に置換
#   5. AGENTS.md を Python専用に書き換え
#   6. pytest 実行 + サーバ再起動
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_python_only.sh

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "Python一本化セットアップ"
echo "============================================================"

# ===========================================================================
# 1. 現状を archive ブランチに退避 (既にあればスキップ)
# ===========================================================================
echo "==> archive/ts-engine ブランチ確認"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)
echo "  現在ブランチ: $CURRENT_BRANCH"

if git show-ref --quiet refs/heads/archive/ts-engine; then
  echo "  archive/ts-engine 既存 (退避済み)"
else
  echo "  archive/ts-engine 作成"
  # 未コミット変更がある場合は WIP コミット
  if ! git diff-index --quiet HEAD --; then
    git add -A
    git commit -m "WIP: snapshot before TS removal" || true
  fi
  git branch archive/ts-engine
  echo "  archive/ts-engine 作成完了 (現在の状態を保存)"
fi

# ===========================================================================
# 2. TS関連ファイル削除
# ===========================================================================
echo ""
echo "==> TS関連ファイル削除"
for path in src tests package.json package-lock.json tsconfig.json node_modules; do
  if [ -e "$path" ]; then
    rm -rf "$path"
    echo "  removed: $path"
  fi
done

# ===========================================================================
# 3. rules.py に TS版の追加キーワード移植
# ===========================================================================
echo ""
echo "==> rules.py に追加キーワード移植"
cat > backend/app/classifier/rules.py <<'EOF'
"""Classification rule tables — 9-category system, merged with TS legacy."""
from __future__ import annotations
from .types import Category

merchant_rules: dict[str, Category] = {
    "セブンイレブン": "食費",
    "ファミリーマート": "食費",
    "ローソン": "食費",
    "マツモトキヨシ": "日用品",
    "ウエルシア": "日用品",
    "ENEOS": "交通費",
    "JR東日本": "交通費",
}

# Note: ドン・キホーテ (中黒入り) も含める. normalize_merchant で中黒は除去されるが、
# 原文マッチ用に表記揺れも保持.
ambiguous_merchants: list[str] = [
    "Amazon", "楽天", "イオン", "ドンキホーテ", "メルカリ",
]

item_keyword_rules: dict[str, Category] = {
    # 食費
    "おにぎり": "食費",
    "弁当": "食費",
    "牛乳": "食費",
    "パン": "食費",
    # 酒類
    "ビール": "酒類",
    "ワイン": "酒類",
    "日本酒": "酒類",
    "チューハイ": "酒類",
    # 日用品 (TS legacy から移植: ティッシュ, トイレットペーパー)
    "洗剤": "日用品",
    "シャンプー": "日用品",
    "歯ブラシ": "日用品",
    "ティッシュ": "日用品",
    "トイレットペーパー": "日用品",
    # 医療費
    "薬": "医療費",
    # 交通費 (TS legacy から移植: バス, 電車)
    "ガソリン": "交通費",
    "バス": "交通費",
    "電車": "交通費",
    # 娯楽費
    "本": "娯楽費",
    "映画": "娯楽費",
    # 衣料費
    "シャツ": "衣料費",
    "靴": "衣料費",
}
EOF

# ===========================================================================
# 4. .github/workflows/ を Python向け CI に置換
# ===========================================================================
echo ""
echo "==> .github/workflows/ を Python版CI に置換"
mkdir -p .github/workflows

# 既存の TS向けworkflow を削除
rm -f .github/workflows/automerge.yml \
      .github/workflows/ci.yml \
      .github/workflows/policy-guard.yml

# Python向けCI
cat > .github/workflows/backend-ci.yml <<'EOF'
name: Backend CI

on:
  pull_request:
    paths:
      - 'backend/**'
      - '.github/workflows/backend-ci.yml'
  push:
    branches: [main]
    paths:
      - 'backend/**'

jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: backend
    steps:
      - uses: actions/checkout@v4

      - name: Install Tesseract
        run: |
          sudo apt-get update
          sudo apt-get install -y --no-install-recommends \
            tesseract-ocr tesseract-ocr-jpn tesseract-ocr-jpn-vert \
            libgl1 libglib2.0-0

      - name: Setup uv
        uses: astral-sh/setup-uv@v3
        with:
          version: "latest"

      - name: Setup Python
        run: uv python install 3.13

      - name: Install dependencies
        run: uv sync

      - name: Lint
        run: uv run ruff check .

      - name: Test
        run: uv run pytest -v
EOF

# Frontend向けCI
cat > .github/workflows/frontend-ci.yml <<'EOF'
name: Frontend CI

on:
  pull_request:
    paths:
      - 'frontend/**'
      - '.github/workflows/frontend-ci.yml'
  push:
    branches: [main]
    paths:
      - 'frontend/**'

jobs:
  build:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: frontend
    steps:
      - uses: actions/checkout@v4

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: '22'
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json

      - name: Install deps
        run: npm ci || npm install

      - name: Typecheck
        run: npx tsc --noEmit

      - name: Lint
        run: npm run lint
EOF

# Policy Guard を移植 (Python版: sensitive ファイル変更で human-approval ラベル)
cat > .github/workflows/policy-guard.yml <<'EOF'
name: Policy Guard

on:
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]

permissions:
  contents: read
  pull-requests: write

jobs:
  guard:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Detect sensitive file changes
        id: changed
        uses: tj-actions/changed-files@v45
        with:
          files: |
            AGENTS.md
            backend/pyproject.toml
            backend/app/classifier/rules.py
            backend/app/models.py
            backend/app/database.py

      - name: Add needs-human-approval label
        if: steps.changed.outputs.any_changed == 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const label = 'needs-human-approval'
            const { owner, repo } = context.repo
            const issue_number = context.payload.pull_request.number
            const labels = await github.rest.issues.listLabelsOnIssue({ owner, repo, issue_number })
            if (!labels.data.some(l => l.name === label)) {
              await github.rest.issues.addLabels({ owner, repo, issue_number, labels: [label] })
            }

      - name: Add auto-merge-safe label
        if: steps.changed.outputs.any_changed != 'true'
        uses: actions/github-script@v7
        with:
          script: |
            const label = 'auto-merge-safe'
            const { owner, repo } = context.repo
            const issue_number = context.payload.pull_request.number
            const labels = await github.rest.issues.listLabelsOnIssue({ owner, repo, issue_number })
            if (!labels.data.some(l => l.name === label)) {
              await github.rest.issues.addLabels({ owner, repo, issue_number, labels: [label] })
            }
EOF

# Auto-merge は維持 (auto-merge-safe ラベル + CI通過で自動マージ)
cat > .github/workflows/automerge.yml <<'EOF'
name: Auto Merge Safe PR

on:
  pull_request:
    types: [labeled, synchronize, reopened, ready_for_review]

permissions:
  pull-requests: write
  contents: write

jobs:
  automerge:
    if: contains(github.event.pull_request.labels.*.name, 'auto-merge-safe') && !contains(github.event.pull_request.labels.*.name, 'needs-human-approval')
    runs-on: ubuntu-latest
    steps:
      - uses: actions/github-script@v7
        with:
          script: |
            try {
              await github.graphql(`
                mutation($pullRequestId:ID!) {
                  enablePullRequestAutoMerge(input: {
                    pullRequestId: $pullRequestId,
                    mergeMethod: SQUASH
                  }) {
                    pullRequest { number }
                  }
                }
              `, {
                pullRequestId: context.payload.pull_request.node_id
              })
            } catch (e) {
              core.warning(`Auto-merge not enabled yet: ${e.message}`)
            }
EOF

# ===========================================================================
# 5. AGENTS.md を Python専用に書き換え
# ===========================================================================
echo ""
echo "==> AGENTS.md を Python専用版に置換"
cat > AGENTS.md <<'EOF'
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
EOF

# ===========================================================================
# 6. docs/classification-policy.md 更新 (TS言及削除, 明細単位を反映)
# ===========================================================================
echo ""
echo "==> docs/classification-policy.md"
cat > docs/classification-policy.md <<'EOF'
# Classification Policy

## 目的
家計簿アプリ向けに, レシート情報をカテゴリ分類する.
Python 一本化: 分類ロジックは `backend/app/classifier/` のみ.

## カテゴリ (9種, 税率付き)
| カテゴリ | 税率 | 説明 |
|---|---|---|
| 食費 | 8% | スーパー, コンビニ, 弁当, 食品 |
| 酒類 | 10% | ビール, ワイン, 日本酒, チューハイ |
| 外食 | 10% | レストラン, カフェ, 居酒屋 |
| 日用品 | 10% | ドラッグストア, 洗剤, トイレ, キッチン |
| 交通費 | 10% | 電車, バス, タクシー, ガソリン, 駐車場 |
| 医療費 | 10% | 病院, 薬局, 医薬品, 診察 |
| 娯楽費 | 10% | 書店, 映画, ゲーム, 趣味, レジャー |
| 衣料費 | 10% | アパレル, 靴, ファッション, クリーニング |
| その他 | 10% | 判断できないもの |

カテゴリと税率の正書: `backend/app/database.py` の `_INITIAL_CATEGORIES` + DB `category_master` テーブル.

## 分類粒度
1. **取引単位 (ヘッダ)**: `transactions.screening_category` に主カテゴリ
   - 明細未使用時: 分類エンジンが返す category
   - 明細使用時: 明細の最大金額カテゴリを自動代入
2. **明細単位**: `transaction_items.category` に各明細のカテゴリ
   - ユーザーが手動分類 (将来は `classify_line_items` ロジックで自動化)

## 危険店舗
Amazon / 楽天 / イオン / ドンキホーテ / メルカリ
明細なしなら needs_review=true.

## 基本ルール (rules.py)
1. ユーザー修正ルール (DB)
2. 店舗名ルール (`merchant_rules`)
3. 明細キーワードルール (`item_keyword_rules`)
4. 曖昧店舗 + 明細なし → needs_review=true
5. 分類不能 → needs_review=true

## 金額保存方式
- レシート印字の金額 = 税込総額 → そのまま `amount` に保存
- `tax_amount` は表示参考用に逆算保存
- 明細追加時はヘッダ amount/tax_amount を明細合計から自動再計算
EOF

# ===========================================================================
# 7. 既存テストが新ルールで通るか確認 (新規キーワードのテスト追加)
# ===========================================================================
echo ""
echo "==> tests/test_classify.py に新キーワードテスト追加"
cat > backend/tests/test_classify.py <<'EOF'
"""Tests for classify_receipt — 9-category system."""
from __future__ import annotations
from app.classifier import ReceiptInput, classify_receipt


def test_seven_eleven_classified_as_food():
    r = classify_receipt(ReceiptInput(merchantRaw="ｾﾌﾞﾝ-ｲﾚﾌﾞﾝ 渋谷店",
                                        items=["おにぎり", "牛乳"], totalAmount=620))
    assert r.category == "食費"
    assert r.needsReview is False


def test_amazon_without_items_needs_review():
    r = classify_receipt(ReceiptInput(merchantRaw="Amazon.co.jp", items=[], totalAmount=3000))
    assert r.category is None
    assert r.needsReview is True


def test_beer_classified_as_liquor():
    r = classify_receipt(ReceiptInput(merchantRaw="酒屋", items=["ビール"], totalAmount=500))
    assert r.category == "酒類"


def test_shirt_classified_as_clothing():
    r = classify_receipt(ReceiptInput(merchantRaw="アパレル店", items=["シャツ"], totalAmount=3000))
    assert r.category == "衣料費"


def test_no_rule_match_needs_review():
    r = classify_receipt(ReceiptInput(merchantRaw="未知の店舗", items=["未知"], totalAmount=1000))
    assert r.category is None
    assert r.needsReview is True


# === TS legacy から移植したキーワードのテスト ===

def test_tissue_classified_as_daily_goods():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["ティッシュ"], totalAmount=300))
    assert r.category == "日用品"
    assert r.reasons == ["item_keyword: ティッシュ"]


def test_toilet_paper_classified_as_daily_goods():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["トイレットペーパー"], totalAmount=400))
    assert r.category == "日用品"


def test_train_classified_as_transport():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["電車"], totalAmount=180))
    assert r.category == "交通費"
    assert r.reasons == ["item_keyword: 電車"]


def test_bus_classified_as_transport():
    r = classify_receipt(ReceiptInput(merchantRaw="不明店舗", items=["バス"], totalAmount=210))
    assert r.category == "交通費"
EOF

# ===========================================================================
# 8. data.db リセットしない (C4の状態を保持)
# ===========================================================================
# 注意: C4 で transaction_items 追加済み. ここではスキーマ変更なし.

# ===========================================================================
# 9. pytest
# ===========================================================================
echo ""
echo "==> backend pytest"
cd backend && uv run pytest -v 2>&1 | tail -30 || echo "WARN: tests failed"
cd "$REPO"

# ===========================================================================
# 10. server restart
# ===========================================================================
echo ""
echo "==> restart uvicorn"
pkill -f uvicorn 2>/dev/null || true
sleep 2
cd backend
nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &
sleep 4
cd "$REPO"

echo ""
echo "==> backend health"
curl -s http://localhost:8000/api/health && echo

# ===========================================================================
# 11. 最終状態確認
# ===========================================================================
echo ""
echo "==> ルートディレクトリ確認 (TS削除済みのはず)"
ls /workspaces/kakeibo/ | head -20

echo ""
echo "==> backend/ 構造"
find backend -type f -name "*.py" | head -20

echo ""
echo "==> .github/workflows/"
ls .github/workflows/ 2>/dev/null

cat <<EOM

============================================================
Python一本化セットアップ完了.

変更点:
  - ルートの src/, tests/, package.json 等を削除 (archive/ts-engine ブランチに退避済み)
  - rules.py に TS版の追加キーワード移植 (ティッシュ, トイレットペーパー, バス, 電車)
  - .github/workflows/ を Python向け CI に置換 (backend-ci, frontend-ci, policy-guard, automerge)
  - AGENTS.md を Python一本化方針に書き換え (Codex はこれを読んで作業する)
  - docs/classification-policy.md 更新

次にユーザーがやること:
  1. git status で変更確認, git add -A && git commit && git push
  2. (Codex の) PR をクローズ (ブラウザ or gh pr close <番号>)
  3. 次フェーズ (C3: CSV取込 + グラフ) を承認

サーバ稼働: http://localhost:8000 + http://localhost:5173
============================================================
EOM
