# AGENTS.md

## 目的
家計簿アプリ向けのレシート分類エンジンだけを作る。

## 今回作るもの
- 店舗名正規化
- カテゴリ分類
- confidence算出
- needs_review判定
- unit test
- 明細キーワード自動抽出（ラベル付き学習データからの統計的マイニング）

## 今回作らないもの
- OCR
- 画像アップロード
- DB
- ログイン
- UI
- 外部API接続
- 学習済みモデルの永続化（rules.ts への自動上書きは禁止、候補出力のみ）

## 分類ルール
優先順位:
1. ユーザー修正ルール
2. 店舗名ルール
3. 明細キーワードルール
4. 曖昧店舗判定
5. 要確認

## 危険店舗
以下は店舗名だけで分類確定しない:
- Amazon
- 楽天
- イオン
- ドン・キホーテ
- メルカリ

明細がなければ needs_review=true にする。

## 禁止事項
- .envを作らない
- APIキーを扱わない
- DB migrationを作らない
- OCR APIを呼ばない
- 依存パッケージを勝手に追加しない

## テスト
npm test

## 機械学習（明細キーワード自動抽出）
- 学習データ: `fixtures/training/labeled-items.json`（明細×カテゴリのラベル付き）
- 抽出ロジック: `src/keywordMiner.ts`（純TypeScript・依存追加なし・文字n-gram統計）
- 実行: `npm run mine-keywords`（候補をstdout出力するのみ）
- `src/rules.ts` への反映は人手レビュー後に手動で行う

## Environment Rules

Before implementation:
- Read docs/classification-policy.md
- Read docs/danger-points.md
- Run npm run verify if code is changed

Do not:
- Add OCR API
- Add database
- Add authentication
- Add UI
- Add network access
- Add production dependencies without explanation

When editing:
- First explain the implementation plan
- List target files before changing them
- Keep changes limited to classifier logic, tests, fixtures, and docs
- Run npm run verify after changes
