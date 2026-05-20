# Keyword Mining (明細キーワード自動抽出)

## 目的
ラベル付きレシート明細データから、カテゴリ特異的なキーワード候補を統計的に抽出し、`src/rules.ts` の `itemKeywordRules` 拡張に役立てる。

## 非対象
- `rules.ts` への自動上書きはしない（候補出力のみ）
- 形態素解析・外部API・モデル永続化はしない
- 依存パッケージは追加しない

## アルゴリズム
1. 各明細テキストから文字n-gram（既定: 2〜3字）を抽出
2. n-gramごとにカテゴリ別出現数を集計
3. 各n-gramの最頻カテゴリを採用カテゴリとし、以下を算出:
   - `support`: 採用カテゴリ内での出現数
   - `purity`: support / 全カテゴリ合計出現数
   - `score`: support × purity
4. `minSupport` と `minPurity` の閾値でフィルタ
5. 長いn-gramに包含される短いn-gram（同カテゴリ・support同等以下）は冗長として除去
6. score降順で出力

## 使い方

### 学習データの追加
`fixtures/training/labeled-items.json` に明細とカテゴリを追記する。

```json
{
  "source": "店舗名_日付",
  "items": [
    { "text": "雑誌書籍", "category": "教育" },
    { "text": "ミルク", "category": "食費" }
  ]
}
```

### 候補の出力
```bash
npm run mine-keywords
```

vitest経由で `tests/mineKeywordsReport.test.ts` を実行し、stdoutに `keyword / category / support / purity / score` のTSVを出力する（通常の `npm test` ではスキップされる）。

### rules.tsへの反映
出力を目視レビューし、妥当なものだけ `src/rules.ts` の `itemKeywordRules` に手動で追記する。追記後は必ず:
```bash
npm run verify
```
を通す。

## 運用上の注意
- 学習データは原文を改変せず、明細ごとにラベルを付ける
- 1レシートに複数カテゴリの明細が混在しても良い（例: FamilyMartの「ミルク=食費」「雑誌書籍=教育」）
- ノイズが多い場合は `minSupport` / `minPurity` を上げる
- 危険店舗（Amazon等）の明細にも有効だが、ルール反映時は曖昧店舗判定の挙動を壊さないこと
