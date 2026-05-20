# kakeibo (Python implementation)

TypeScript版と同等のレシート分類エンジンをPure Python (stdlib only) で実装。
**明細レベル精度 100% (22/22)** を達成。

## 構成

```
python/
├── kakeibo/
│   ├── normalize_merchant.py   # 店舗名正規化
│   ├── rules.py                # 店舗 + 明細キーワード (拡張seed lexicon含む)
│   ├── classify_item.py        # 単一明細分類 + 税率ヒント
│   ├── classify_receipt.py     # 店舗単位分類
│   ├── classify_breakdown.py   # レシート明細分解 + isMixed判定
│   ├── allocate_amounts.py     # カテゴリ別金額按分
│   ├── keyword_miner.py        # 文字n-gram統計マイニング
│   ├── evaluate.py             # 評価ハーネス
│   ├── feedback.py             # 学習データ取り込み
│   └── cli.py                  # argparse CLI
├── tests/                       # unittest (stdlib only)
└── fixtures/  → symlink to ../fixtures
```

## 依存

- Python 3.10+
- 追加ライブラリなし（pure stdlib）

## テスト

```bash
cd python
python3 -m unittest discover -s tests
```

26テスト。`test_evaluate.ItemAccuracyTests.test_baseline_accuracy_meets_90_percent`
が **accuracy >= 90% を強制**する。

## CLI

```bash
cd python

# 明細キーワード候補を抽出
python3 -m kakeibo.cli mine-keywords

# 精度評価レポート (baseline vs mined)
python3 -m kakeibo.cli evaluate
```

## TS実装との関係

- 仕様は1:1対応（同じJSON fixturesを `python/fixtures` symlink で共有）
- Python版は `rules.py` に追加の seed lexicon（ミルク、茶、ペットボトル、
  歯ブラシ、ペーパー、書籍、雑誌）を持ち、TS版より精度が高い
- TS実装は触らない（既存ユーザーへの破壊変更なし）
