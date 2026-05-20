# Operation Playbook (1-page)

## 目的
- 入力品質を最重要にして、正確な出力を安定運用する。
- 誰が運用しても同じ結果になるように、手順と列定義を固定する。

## 固定フロー（最小）
1. 入力
2. 出力
3. 記録
4. 保守

---

## 1) 入力（最重要）
入力時に必ず次を満たす。
- `merchantRaw`: 店舗名の原文（省略しない）
- `items`: 分かる範囲で明細文字列を入れる（空でも可）
- `totalAmount`: 数値で入力
- `purchasedAt`: 可能なら `YYYY-MM-DD`

入力ルール:
- 原文を改変しない（正規化はエンジン側で実施）
- 店舗名・明細が不明でも空で通し、推測補完しない
- 手動補正は `userCategoryOverrides` でのみ行う

---

## 2) 出力
分類エンジンの出力は次を使う。
- `merchantNormalized`
- `category`
- `confidence`
- `reason`
- `reasons`

注記:
- `needsReview` は内部判定として保持する（仕様準拠）。
- 運用上は「入力品質を上げて review を最小化」する。

---

## 3) 記録（CSV列を契約化）
CSV列は以下で固定する（列名変更禁止）。

1. `receipt_id`
2. `merchant_normalized`
3. `items_text`
4. `screening_category`
5. `needs_review`
6. `reason`
7. `confidence`
8. `amount`
9. `purchased_at`

運用ルール:
- 列の追加・削除・順序変更はしない
- 変更が必要な場合は、先に docs 更新 + テスト更新を同時実施する

---

## 4) 保守
### k処理準拠（手動処理）
- `needs_review = yes` のレコードのみを手動確認対象とする
- 手動確定後は、`userCategoryOverrides` に反映して再処理する
- 同一パターンは必ず再利用し、都度の個別判断を減らす

### 日次ミニチェック（軽量）
- 出力件数
- review率（`needs_review=yes` の割合）

この2つだけを見る。バックアップ件数は日次チェック対象外。


---

## 5) 入力の自動化（CSVバッチ）
CSVヘッダーを次で固定する。
`receipt_id,merchantRaw,items,totalAmount,purchasedAt`

実行手順（バックエンド処理）:
1. CSVを読み込む
2. 入力チェックを通す（店舗名必須・金額>0・日付 `YYYY-MM-DD`）
3. 各行を `classifyReceipt` で分類する
4. 結果を `result.csv` として出力する

`items` 列は `|` 区切り（例: `おにぎり|牛乳`）を使う。
入力不正行は `needs_review=yes` とし、`reason` にエラーコードを入れる。
エラー表示は利用者向け文言（例: 「店舗名を入力してください」）も併記して運用する。

---

## 6) 内訳出力（混在レシート対応）
1レシート内に複数カテゴリの明細が混在する場合は、`runBreakdownClassificationFromCsvRows` を使う。

出力CSVヘッダー（固定）:
`receipt_id,merchant_normalized,category,item_texts,amount,is_mixed,purchased_at,reason`

- 1レシートはカテゴリ別に複数行に展開される（按分後）
- `is_mixed=yes` は混在検出フラグ
- per-item金額が分かる場合は `allocateAmountsByCategory` に `perItemAmounts` を渡して正確按分する（パイプライン外で利用）
- 軽減税率「軽」マーカーが取れる場合は `perItemTaxRateHints` で食費フォールバックを有効化する
