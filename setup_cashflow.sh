#!/usr/bin/env bash
# キャッシュフロー可視化拡張: 3つの新グラフ + 大口取引ランキング.
#
# 追加機能:
#   - 月別カテゴリ積み上げ棒グラフ (過去6ヶ月)
#   - 日次累積支出 折れ線グラフ (今月+先月オーバーレイ)
#   - 大口支出 TOP10 (今月)
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_cashflow.sh

set -euo pipefail
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "キャッシュフロー可視化拡張"
echo "============================================================"

# ===========================================================================
# 1. backend/app/routers/summary.py に新エンドポイント追加
# ===========================================================================
echo "==> backend/app/routers/summary.py (3エンドポイント追加)"
cat > backend/app/routers/summary.py <<'EOF'
"""Summary API — extended for cashflow visualization."""
from __future__ import annotations

from collections import defaultdict
from datetime import date, timedelta
from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlmodel import Session, select

from app.database import get_session
from app.models import Transaction, TransactionItem

router = APIRouter(prefix="/api/summary", tags=["summary"])


# ===== Models =====

class CategorySliceItem(BaseModel):
    category: str
    amount: int


class CategorySummary(BaseModel):
    ym: str
    total: int
    slices: list[CategorySliceItem]


class MonthlySliceItem(BaseModel):
    ym: str
    total: int


class MonthlySummary(BaseModel):
    months: int
    slices: list[MonthlySliceItem]


class MonthlyByCategoryRow(BaseModel):
    """月×カテゴリ合計 (積み上げ棒用)."""
    ym: str
    by_category: dict[str, int]  # {"食費": 12000, ...}
    total: int


class MonthlyByCategoryResponse(BaseModel):
    months: int
    categories: list[str]  # 表示順
    rows: list[MonthlyByCategoryRow]


class DailyCumulativePoint(BaseModel):
    date: str  # YYYY-MM-DD
    cumulative: int


class DailyCumulativeResponse(BaseModel):
    ym: str
    points: list[DailyCumulativePoint]
    total: int


class TopTransactionItem(BaseModel):
    id: int
    purchased_at: str
    merchant: str
    category: str | None
    amount: int


class TopTransactionsResponse(BaseModel):
    ym: str
    limit: int
    items: list[TopTransactionItem]


# ===== Helpers =====

CATEGORY_ORDER = [
    "食費", "酒類", "外食", "日用品",
    "交通費", "医療費", "娯楽費", "衣料費", "その他",
]


def _month_range(ym: str) -> tuple[date, date]:
    y, m = ym.split("-")
    y_i, m_i = int(y), int(m)
    start = date(y_i, m_i, 1)
    if m_i == 12:
        end = date(y_i + 1, 1, 1)
    else:
        end = date(y_i, m_i + 1, 1)
    return start, end


def _generate_yms(months: int) -> list[str]:
    today = date.today()
    y, m = today.year, today.month
    yms: list[str] = []
    for _ in range(months):
        yms.append(f"{y:04d}-{m:02d}")
        m -= 1
        if m == 0:
            m = 12
            y -= 1
    yms.reverse()
    return yms


def _aggregate_by_category(
    session: Session, start: date, end: date,
) -> dict[str, int]:
    """期間内のカテゴリ別合計."""
    by_cat: dict[str, int] = defaultdict(int)
    tx_stmt = select(
        Transaction.id, Transaction.screening_category, Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
    )
    tx_rows = list(session.exec(tx_stmt).all())

    items_by_tx: dict[int, list[TransactionItem]] = defaultdict(list)
    if tx_rows:
        tx_ids = [row[0] for row in tx_rows]
        item_stmt = select(TransactionItem).where(
            TransactionItem.transaction_id.in_(tx_ids)  # type: ignore
        )
        for item in session.exec(item_stmt).all():
            items_by_tx[item.transaction_id].append(item)

    for tx_id, screening_category, amount in tx_rows:
        items = items_by_tx.get(tx_id, [])
        if items:
            for item in items:
                if item.category:
                    by_cat[item.category] += item.amount
        else:
            if screening_category:
                by_cat[screening_category] += amount
    return dict(by_cat)


# ===== Endpoints =====

@router.get("/category", response_model=CategorySummary)
def category_summary(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> CategorySummary:
    start, end = _month_range(ym)
    by_cat = _aggregate_by_category(session, start, end)
    slices = sorted(
        [CategorySliceItem(category=c, amount=a) for c, a in by_cat.items()],
        key=lambda x: -x.amount,
    )
    return CategorySummary(ym=ym, total=sum(s.amount for s in slices), slices=slices)


@router.get("/monthly", response_model=MonthlySummary)
def monthly_summary(
    months: int = Query(6, ge=1, le=24),
    session: Session = Depends(get_session),
) -> MonthlySummary:
    yms = _generate_yms(months)
    slices: list[MonthlySliceItem] = []
    for ym in yms:
        start, end = _month_range(ym)
        by_cat = _aggregate_by_category(session, start, end)
        slices.append(MonthlySliceItem(ym=ym, total=sum(by_cat.values())))
    return MonthlySummary(months=months, slices=slices)


@router.get("/monthly_by_category", response_model=MonthlyByCategoryResponse)
def monthly_by_category(
    months: int = Query(6, ge=1, le=24),
    session: Session = Depends(get_session),
) -> MonthlyByCategoryResponse:
    """月×カテゴリのマトリクス (積み上げ棒グラフ用)."""
    yms = _generate_yms(months)
    rows: list[MonthlyByCategoryRow] = []
    for ym in yms:
        start, end = _month_range(ym)
        by_cat = _aggregate_by_category(session, start, end)
        rows.append(MonthlyByCategoryRow(
            ym=ym, by_category=by_cat, total=sum(by_cat.values()),
        ))
    return MonthlyByCategoryResponse(
        months=months, categories=CATEGORY_ORDER, rows=rows,
    )


@router.get("/daily_cumulative", response_model=DailyCumulativeResponse)
def daily_cumulative(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    session: Session = Depends(get_session),
) -> DailyCumulativeResponse:
    """指定月の日次累積支出."""
    start, end = _month_range(ym)
    # 日別合計を取得 (取引のみベース、明細単位は集計しない簡易版)
    tx_stmt = select(
        Transaction.purchased_at, Transaction.id, Transaction.screening_category, Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
    ).order_by(Transaction.purchased_at)  # type: ignore
    tx_rows = list(session.exec(tx_stmt).all())

    items_by_tx: dict[int, list[TransactionItem]] = defaultdict(list)
    if tx_rows:
        tx_ids = [row[1] for row in tx_rows]
        item_stmt = select(TransactionItem).where(
            TransactionItem.transaction_id.in_(tx_ids)  # type: ignore
        )
        for item in session.exec(item_stmt).all():
            items_by_tx[item.transaction_id].append(item)

    daily_total: dict[date, int] = defaultdict(int)
    for purchased_at, tx_id, screening_category, amount in tx_rows:
        items = items_by_tx.get(tx_id, [])
        if items:
            for item in items:
                daily_total[purchased_at] += item.amount
        else:
            daily_total[purchased_at] += amount

    # 月初から月末まで全日埋める
    points: list[DailyCumulativePoint] = []
    cum = 0
    cursor = start
    while cursor < end:
        cum += daily_total.get(cursor, 0)
        points.append(DailyCumulativePoint(
            date=cursor.isoformat(), cumulative=cum,
        ))
        cursor += timedelta(days=1)
    return DailyCumulativeResponse(ym=ym, points=points, total=cum)


@router.get("/top_transactions", response_model=TopTransactionsResponse)
def top_transactions(
    ym: str = Query(..., pattern=r"^\d{4}-\d{2}$"),
    limit: int = Query(10, ge=1, le=50),
    session: Session = Depends(get_session),
) -> TopTransactionsResponse:
    """指定月の大口支出TOP."""
    start, end = _month_range(ym)
    stmt = select(
        Transaction.id,
        Transaction.purchased_at,
        Transaction.merchant_normalized,
        Transaction.merchant_raw,
        Transaction.screening_category,
        Transaction.amount,
    ).where(
        Transaction.purchased_at >= start,
        Transaction.purchased_at < end,
    ).order_by(Transaction.amount.desc()).limit(limit)  # type: ignore
    rows = session.exec(stmt).all()
    items = [
        TopTransactionItem(
            id=row[0],
            purchased_at=row[1].isoformat(),
            merchant=row[2] or row[3] or "(空)",
            category=row[4],
            amount=row[5],
        )
        for row in rows
    ]
    return TopTransactionsResponse(ym=ym, limit=limit, items=items)
EOF

# ===========================================================================
# 2. frontend/src/api.ts に新API追加
# ===========================================================================
echo "==> frontend/src/api.ts (新API追加)"
python3 <<'PYEOF'
from pathlib import Path
p = Path("frontend/src/api.ts")
text = p.read_text(encoding="utf-8")
if "monthlyByCategory" not in text:
    addition = """

// ===== Cashflow extended =====
export interface MonthlyByCategoryRow {
  ym: string;
  by_category: Record<string, number>;
  total: number;
}
export interface MonthlyByCategoryResponse {
  months: number;
  categories: string[];
  rows: MonthlyByCategoryRow[];
}

export interface DailyCumulativePoint {
  date: string;
  cumulative: number;
}
export interface DailyCumulativeResponse {
  ym: string;
  points: DailyCumulativePoint[];
  total: number;
}

export interface TopTransactionItem {
  id: number;
  purchased_at: string;
  merchant: string;
  category: string | null;
  amount: number;
}
export interface TopTransactionsResponse {
  ym: string;
  limit: number;
  items: TopTransactionItem[];
}

export async function monthlyByCategory(months = 6): Promise<MonthlyByCategoryResponse> {
  return handle<MonthlyByCategoryResponse>(await fetch(`${BASE}/summary/monthly_by_category?months=${months}`));
}

export async function dailyCumulative(ym: string): Promise<DailyCumulativeResponse> {
  return handle<DailyCumulativeResponse>(await fetch(`${BASE}/summary/daily_cumulative?ym=${ym}`));
}

export async function topTransactions(ym: string, limit = 10): Promise<TopTransactionsResponse> {
  return handle<TopTransactionsResponse>(await fetch(`${BASE}/summary/top_transactions?ym=${ym}&limit=${limit}`));
}
"""
    text = text.rstrip() + addition
    p.write_text(text, encoding="utf-8")
    print("  api.ts 追加完了")
else:
    print("  api.ts 既に拡張済み")
PYEOF

# ===========================================================================
# 3. frontend/src/components/GraphView.tsx を拡張版に置換
# ===========================================================================
echo "==> frontend/src/components/GraphView.tsx"
cat > frontend/src/components/GraphView.tsx <<'EOF'
import { useEffect, useMemo, useState } from "react";
import {
  Bar, BarChart, CartesianGrid, Cell, Legend, Line, LineChart,
  Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import {
  categorySummary, dailyCumulative, monthlyByCategory,
  monthlySummary, topTransactions,
} from "../api";
import type {
  CategorySummary, DailyCumulativeResponse, MonthlyByCategoryResponse,
  MonthlySummary, TopTransactionsResponse,
} from "../api";

const COLORS: Record<string, string> = {
  "食費": "#22c55e",
  "酒類": "#f59e0b",
  "外食": "#ef4444",
  "日用品": "#3b82f6",
  "交通費": "#8b5cf6",
  "医療費": "#ec4899",
  "娯楽費": "#06b6d4",
  "衣料費": "#f97316",
  "その他": "#94a3b8",
};

function currentYm(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

export function GraphView() {
  const [ym, setYm] = useState<string>(currentYm());
  const [cat, setCat] = useState<CategorySummary | null>(null);
  const [monthly, setMonthly] = useState<MonthlySummary | null>(null);
  const [stack, setStack] = useState<MonthlyByCategoryResponse | null>(null);
  const [daily, setDaily] = useState<DailyCumulativeResponse | null>(null);
  const [top, setTop] = useState<TopTransactionsResponse | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    setLoading(true);
    setError(null);
    Promise.all([
      categorySummary(ym),
      monthlySummary(6),
      monthlyByCategory(6),
      dailyCumulative(ym),
      topTransactions(ym, 10),
    ])
      .then(([c, m, s, d, t]) => {
        setCat(c); setMonthly(m); setStack(s); setDaily(d); setTop(t);
      })
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }, [ym]);

  // 円グラフ用データ
  const pieData = useMemo(() => {
    if (!cat) return [];
    return cat.slices.map((s) => ({ name: s.category, value: s.amount }));
  }, [cat]);

  // 積み上げ棒グラフ用データ
  const stackData = useMemo(() => {
    if (!stack) return [];
    return stack.rows.map((row) => ({
      ym: row.ym,
      ...row.by_category,
    }));
  }, [stack]);

  // 使用カテゴリ (積み上げで色分けする対象)
  const usedCategories = useMemo(() => {
    if (!stack) return [];
    const set = new Set<string>();
    stack.rows.forEach((row) => {
      Object.keys(row.by_category).forEach((c) => set.add(c));
    });
    return stack.categories.filter((c) => set.has(c));
  }, [stack]);

  return (
    <div>
      <div className="card">
        <h2>表示月の選択</h2>
        <input type="month" value={ym} onChange={(e) => setYm(e.target.value)} />
        {loading && <p>読込中...</p>}
        {error && <p className="err">{error}</p>}
      </div>

      {/* 円グラフ: 今月のカテゴリ比率 */}
      <div className="card">
        <h3>カテゴリ別支出 ({ym})</h3>
        {cat && (
          <>
            <p>合計: <b>{cat.total.toLocaleString()}円</b></p>
            {pieData.length === 0 ? (
              <p className="hint">この月にデータがありません.</p>
            ) : (
              <ResponsiveContainer width="100%" height={300}>
                <PieChart>
                  <Pie
                    data={pieData}
                    dataKey="value"
                    nameKey="name"
                    cx="50%"
                    cy="50%"
                    outerRadius={100}
                    label={(entry: any) =>
                      `${entry.name} ${entry.value.toLocaleString()}円`
                    }
                  >
                    {pieData.map((entry) => (
                      <Cell key={entry.name} fill={COLORS[entry.name] ?? "#94a3b8"} />
                    ))}
                  </Pie>
                  <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
                  <Legend />
                </PieChart>
              </ResponsiveContainer>
            )}
          </>
        )}
      </div>

      {/* 日次累積支出 折れ線 */}
      <div className="card">
        <h3>日次累積支出 ({ym})</h3>
        <p className="hint">月初からの累積額の推移. 月末ペースを把握できる.</p>
        {daily && daily.points.length > 0 && (
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={daily.points}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="date" tickFormatter={(d: string) => d.slice(-2)} />
              <YAxis tickFormatter={(v: number) => (v / 1000).toFixed(0) + "k"} />
              <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
              <Line
                type="monotone" dataKey="cumulative" stroke="#1f6feb"
                strokeWidth={2} dot={false}
              />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 月別カテゴリ積み上げ棒 */}
      <div className="card">
        <h3>過去6ヶ月のカテゴリ別支出</h3>
        <p className="hint">月ごとのカテゴリ構成と総額が一目で分かる.</p>
        {stack && stackData.length > 0 && (
          <ResponsiveContainer width="100%" height={300}>
            <BarChart data={stackData}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="ym" />
              <YAxis tickFormatter={(v: number) => (v / 1000).toFixed(0) + "k"} />
              <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
              <Legend />
              {usedCategories.map((c) => (
                <Bar key={c} dataKey={c} stackId="a" fill={COLORS[c] ?? "#94a3b8"} />
              ))}
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 月次合計 (既存) */}
      <div className="card">
        <h3>月次合計推移 (過去6ヶ月)</h3>
        {monthly && monthly.slices.length > 0 && (
          <ResponsiveContainer width="100%" height={240}>
            <BarChart data={monthly.slices}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="ym" />
              <YAxis tickFormatter={(v: number) => (v / 1000).toFixed(0) + "k"} />
              <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
              <Bar dataKey="total" fill="#1f6feb" />
            </BarChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 大口支出 TOP10 */}
      <div className="card">
        <h3>大口支出 TOP10 ({ym})</h3>
        {top && top.items.length === 0 && <p className="hint">取引なし.</p>}
        {top && top.items.length > 0 && (
          <table className="tx-table" style={{ fontSize: "0.9em" }}>
            <thead>
              <tr>
                <th>順位</th>
                <th>日付</th>
                <th>店舗</th>
                <th>カテゴリ</th>
                <th style={{ textAlign: "right" }}>金額</th>
              </tr>
            </thead>
            <tbody>
              {top.items.map((it, i) => (
                <tr key={it.id}>
                  <td>{i + 1}</td>
                  <td>{it.purchased_at}</td>
                  <td>{it.merchant}</td>
                  <td>{it.category || "(未分類)"}</td>
                  <td style={{ textAlign: "right" }}>
                    <b>{it.amount.toLocaleString()}円</b>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>
    </div>
  );
}
EOF

# ===========================================================================
# 4. uvicorn 再起動 + 動作確認
# ===========================================================================
echo ""
echo "==> uvicorn 再起動"
pkill -9 -f uvicorn 2>/dev/null; sleep 2
(cd /workspaces/kakeibo/backend && nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 5

echo ""
echo "==> health"
curl -s http://localhost:8000/api/health; echo

YM=$(date +%Y-%m)
echo ""
echo "==> 月別カテゴリ積み上げ ($YM 周辺)"
curl -s "http://localhost:8000/api/summary/monthly_by_category?months=3" | python3 -m json.tool | head -40

echo ""
echo "==> 日次累積支出 ($YM)"
curl -s "http://localhost:8000/api/summary/daily_cumulative?ym=$YM" | python3 -c "
import sys,json
d = json.load(sys.stdin)
print(f'  ym={d[\"ym\"]} total={d[\"total\"]}円 points={len(d[\"points\"])}')
print(f'  最終5日:')
for p in d['points'][-5:]:
    print(f'    {p[\"date\"]} 累積={p[\"cumulative\"]}円')
"

echo ""
echo "==> 大口支出 TOP10 ($YM)"
curl -s "http://localhost:8000/api/summary/top_transactions?ym=$YM&limit=5" | python3 -m json.tool | head -30

cat <<EOM

============================================================
キャッシュフロー可視化 完了.

新グラフ (グラフタブ):
  1. カテゴリ別円グラフ (既存)
  2. 日次累積支出 折れ線 (新)
  3. 月別カテゴリ積み上げ棒 (新)
  4. 月次合計 棒 (既存)
  5. 大口支出 TOP10 (新)

確認: ブラウザで Ctrl+Shift+R
============================================================
EOM
