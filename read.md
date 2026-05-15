# household-classifier 運用ガイド（可読性・保守性重視）

このドキュメントは、家計簿向けの**最小レシート分類エンジン**を安全に拡張するためのガイドです。  
対象は以下の範囲のみです。

- 店舗名正規化
- ルールベース分類
- `confidence` / `needsReview` / `reason` の返却
- ユニットテスト

> OCR / DB / UI / 外部API はこのリポジトリの責務外です。

---

## 1. ディレクトリ構成

```text
.
├─ AGENTS.md
├─ package.json
├─ src/
│  ├─ classifyReceipt.ts
│  ├─ normalizeMerchant.ts
│  ├─ rules.ts
│  └─ types.ts
└─ tests/
   └─ classifyReceipt.test.ts
```

### 役割分担

- `src/types.ts`
  - 入力/出力の型定義。仕様変更の起点。
- `src/rules.ts`
  - ルールデータ（店舗・曖昧店舗・明細キーワード）。
- `src/normalizeMerchant.ts`
  - OCRや表記揺れを正規化。
- `src/classifyReceipt.ts`
  - 判定フロー本体。
- `tests/classifyReceipt.test.ts`
  - 仕様の回帰防止。

---

## 2. 分類フロー（現在仕様）

`classifyReceipt` は次の優先順で判定します。

1. 店舗名ルール
2. 明細キーワードルール
3. 曖昧店舗判定（`needsReview=true`）
4. どれにも該当しない場合は要確認（`needsReview=true`）

この順序を変えると既存挙動が変わるため、変更時は必ずテストを先に更新してください。

---

## 3. 可読性を保つ実装ルール

### 3.1 命名

- 関数名は動詞起点（例: `normalizeMerchant`, `classifyReceipt`）
- ルール配列/辞書は用途を名前に含める（例: `itemKeywordRules`）
- 真偽値は意味が分かる形（例: `needsReview`）

### 3.2 1ファイル1責務

- 型・ルールデータ・文字列正規化・分類本体を分離する。
- 「判定ロジック」と「定数データ」を混在させない。

### 3.3 早期returnは理由を残す

- `reason` に、どのルールが当たったかを残す。
- デバッグ時に原因追跡がしやすくなる。

### 3.4 マジックナンバー管理

- `confidence` は固定値でも意味をコメント化する。
- 将来、スコア方式へ移行する際に見直しやすくする。

---

## 4. 保守性を高める変更手順

1. **先にテストを書く（または更新）**
2. `src/rules.ts` のデータ変更で済むかを確認
3. ロジック変更が必要なら `src/classifyReceipt.ts` を最小差分で変更
4. `reason` が説明可能か確認
5. 既存テスト + 追加テストを通す

---

## 5. よくある拡張パターン

### A. 新しい店舗を追加したい

- `merchantRules` に1行追加
- 想定分類のテストを1件追加

### B. 曖昧店舗を増やしたい

- `ambiguousMerchants` に追加
- 明細なしで `needsReview=true` になるテストを追加

### C. 表記ゆれを吸収したい

- `normalizeMerchant` に `replace` を追加
- 正規化後に分類成功するテストを追加

---

## 6. テスト方針

最低限、以下を維持します。

- 既知店舗が正しく分類される
- 曖昧店舗は要確認になる
- 未知店舗は要確認になる
- 正規化（全角/半角・別表記）が効く

---

## 7. 非対象（このリポジトリでやらないこと）

- OCR API接続
- DB保存
- ログイン/認証
- 画面実装
- 課金

責務を限定することで、壊れ方を追跡しやすくし、学習コストを下げます。

