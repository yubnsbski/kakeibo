#!/usr/bin/env bash
# 複数カテゴリ明細を含むダミーレシートを curl で投入.
#
# 使い方:
#   cd /workspaces/kakeibo && bash seed_multi_category.sh
#
# 投入後の確認:
#   - 一覧タブで3取引追加
#   - 各取引の編集で明細セクション表示
#   - ヘッダの主カテゴリが最大金額カテゴリで自動設定されている

set -euo pipefail

API=http://localhost:8000/api

# サーバー稼働確認
if ! curl -sf $API/health > /dev/null 2>&1; then
  echo "ERROR: backend not running. uvicorn を起動してください."
  exit 1
fi

create_tx() {
  local merchant="$1"
  local date="$2"
  local memo="$3"
  curl -s -X POST $API/transactions \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
print(json.dumps({
  'merchant_raw': '$merchant',
  'merchant_normalized': '$merchant',
  'items_text': '',
  'screening_category': None,
  'needs_review': False,
  'reason': 'manual',
  'confidence': 1.0,
  'amount': 0,
  'tax_amount': 0,
  'purchased_at': '$date',
  'memo': '$memo',
  'status': 'auto_saved',
}, ensure_ascii=False))
")" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])"
}

add_item() {
  local tx_id="$1"
  local name="$2"
  local amount="$3"
  local category="$4"
  local sort_order="$5"
  curl -s -X POST $API/transactions/$tx_id/items \
    -H "Content-Type: application/json" \
    -d "$(python3 -c "
import json
print(json.dumps({
  'name': '$name',
  'amount': $amount,
  'category': '$category',
  'sort_order': $sort_order,
}, ensure_ascii=False))
")" > /dev/null
}

echo "============================================================"
echo "複数カテゴリダミーデータ投入"
echo "============================================================"

# === ダミー1: イオン (酒類最大) ===
echo ""
echo "1) イオン渋谷店 (食費+酒類+日用品 混在、主=酒類)"
TX1=$(create_tx "イオン渋谷店" "2026-05-15" "週末まとめ買い")
echo "  TX_ID=$TX1"
add_item "$TX1" "牛乳" 280 "食費" 0
add_item "$TX1" "パン" 320 "食費" 1
add_item "$TX1" "ビール6缶セット" 1500 "酒類" 2
add_item "$TX1" "洗剤" 580 "日用品" 3
add_item "$TX1" "シャンプー" 780 "日用品" 4
echo "  明細5件追加"

# === ダミー2: セブンイレブン (食費最大) ===
echo ""
echo "2) セブンイレブン渋谷 (食費+酒類+日用品 混在、主=食費)"
TX2=$(create_tx "セブンイレブン渋谷" "2026-05-16" "夜の買い物")
echo "  TX_ID=$TX2"
add_item "$TX2" "おにぎり3個" 360 "食費" 0
add_item "$TX2" "弁当" 580 "食費" 1
add_item "$TX2" "缶チューハイ" 220 "酒類" 2
add_item "$TX2" "ティッシュ" 250 "日用品" 3
echo "  明細4件追加"

# === ダミー3: マツモトキヨシ (衣料費最大、4カテゴリ混在) ===
echo ""
echo "3) マツモトキヨシ新宿 (医療+日用品+食費+衣料費 4カテゴリ混在、主=衣料費)"
TX3=$(create_tx "マツモトキヨシ新宿" "2026-05-17" "風邪と買い物")
echo "  TX_ID=$TX3"
add_item "$TX3" "風邪薬" 980 "医療費" 0
add_item "$TX3" "ティッシュ" 250 "日用品" 1
add_item "$TX3" "牛乳" 280 "食費" 2
add_item "$TX3" "シャツ" 1980 "衣料費" 3
echo "  明細4件追加"

echo ""
echo "============================================================"
echo "投入完了. ヘッダ自動再計算の検証:"
echo "============================================================"

verify() {
  local tx_id="$1"
  local expected_total="$2"
  local expected_cat="$3"
  curl -s "$API/transactions/$tx_id" | python3 -c "
import sys, json
d = json.load(sys.stdin)
got_amount = d['amount']
got_cat = d['screening_category']
exp_amount = $expected_total
exp_cat = '$expected_cat'
ok = '✓' if (got_amount == exp_amount and got_cat == exp_cat) else '✗'
print(f'  {ok} TX{d[\"id\"]} [{d[\"merchant_raw\"]}] amount={got_amount} (expected {exp_amount}), category={got_cat} (expected {exp_cat})')
print(f'      明細: ' + ' / '.join(f'{it[\"name\"]} {it[\"amount\"]}円 [{it[\"category\"]}]' for it in d.get('items', [])))
"
}

verify "$TX1" 3460 "酒類"
verify "$TX2" 1410 "食費"
verify "$TX3" 3490 "衣料費"

echo ""
echo "確認URL:"
echo "  https://${CODESPACE_NAME:-localhost}-5173.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-app.github.dev}/"
echo ""
echo "一覧タブで3取引を確認 → 編集ボタンで明細セクションを開いて確認できます."
