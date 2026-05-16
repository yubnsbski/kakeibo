# Next Task

## 次に実装するもの
分類ロジックをスコア方式に変更する。

## 目的
単純な最初一致ではなく、複数の根拠を使ってカテゴリ候補を評価する。

## 実装対象
- カテゴリごとの score
- reasons 配列
- score差が小さい場合の needsReview=true
- ambiguous merchant の単独確定禁止
- fixture を使ったテスト

## 実装しないもの
- OCR API
- DB
- UI
- 画像処理
- 外部API

## 出力例
{
  "merchantNormalized": "セブンイレブン渋谷店",
  "category": "食費",
  "confidence": 0.86,
  "needsReview": false,
  "reasons": [
    "merchant_rule: セブンイレブン",
    "item_keyword: おにぎり"
  ],
  "scores": [
    {
      "category": "食費",
      "score": 130
    }
  ]
}
