# AGENTS.md

## 目的
家計簿アプリ向けのレシート分類エンジンだけを作る。

## 今回作るもの
- 店舗名正規化
- カテゴリ分類
- confidence算出
- needs_review判定
- unit test

## 今回作らないもの
- OCR
- 画像アップロード
- DB
- ログイン
- UI
- 外部API接続

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
明細がある場合は、店舗名ルール/明細キーワードルールで分類してよい。

## 禁止事項
- .envを作らない
- APIキーを扱わない
- DB migrationを作らない
- OCR APIを呼ばない
- 依存パッケージを勝手に追加しない

## テスト
npm test

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
