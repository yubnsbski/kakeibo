import { useEffect, useMemo, useState } from "react";
import { decryptJson, requireKey } from "../index";
import {
  fetchEncryptedTx,
  type EncryptedTxRow,
} from "../encryptedTxApi";
import {
  summarizeByCategory,
  type CategoryTotal,
  type PeriodUnit,
} from "../periodSummary";
import {
  normalizeEncryptedPayload,
  type EncryptedTxPayload,
  type NormalizedEncryptedTx,
} from "../txPayload";

function todayLocalIsoDate(): string {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, "0");
  const day = String(now.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

function yen(value: number): string {
  return `${value.toLocaleString()}円`;
}

function CategoryTable({
  title,
  rows,
}: {
  title: string;
  rows: CategoryTotal[];
}) {
  return (
    <div style={{ minWidth: 280, flex: "1 1 320px" }}>
      <h3>{title}</h3>
      {rows.length === 0 ? (
        <p className="hint">該当する取引はありません。</p>
      ) : (
        <table>
          <thead>
            <tr>
              <th>カテゴリ</th>
              <th>合計金額</th>
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.category}>
                <td>{row.category}</td>
                <td>{yen(row.amount)}</td>
              </tr>
            ))}
          </tbody>
        </table>
      )}
    </div>
  );
}

type EncryptedSummaryViewProps = {
  refreshKey?: number;
};

export function EncryptedSummaryView({
  refreshKey = 0,
}: EncryptedSummaryViewProps) {
  const [rows, setRows] = useState<NormalizedEncryptedTx[]>([]);
  const [unit, setUnit] = useState<PeriodUnit>("month");
  const [anchorDate, setAnchorDate] = useState(todayLocalIsoDate());
  const [decryptFailures, setDecryptFailures] = useState(0);
  const [message, setMessage] = useState("");
  const [loading, setLoading] = useState(false);

  const summary = useMemo(
    () => summarizeByCategory(rows, unit, anchorDate),
    [rows, unit, anchorDate],
  );

  async function loadRows() {
    setLoading(true);
    setMessage("");

    try {
      const key = requireKey();
      const encryptedRows = await fetchEncryptedTx();
      const normalizedRows = await Promise.all(
        encryptedRows.map(
          async (row: EncryptedTxRow): Promise<NormalizedEncryptedTx | null> => {
            try {
              const record = JSON.parse(row.encrypted_payload);
              const payload = await decryptJson<EncryptedTxPayload>(key, record);
              return normalizeEncryptedPayload(payload);
            } catch {
              return null;
            }
          },
        ),
      );
      const validRows = normalizedRows.filter(
        (row): row is NormalizedEncryptedTx => row !== null,
      );

      setRows(validRows);
      setDecryptFailures(normalizedRows.length - validRows.length);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : String(error));
    } finally {
      setLoading(false);
    }
  }

  function updateDay(value: string) {
    if (/^\d{4}-\d{2}-\d{2}$/.test(value)) {
      setAnchorDate(value);
    }
  }

  function updateMonth(value: string) {
    if (/^\d{4}-\d{2}$/.test(value)) {
      setAnchorDate(`${value}-01`);
    }
  }

  function updateYear(value: string) {
    if (/^\d{4}$/.test(value)) {
      setAnchorDate(`${value}-01-01`);
    }
  }

  useEffect(() => {
    void loadRows();
  }, [refreshKey]);

  return (
    <section style={{ border: "1px solid #ddd", padding: 16, marginTop: 16 }}>
      <h2>カテゴリ別合計</h2>
      <p className="hint">
        暗号化取引をブラウザ内で復号し、選択した日・月・年ごとに集計します。
      </p>

      <div
        style={{
          display: "flex",
          gap: 12,
          alignItems: "end",
          flexWrap: "wrap",
        }}
      >
        <label>
          集計単位
          <select
            value={unit}
            onChange={(event) => setUnit(event.target.value as PeriodUnit)}
          >
            <option value="day">日</option>
            <option value="month">月</option>
            <option value="year">年</option>
          </select>
        </label>

        {unit === "day" && (
          <label>
            日付
            <input
              type="date"
              value={anchorDate}
              onChange={(event) => updateDay(event.target.value)}
            />
          </label>
        )}

        {unit === "month" && (
          <label>
            月
            <input
              type="month"
              value={anchorDate.slice(0, 7)}
              onChange={(event) => updateMonth(event.target.value)}
            />
          </label>
        )}

        {unit === "year" && (
          <label>
            年
            <input
              type="number"
              min="1900"
              max="9999"
              step="1"
              value={anchorDate.slice(0, 4)}
              onChange={(event) => updateYear(event.target.value)}
            />
          </label>
        )}

        <button onClick={() => void loadRows()} disabled={loading}>
          {loading ? "集計中..." : "再集計"}
        </button>
      </div>

      {message && <p className="err">{message}</p>}
      {decryptFailures > 0 && (
        <p className="err">
          復号できない取引 {decryptFailures}件は集計対象外です。
        </p>
      )}
      {summary.skippedInvalidRows > 0 && (
        <p className="err">
          日付が不正な取引 {summary.skippedInvalidRows}件は集計対象外です。
        </p>
      )}
      {summary.fallbackRows > 0 && (
        <p className="hint">
          明細合計が取引合計と一致しない、または明細がない取引
          {summary.fallbackRows}件は、取引本体のカテゴリと合計金額で集計しました。
        </p>
      )}

      <h3>{summary.label}</h3>
      <p className="hint">対象取引: {summary.matchingRows}件</p>

      <div
        style={{
          display: "grid",
          gridTemplateColumns: "repeat(auto-fit, minmax(180px, 1fr))",
          gap: 12,
          marginBottom: 20,
        }}
      >
        <div style={{ border: "1px solid #ddd", padding: 12 }}>
          <strong>支出合計</strong>
          <div>{yen(summary.expenseTotal)}</div>
        </div>
        <div style={{ border: "1px solid #ddd", padding: 12 }}>
          <strong>収入合計</strong>
          <div>{yen(summary.incomeTotal)}</div>
        </div>
        <div style={{ border: "1px solid #ddd", padding: 12 }}>
          <strong>収支</strong>
          <div>{yen(summary.balance)}</div>
        </div>
      </div>

      <div style={{ display: "flex", gap: 24, flexWrap: "wrap" }}>
        <CategoryTable title="支出カテゴリ" rows={summary.expenseCategories} />
        <CategoryTable title="収入カテゴリ" rows={summary.incomeCategories} />
      </div>
    </section>
  );
}
