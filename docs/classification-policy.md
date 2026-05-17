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
