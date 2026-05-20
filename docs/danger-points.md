# Danger Points

## 分類粒度
店舗単位分類: `classifyReceipt`（既存・回帰なし）
明細単位分類: `classifyReceiptBreakdown` / `classifyItem`
- 明細単位はキーワード最長一致を採用する
- `additionalKeywordRules` で実行時にキーワード注入できる（rules.tsは書き換えない）
- 混在レシート (`isMixed=true`) は needsReview=true となり、家計簿側で按分判断する前提

## OCR
OCRは未接続。
OCR結果は誤読・改行崩れ・店舗名揺れを含む前提で扱う。

## 曖昧店舗
Amazon、楽天、イオンなどは店舗名だけで分類しない。

## Codex運用
- ファイル編集前に計画を出す
- OCR、DB、UI、外部APIは勝手に追加しない
- 依存追加前に理由を説明する
- npm run verify を通す
