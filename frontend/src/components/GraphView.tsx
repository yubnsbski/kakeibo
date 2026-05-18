import { useEffect, useMemo, useState } from "react";
import {
  Bar, BarChart, CartesianGrid, Cell, Legend, Line, LineChart,
  Pie, PieChart, ResponsiveContainer, Tooltip, XAxis, YAxis,
} from "recharts";
import {
  cashflowSummary, categorySummary, dailyCumulative,
  monthCompare, monthlyByCategory, monthlySummary, topTransactions,
} from "../api";
import type {
  CashflowSummary, CategorySummary, DailyCumulativeResponse,
  MonthCompareResponse, MonthlyByCategoryResponse, MonthlySummary, TopTransactionsResponse,
} from "../api";

const COLORS: Record<string, string> = {
  "食費": "#22c55e", "酒類": "#f59e0b", "外食": "#ef4444",
  "日用品": "#3b82f6", "交通費": "#8b5cf6", "医療費": "#ec4899",
  "娯楽費": "#06b6d4", "衣料費": "#f97316", "その他": "#94a3b8",
};

function currentYm(): string {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

export function GraphView() {
  const [ym, setYm] = useState<string>(currentYm());
  const [cashflow, setCashflow] = useState<CashflowSummary | null>(null);
  const [compare, setCompare] = useState<MonthCompareResponse | null>(null);
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
      cashflowSummary(ym), monthCompare(ym),
      categorySummary(ym), monthlySummary(6),
      monthlyByCategory(6), dailyCumulative(ym), topTransactions(ym, 10),
    ])
      .then(([cf, cmp, c, m, s, d, t]) => {
        setCashflow(cf); setCompare(cmp); setCat(c); setMonthly(m);
        setStack(s); setDaily(d); setTop(t);
      })
      .catch((e) => setError(String(e)))
      .finally(() => setLoading(false));
  }, [ym]);

  const pieData = useMemo(() => {
    if (!cat) return [];
    return cat.slices.map((s) => ({ name: s.category, value: s.amount }));
  }, [cat]);

  const stackData = useMemo(() => {
    if (!stack) return [];
    return stack.rows.map((row) => ({ ym: row.ym, ...row.by_category }));
  }, [stack]);

  const usedCategories = useMemo(() => {
    if (!stack) return [];
    const set = new Set<string>();
    stack.rows.forEach((row) => Object.keys(row.by_category).forEach((c) => set.add(c)));
    return stack.categories.filter((c) => set.has(c));
  }, [stack]);

  return (
    <div>
      {/* 月選択 */}
      <div className="card">
        <h2>表示月の選択</h2>
        <input type="month" value={ym} onChange={(e) => setYm(e.target.value)} />
        {loading && <p>読込中...</p>}
        {error && <p className="err">{error}</p>}
      </div>

      {/* 収支サマリー (新) */}
      <div className="card">
        <h3>収支サマリー ({ym})</h3>
        {cashflow && (
          <div className="cashflow-grid">
            <div className="cashflow-item income">
              <div className="label">収入</div>
              <div className="value">{cashflow.income.toLocaleString()}円</div>
            </div>
            <div className="cashflow-item expense">
              <div className="label">支出</div>
              <div className="value">{cashflow.expense.toLocaleString()}円</div>
            </div>
            <div className={`cashflow-item balance ${cashflow.balance >= 0 ? "positive" : "negative"}`}>
              <div className="label">収支差額</div>
              <div className="value">
                {cashflow.balance >= 0 ? "+" : ""}
                {cashflow.balance.toLocaleString()}円
              </div>
            </div>
          </div>
        )}
      </div>

      {/* 前月比較 (新) */}
      <div className="card">
        <h3>前月比較 ({compare?.previous_ym} → {compare?.current_ym})</h3>
        {compare && compare.diffs.length === 0 && (
          <p className="hint">比較データなし.</p>
        )}
        {compare && compare.diffs.length > 0 && (
          <table className="tx-table" style={{ fontSize: "0.9em" }}>
            <thead>
              <tr>
                <th>カテゴリ</th>
                <th style={{ textAlign: "right" }}>先月</th>
                <th style={{ textAlign: "right" }}>今月</th>
                <th style={{ textAlign: "right" }}>差額</th>
                <th style={{ textAlign: "right" }}>増減率</th>
              </tr>
            </thead>
            <tbody>
              {compare.diffs.map((d) => (
                <tr key={d.category}>
                  <td>{d.category}</td>
                  <td style={{ textAlign: "right" }}>{d.previous.toLocaleString()}</td>
                  <td style={{ textAlign: "right" }}>{d.current.toLocaleString()}</td>
                  <td style={{
                    textAlign: "right",
                    color: d.diff > 0 ? "#cf222e" : d.diff < 0 ? "#1a7f37" : "#666",
                  }}>
                    {d.diff > 0 ? "+" : ""}{d.diff.toLocaleString()}
                  </td>
                  <td style={{
                    textAlign: "right",
                    color: (d.ratio ?? 0) > 0 ? "#cf222e" : (d.ratio ?? 0) < 0 ? "#1a7f37" : "#666",
                  }}>
                    {d.ratio === null
                      ? "(新規)"
                      : `${(d.ratio * 100 > 0 ? "+" : "")}${(d.ratio * 100).toFixed(1)}%`}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* 既存: カテゴリ別円グラフ */}
      <div className="card">
        <h3>カテゴリ別支出 ({ym})</h3>
        {cat && pieData.length > 0 && (
          <>
            <p>合計: <b>{cat.total.toLocaleString()}円</b></p>
            <ResponsiveContainer width="100%" height={300}>
              <PieChart>
                <Pie data={pieData} dataKey="value" nameKey="name"
                     cx="50%" cy="50%" outerRadius={100}
                     label={(e: any) => `${e.name} ${e.value.toLocaleString()}円`}>
                  {pieData.map((entry) => (
                    <Cell key={entry.name} fill={COLORS[entry.name] ?? "#94a3b8"} />
                  ))}
                </Pie>
                <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
                <Legend />
              </PieChart>
            </ResponsiveContainer>
          </>
        )}
        {cat && pieData.length === 0 && <p className="hint">支出データなし.</p>}
      </div>

      {/* 日次累積 */}
      <div className="card">
        <h3>日次累積支出 ({ym})</h3>
        {daily && daily.points.length > 0 && (
          <ResponsiveContainer width="100%" height={240}>
            <LineChart data={daily.points}>
              <CartesianGrid strokeDasharray="3 3" />
              <XAxis dataKey="date" tickFormatter={(d: string) => d.slice(-2)} />
              <YAxis tickFormatter={(v: number) => (v / 1000).toFixed(0) + "k"} />
              <Tooltip formatter={(v: number) => `${v.toLocaleString()}円`} />
              <Line type="monotone" dataKey="cumulative" stroke="#1f6feb"
                    strokeWidth={2} dot={false} />
            </LineChart>
          </ResponsiveContainer>
        )}
      </div>

      {/* 月別カテゴリ積み上げ */}
      <div className="card">
        <h3>過去6ヶ月のカテゴリ別支出</h3>
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

      {/* 月次合計 */}
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
                <th>順位</th><th>日付</th><th>店舗</th><th>カテゴリ</th>
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
