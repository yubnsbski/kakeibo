#!/usr/bin/env bash
# グラフ改善: カテゴリから自販機・割り勘削除 + グラフ刷新
#   - categories.ts: 自販機/割り勘 を選択肢から削除
#   - EncryptedGraphView.tsx: 縦軸ラベルずらし、大口支出TOP10タブ追加、表示拡大
#
# 既存データには触れない。frontend の2ファイルを上書きするだけ。
#
# 使い方: cd /workspaces/kakeibo && bash setup_graph_update.sh

set -u
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "グラフ改善 + カテゴリ整理"
echo "============================================================"

echo ""
echo "==> frontend/src/crypto/categories.ts"
cat > frontend/src/crypto/categories.ts <<'CATEOF'
/**
 * 支出・収入カテゴリの定義。
 *
 * カテゴリは「何に使ったか」を表す。
 * 「現金/割り勘/自販機」などの支払い手段は payment_method 側で扱い、
 * カテゴリには含めない。
 */

export const EXPENSE_CATEGORIES = [
  "食費",
  "日用品",
  "交通",
  "交際費",
  "娯楽",
  "医療",
  "通信",
  "住居",
  "水道光熱",
  "教育",
  "衣服",
  "その他",
  "未分類",
] as const;

export const INCOME_CATEGORIES = [
  "給与",
  "副業",
  "臨時収入",
  "返金",
  "その他収入",
] as const;

export type ExpenseCategory = (typeof EXPENSE_CATEGORIES)[number];
export type IncomeCategory = (typeof INCOME_CATEGORIES)[number];

export function categoryOptions(txType: "expense" | "income"): readonly string[] {
  return txType === "income" ? INCOME_CATEGORIES : EXPENSE_CATEGORIES;
}

export function normalizeCategory(category: string | null | undefined): string {
  if (!category) return "未分類";
  return category.trim() || "未分類";
}

/**
 * カテゴリ選択肢を返す。
 * 既存データに、現在の選択肢に無いカテゴリ（旧「自販機」「割り勘」など）が
 * 入っている場合、その値を先頭に追加して選択可能にする。
 * これにより、編集時に既存値が消えるのを防ぐ。
 */
export function categoryOptionsWithCurrent(
  txType: "expense" | "income",
  current: string | null | undefined,
): string[] {
  const normalized = normalizeCategory(current);
  const base = [...categoryOptions(txType)];

  if (!base.includes(normalized)) {
    return [normalized, ...base];
  }

  return base;
}
CATEOF

echo "==> frontend/src/crypto/ui/EncryptedGraphView.tsx"
cat > frontend/src/crypto/ui/EncryptedGraphView.tsx <<'GRAPHEOF'
import { useEffect, useMemo, useState } from "react";
import { decryptJson, requireKey } from "../index";
import { fetchEncryptedTx } from "../encryptedTxApi";
import {
  categoryExpenseSummary,
  normalizeEncryptedPayload,
  totalExpense,
  totalIncome,
  type EncryptedTxPayload,
  type NormalizedEncryptedTx,
} from "../txPayload";

type ChartTab = "pie" | "bar" | "line" | "top10";

type LoadState =
  | { status: "loading" }
  | { status: "error"; message: string }
  | { status: "ready"; rows: NormalizedEncryptedTx[] };

/** グラフ配色（カテゴリ別の固定パレット風）。 */
const PALETTE = [
  "#e8743b",
  "#3b8ee8",
  "#4cae7a",
  "#d9b13b",
  "#9b59b6",
  "#e85b8a",
  "#3bb3c4",
  "#7a8b3b",
  "#c4603b",
  "#5a6acf",
  "#aa5a3b",
  "#8a8a8a",
  "#6abf4c",
  "#cf5a5a",
];

function colorFor(index: number): string {
  return PALETTE[index % PALETTE.length];
}

function currentYm(): string {
  return new Date().toISOString().slice(0, 7);
}

function rowYm(date: string): string {
  return date.slice(0, 7);
}

function ymOffset(baseYm: string, offset: number): string {
  const [year, month] = baseYm.split("-").map(Number);
  const d = new Date(year, month - 1 + offset, 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function dayOfMonth(date: string): number {
  return Number(date.slice(8, 10));
}

function daysInYm(ym: string): number {
  const [year, month] = ym.split("-").map(Number);
  return new Date(year, month, 0).getDate();
}

function polarToCartesian(cx: number, cy: number, r: number, angle: number) {
  const rad = ((angle - 90) * Math.PI) / 180;
  return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
}

function piePath(cx: number, cy: number, r: number, start: number, end: number) {
  const s = polarToCartesian(cx, cy, r, end);
  const e = polarToCartesian(cx, cy, r, start);
  const largeArc = end - start <= 180 ? "0" : "1";
  return `M ${cx} ${cy} L ${s.x} ${s.y} A ${r} ${r} 0 ${largeArc} 0 ${e.x} ${e.y} Z`;
}

/** 軸目盛り用に、金額を読みやすい単位に丸める（縦軸ラベル）。 */
function formatAxisYen(value: number): string {
  if (value >= 10000) {
    const man = value / 10000;
    return `${Number.isInteger(man) ? man : man.toFixed(1)}万`;
  }
  return value.toLocaleString();
}

function signedYen(value: number): string {
  return `${value >= 0 ? "+" : ""}${value.toLocaleString()}円`;
}

function diffLabel(current: number, previous: number): string {
  if (previous === 0) {
    return current === 0 ? "±0円" : `${current.toLocaleString()}円（比較元なし）`;
  }
  const diff = current - previous;
  const ratio = (diff / previous) * 100;
  return `${signedYen(diff)}（${ratio >= 0 ? "+" : ""}${ratio.toFixed(1)}%）`;
}

export function EncryptedGraphView() {
  const [ym, setYm] = useState(currentYm());
  const [tab, setTab] = useState<ChartTab>("pie");
  const [state, setState] = useState<LoadState>({ status: "loading" });

  async function loadRows() {
    setState({ status: "loading" });
    try {
      const key = requireKey();
      const encryptedRows = await fetchEncryptedTx();
      const rows: NormalizedEncryptedTx[] = [];

      for (const row of encryptedRows) {
        try {
          const record = JSON.parse(row.encrypted_payload);
          const payload = await decryptJson<EncryptedTxPayload>(key, record);
          rows.push(normalizeEncryptedPayload(payload));
        } catch {
          // 復号不能データは集計から除外
        }
      }

      setState({ status: "ready", rows });
    } catch (e) {
      setState({
        status: "error",
        message: e instanceof Error ? e.message : String(e),
      });
    }
  }

  useEffect(() => {
    void loadRows();
  }, []);

  const allRows = state.status === "ready" ? state.rows : [];

  const filteredRows = useMemo(
    () => allRows.filter((row) => rowYm(row.date) === ym),
    [allRows, ym],
  );

  const previousMonthYm = ymOffset(ym, -1);
  const previousYearYm = ymOffset(ym, -12);

  const previousMonthExpense = useMemo(
    () => totalExpense(allRows.filter((r) => rowYm(r.date) === previousMonthYm)),
    [allRows, previousMonthYm],
  );
  const previousYearExpense = useMemo(
    () => totalExpense(allRows.filter((r) => rowYm(r.date) === previousYearYm)),
    [allRows, previousYearYm],
  );

  const categoryRows = useMemo(
    () => categoryExpenseSummary(filteredRows),
    [filteredRows],
  );

  const income = totalIncome(filteredRows);
  const expense = totalExpense(filteredRows);
  const balance = income - expense;

  const maxAmount = Math.max(...categoryRows.map((r) => r.amount), 1);
  const totalCategoryExpense = categoryRows.reduce((s, r) => s + r.amount, 0);

  const days = daysInYm(ym);

  const dailyPoints = useMemo(() => {
    const byDay = new Map<number, number>();
    for (const row of filteredRows) {
      if (row.tx_type !== "expense") continue;
      const day = dayOfMonth(row.date);
      byDay.set(day, (byDay.get(day) ?? 0) + row.amount);
    }
    let cumulative = 0;
    return Array.from({ length: days }, (_, i) => {
      const day = i + 1;
      cumulative += byDay.get(day) ?? 0;
      return { day, amount: byDay.get(day) ?? 0, cumulative };
    });
  }, [filteredRows, days]);

  const maxCumulative = Math.max(...dailyPoints.map((p) => p.cumulative), 1);
  const axisMax = Math.ceil(maxCumulative / 10000) * 10000 || 10000;

  /** 大口支出 TOP10（取引単位）。 */
  const top10 = useMemo(() => {
    return filteredRows
      .filter((r) => r.tx_type === "expense")
      .slice()
      .sort((a, b) => b.amount - a.amount)
      .slice(0, 10);
  }, [filteredRows]);

  const top10Max = Math.max(...top10.map((r) => r.amount), 1);

  // ---- スタイル ----
  const tabButton = (active: boolean): React.CSSProperties => ({
    padding: "10px 20px",
    fontSize: "0.95rem",
    fontWeight: active ? 700 : 500,
    color: active ? "#fff" : "#44443f",
    background: active ? "#e8743b" : "#f0f0ee",
    border: "none",
    borderRadius: 8,
    cursor: "pointer",
  });

  const statCard = (accent: string): React.CSSProperties => ({
    flex: "1 1 140px",
    minWidth: 140,
    padding: "14px 16px",
    background: "#fff",
    border: "1px solid #e6e6e3",
    borderLeft: `4px solid ${accent}`,
    borderRadius: 8,
  });

  return (
    <section
      style={{
        padding: 20,
        background: "#faf9f7",
        borderRadius: 12,
        marginTop: 16,
      }}
    >
      <h2 style={{ fontSize: "1.5rem", margin: "0 0 6px" }}>グラフ</h2>
      <p className="hint" style={{ margin: "0 0 16px" }}>
        encrypted_transactions をブラウザ側で復号し、明細カテゴリ別に集計します。
      </p>

      <label style={{ fontSize: "0.95rem" }}>
        対象月{" "}
        <input
          type="month"
          value={ym}
          onChange={(e) => setYm(e.target.value)}
          style={{ padding: "6px 10px", fontSize: "0.95rem" }}
        />
      </label>

      {/* サマリーカード */}
      <div
        style={{
          display: "flex",
          gap: 12,
          flexWrap: "wrap",
          margin: "16px 0",
        }}
      >
        <div style={statCard("#4cae7a")}>
          <div style={{ fontSize: "0.8rem", color: "#777" }}>収入</div>
          <div style={{ fontSize: "1.35rem", fontWeight: 700 }}>
            {income.toLocaleString()}円
          </div>
        </div>
        <div style={statCard("#e8743b")}>
          <div style={{ fontSize: "0.8rem", color: "#777" }}>支出</div>
          <div style={{ fontSize: "1.35rem", fontWeight: 700 }}>
            {expense.toLocaleString()}円
          </div>
        </div>
        <div style={statCard(balance >= 0 ? "#3b8ee8" : "#cf5a5a")}>
          <div style={{ fontSize: "0.8rem", color: "#777" }}>差額</div>
          <div
            style={{
              fontSize: "1.35rem",
              fontWeight: 700,
              color: balance >= 0 ? "#1a1a18" : "#cf222e",
            }}
          >
            {balance.toLocaleString()}円
          </div>
        </div>
        <div style={statCard("#9b59b6")}>
          <div style={{ fontSize: "0.8rem", color: "#777" }}>前月比支出</div>
          <div style={{ fontSize: "1rem", fontWeight: 600 }}>
            {diffLabel(expense, previousMonthExpense)}
          </div>
        </div>
        <div style={statCard("#d9b13b")}>
          <div style={{ fontSize: "0.8rem", color: "#777" }}>前年同月比支出</div>
          <div style={{ fontSize: "1rem", fontWeight: 600 }}>
            {diffLabel(expense, previousYearExpense)}
          </div>
        </div>
      </div>

      {/* グラフ切替タブ */}
      <div style={{ display: "flex", gap: 8, flexWrap: "wrap", marginBottom: 8 }}>
        <button style={tabButton(tab === "pie")} onClick={() => setTab("pie")}>
          円グラフ
        </button>
        <button style={tabButton(tab === "bar")} onClick={() => setTab("bar")}>
          棒グラフ
        </button>
        <button style={tabButton(tab === "line")} onClick={() => setTab("line")}>
          推移
        </button>
        <button
          style={tabButton(tab === "top10")}
          onClick={() => setTab("top10")}
        >
          大口支出TOP10
        </button>
      </div>

      {state.status === "loading" && <p>読み込み中...</p>}
      {state.status === "error" && <p className="err">{state.message}</p>}

      {state.status === "ready" && (
        <div
          style={{
            background: "#fff",
            border: "1px solid #e6e6e3",
            borderRadius: 10,
            padding: 20,
            marginTop: 8,
          }}
        >
          {/* ===== 円グラフ ===== */}
          {tab === "pie" && (
            <div>
              <h3 style={{ fontSize: "1.2rem", marginTop: 0 }}>
                カテゴリ構成比
              </h3>
              {categoryRows.length === 0 ? (
                <p>対象月の支出はありません。</p>
              ) : (
                <div
                  style={{
                    display: "flex",
                    gap: 32,
                    flexWrap: "wrap",
                    alignItems: "center",
                  }}
                >
                  <svg width="300" height="300" viewBox="0 0 300 300">
                    {categoryRows.map((row, index) => {
                      const start = categoryRows
                        .slice(0, index)
                        .reduce(
                          (sum, prev) =>
                            sum + (prev.amount / totalCategoryExpense) * 360,
                          0,
                        );
                      const end =
                        start + (row.amount / totalCategoryExpense) * 360;
                      return (
                        <path
                          key={row.category}
                          d={piePath(150, 150, 130, start, end)}
                          fill={colorFor(index)}
                          stroke="#fff"
                          strokeWidth="2"
                        />
                      );
                    })}
                    {/* 中央の合計表示（ドーナツ風） */}
                    <circle cx="150" cy="150" r="62" fill="#fff" />
                    <text
                      x="150"
                      y="144"
                      textAnchor="middle"
                      fontSize="13"
                      fill="#777"
                    >
                      支出合計
                    </text>
                    <text
                      x="150"
                      y="168"
                      textAnchor="middle"
                      fontSize="18"
                      fontWeight="700"
                      fill="#1a1a18"
                    >
                      {totalCategoryExpense.toLocaleString()}
                    </text>
                  </svg>

                  <div style={{ display: "grid", gap: 8 }}>
                    {categoryRows.map((row, index) => {
                      const pct = (
                        (row.amount / totalCategoryExpense) *
                        100
                      ).toFixed(1);
                      return (
                        <div
                          key={row.category}
                          style={{
                            display: "flex",
                            alignItems: "center",
                            gap: 8,
                            fontSize: "0.95rem",
                          }}
                        >
                          <span
                            style={{
                              width: 16,
                              height: 16,
                              borderRadius: 4,
                              background: colorFor(index),
                              flexShrink: 0,
                            }}
                          />
                          <span style={{ minWidth: 72 }}>{row.category}</span>
                          <span style={{ fontWeight: 600 }}>
                            {row.amount.toLocaleString()}円
                          </span>
                          <span style={{ color: "#999" }}>({pct}%)</span>
                        </div>
                      );
                    })}
                  </div>
                </div>
              )}
            </div>
          )}

          {/* ===== 棒グラフ ===== */}
          {tab === "bar" && (
            <div>
              <h3 style={{ fontSize: "1.2rem", marginTop: 0 }}>
                カテゴリ別支出
              </h3>
              {categoryRows.length === 0 ? (
                <p>対象月の支出はありません。</p>
              ) : (
                <div style={{ display: "grid", gap: 14 }}>
                  {categoryRows.map((row, index) => (
                    <div key={row.category}>
                      <div
                        style={{
                          display: "flex",
                          justifyContent: "space-between",
                          fontSize: "0.95rem",
                          marginBottom: 4,
                        }}
                      >
                        <span style={{ fontWeight: 600 }}>{row.category}</span>
                        <span style={{ fontWeight: 700 }}>
                          {row.amount.toLocaleString()}円
                        </span>
                      </div>
                      <div
                        style={{
                          background: "#f0f0ee",
                          height: 22,
                          borderRadius: 6,
                          overflow: "hidden",
                        }}
                      >
                        <div
                          style={{
                            width: `${Math.max(2, (row.amount / maxAmount) * 100)}%`,
                            height: "100%",
                            borderRadius: 6,
                            background: colorFor(index),
                          }}
                        />
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          {/* ===== 推移（折れ線・軸ラベルずらし済み） ===== */}
          {tab === "line" && (
            <div>
              <h3 style={{ fontSize: "1.2rem", marginTop: 0 }}>
                日次累計支出
              </h3>
              {/*
                左マージンを 96 まで広げ、縦軸ラベルを軸線から離して配置。
                これにより縦軸の数値が軸線に重ならない。
              */}
              <svg
                width="100%"
                height="340"
                viewBox="0 0 760 340"
                style={{ overflow: "visible" }}
              >
                {/* プロット領域: x=96..720, y=40..280 */}
                {/* 横軸 */}
                <line x1="96" y1="280" x2="720" y2="280" stroke="#bbb" strokeWidth="1.5" />
                {/* 縦軸 */}
                <line x1="96" y1="40" x2="96" y2="280" stroke="#bbb" strokeWidth="1.5" />

                {/* 軸タイトル */}
                <text x="14" y="28" fontSize="13" fontWeight="600" fill="#555">
                  累計支出(円)
                </text>
                <text x="700" y="318" fontSize="13" fontWeight="600" fill="#555">
                  日
                </text>

                {/* 横グリッド + 縦軸目盛りラベル（軸線 x=96 から左に18px離す） */}
                {[0, 0.25, 0.5, 0.75, 1].map((ratio) => {
                  const y = 280 - ratio * 240;
                  const value = Math.round(axisMax * ratio);
                  return (
                    <g key={ratio}>
                      <line
                        x1="96"
                        y1={y}
                        x2="720"
                        y2={y}
                        stroke="#f0f0ee"
                        strokeWidth="1"
                      />
                      {/* 目盛り短線 */}
                      <line x1="90" y1={y} x2="96" y2={y} stroke="#bbb" />
                      {/* ラベル: 軸より十分左、右寄せで重なり回避 */}
                      <text
                        x="84"
                        y={y + 4}
                        fontSize="12"
                        textAnchor="end"
                        fill="#777"
                      >
                        {formatAxisYen(value)}
                      </text>
                    </g>
                  );
                })}

                {/* 横軸目盛り */}
                {[1, 5, 10, 15, 20, 25, days].map((day) => {
                  const x = 96 + ((day - 1) / Math.max(days - 1, 1)) * 624;
                  return (
                    <g key={day}>
                      <line x1={x} y1="280" x2={x} y2="286" stroke="#bbb" />
                      <text
                        x={x}
                        y="302"
                        fontSize="12"
                        textAnchor="middle"
                        fill="#777"
                      >
                        {day}
                      </text>
                    </g>
                  );
                })}

                {/* 折れ線の下の塗り（面） */}
                <polygon
                  fill="rgba(232,116,59,0.12)"
                  points={
                    `96,280 ` +
                    dailyPoints
                      .map((p) => {
                        const x =
                          96 + ((p.day - 1) / Math.max(days - 1, 1)) * 624;
                        const y = 280 - (p.cumulative / axisMax) * 240;
                        return `${x},${y}`;
                      })
                      .join(" ") +
                    ` 720,280`
                  }
                />

                {/* 折れ線本体 */}
                <polyline
                  fill="none"
                  stroke="#e8743b"
                  strokeWidth="3.5"
                  strokeLinejoin="round"
                  points={dailyPoints
                    .map((p) => {
                      const x =
                        96 + ((p.day - 1) / Math.max(days - 1, 1)) * 624;
                      const y = 280 - (p.cumulative / axisMax) * 240;
                      return `${x},${y}`;
                    })
                    .join(" ")}
                />
              </svg>
            </div>
          )}

          {/* ===== 大口支出 TOP10 ===== */}
          {tab === "top10" && (
            <div>
              <h3 style={{ fontSize: "1.2rem", marginTop: 0 }}>
                大口支出 TOP10（取引単位）
              </h3>
              {top10.length === 0 ? (
                <p>対象月の支出はありません。</p>
              ) : (
                <div style={{ display: "grid", gap: 10 }}>
                  {top10.map((row, index) => (
                    <div
                      key={`${row.date}-${index}`}
                      style={{
                        display: "flex",
                        alignItems: "center",
                        gap: 12,
                      }}
                    >
                      {/* 順位バッジ */}
                      <span
                        style={{
                          width: 30,
                          height: 30,
                          borderRadius: "50%",
                          background: index < 3 ? "#e8743b" : "#c9c9c5",
                          color: "#fff",
                          fontWeight: 700,
                          fontSize: "0.9rem",
                          display: "flex",
                          alignItems: "center",
                          justifyContent: "center",
                          flexShrink: 0,
                        }}
                      >
                        {index + 1}
                      </span>

                      <div style={{ flex: 1, minWidth: 0 }}>
                        <div
                          style={{
                            display: "flex",
                            justifyContent: "space-between",
                            fontSize: "0.95rem",
                            marginBottom: 4,
                          }}
                        >
                          <span
                            style={{
                              fontWeight: 600,
                              overflow: "hidden",
                              textOverflow: "ellipsis",
                              whiteSpace: "nowrap",
                            }}
                          >
                            {row.merchant}
                            <span
                              style={{
                                color: "#999",
                                fontWeight: 400,
                                marginLeft: 8,
                              }}
                            >
                              {row.category} / {row.date}
                            </span>
                          </span>
                          <span style={{ fontWeight: 700, flexShrink: 0 }}>
                            {row.amount.toLocaleString()}円
                          </span>
                        </div>
                        <div
                          style={{
                            background: "#f0f0ee",
                            height: 14,
                            borderRadius: 5,
                            overflow: "hidden",
                          }}
                        >
                          <div
                            style={{
                              width: `${Math.max(2, (row.amount / top10Max) * 100)}%`,
                              height: "100%",
                              borderRadius: 5,
                              background:
                                index < 3 ? "#e8743b" : "#9aa0a6",
                            }}
                          />
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          )}

          <button
            style={{
              marginTop: 20,
              padding: "8px 18px",
              fontSize: "0.9rem",
              background: "#f0f0ee",
              border: "1px solid #ddd",
              borderRadius: 8,
              cursor: "pointer",
            }}
            onClick={() => void loadRows()}
          >
            再読み込み
          </button>
        </div>
      )}
    </section>
  );
}
GRAPHEOF

echo ""
echo "==> ビルド確認"
cd "$REPO/frontend"
npm run build 2>&1 | tail -15
cd "$REPO"

cat <<'EOM'

============================================================
配置完了.

変更:
  categories.ts        : 「自販機」「割り勘」を選択肢から削除
                         (既存データの旧カテゴリは categoryOptionsWithCurrent で
                          編集時に選択肢へ自動補完されるため消えない)
  EncryptedGraphView.tsx:
    - 縦軸ラベルを軸線から離して配置 (重なり解消)
    - 大口支出TOP10タブを追加 (取引単位・金額降順)
    - グラフ拡大: 円300px / 折れ線760x340 / サマリーをカード化
    - 配色パレット整理、ドーナツ中央に支出合計

ビルドが通っていれば、Vite が動いている前提でブラウザを
Ctrl+Shift+R で再読み込みしてください。
グラフタブ → 円 / 棒 / 推移 / 大口支出TOP10 を確認.
============================================================
EOM
