import { useState, useEffect, useMemo } from 'react'
import Papa from 'papaparse'

type Transaction = {
  id: string
  date: string      // YYYY-MM-DD
  amount: number    // 支出は負、収入は正
  category: string
  memo: string
}

const STORAGE_KEY = 'kakeibo-transactions'

export default function App() {
  const [transactions, setTransactions] = useState<Transaction[]>(() => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY)
      return raw ? JSON.parse(raw) : []
    } catch {
      return []
    }
  })

  useEffect(() => {
    localStorage.setItem(STORAGE_KEY, JSON.stringify(transactions))
  }, [transactions])

  const handleCsvUpload = (file: File) => {
    Papa.parse<Record<string, string>>(file, {
      header: true,
      skipEmptyLines: true,
      complete: (result) => {
        const parsed: Transaction[] = result.data.map((row, idx) => ({
          id: `${Date.now()}-${idx}`,
          date: row.date ?? '',
          amount: Number(row.amount ?? 0),
          category: row.category ?? 'その他',
          memo: row.memo ?? '',
        }))
        setTransactions((prev) => [...prev, ...parsed])
      },
      error: (err) => {
        console.error('CSV parse error:', err)
        alert('CSV読み込みに失敗しました')
      },
    })
  }

  const categorySummary = useMemo(() => {
    const map = new Map<string, number>()
    for (const t of transactions) {
      map.set(t.category, (map.get(t.category) ?? 0) + t.amount)
    }
    return Array.from(map.entries()).sort((a, b) => a[1] - b[1])
  }, [transactions])

  const total = useMemo(
    () => transactions.reduce((sum, t) => sum + t.amount, 0),
    [transactions]
  )

  const handleManualAdd = (t: Omit<Transaction, 'id'>) => {
    setTransactions((prev) => [
      ...prev,
      { ...t, id: `${Date.now()}-manual` },
    ])
  }

  const handleDelete = (id: string) => {
    setTransactions((prev) => prev.filter((t) => t.id !== id))
  }

  const handleClear = () => {
    if (confirm('全データを削除しますか？')) setTransactions([])
  }

  const handleExport = () => {
    const csv = Papa.unparse(
      transactions.map(({ id, ...rest }) => rest)
    )
    const blob = new Blob([csv], { type: 'text/csv;charset=utf-8;' })
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `kakeibo-${new Date().toISOString().slice(0, 10)}.csv`
    a.click()
    URL.revokeObjectURL(url)
  }

  return (
    <div style={styles.container}>
      <h1 style={styles.h1}>家計簿</h1>

      <section style={styles.section}>
        <h2 style={styles.h2}>CSV取込</h2>
        <p style={styles.hint}>ヘッダ: date, amount, category, memo</p>
        <input
          type="file"
          accept=".csv"
          onChange={(e) => {
            const f = e.target.files?.[0]
            if (f) handleCsvUpload(f)
            e.target.value = ''
          }}
        />
        <button onClick={handleExport} style={{ marginLeft: 8 }}>
          エクスポート
        </button>
      </section>

      <ManualAddForm onAdd={handleManualAdd} />

      <section style={styles.section}>
        <h2 style={styles.h2}>合計</h2>
        <p style={{ fontSize: 24, margin: '4px 0' }}>
          {total.toLocaleString()} 円
        </p>
        <button onClick={handleClear}>全削除</button>
      </section>

      <section style={styles.section}>
        <h2 style={styles.h2}>カテゴリ別集計</h2>
        <table style={styles.table}>
          <thead>
            <tr style={styles.trHead}>
              <th style={styles.th}>カテゴリ</th>
              <th style={{ ...styles.th, textAlign: 'right' }}>合計</th>
            </tr>
          </thead>
          <tbody>
            {categorySummary.map(([cat, sum]) => (
              <tr key={cat} style={styles.tr}>
                <td style={styles.td}>{cat}</td>
                <td style={{ ...styles.td, textAlign: 'right' }}>
                  {sum.toLocaleString()}
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>

      <section style={styles.section}>
        <h2 style={styles.h2}>取引一覧 ({transactions.length})</h2>
        <table style={styles.table}>
          <thead>
            <tr style={styles.trHead}>
              <th style={styles.th}>日付</th>
              <th style={{ ...styles.th, textAlign: 'right' }}>金額</th>
              <th style={styles.th}>カテゴリ</th>
              <th style={styles.th}>メモ</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {[...transactions].reverse().map((t) => (
              <tr key={t.id} style={styles.tr}>
                <td style={styles.td}>{t.date}</td>
                <td
                  style={{
                    ...styles.td,
                    textAlign: 'right',
                    color: t.amount < 0 ? '#c00' : '#080',
                  }}
                >
                  {t.amount.toLocaleString()}
                </td>
                <td style={styles.td}>{t.category}</td>
                <td style={styles.td}>{t.memo}</td>
                <td style={styles.td}>
                  <button onClick={() => handleDelete(t.id)}>削除</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </section>
    </div>
  )
}

function ManualAddForm({
  onAdd,
}: {
  onAdd: (t: Omit<Transaction, 'id'>) => void
}) {
  const [date, setDate] = useState(() =>
    new Date().toISOString().slice(0, 10)
  )
  const [amount, setAmount] = useState('')
  const [category, setCategory] = useState('食費')
  const [memo, setMemo] = useState('')

  const submit = () => {
    const n = Number(amount)
    if (!date || Number.isNaN(n) || amount === '') {
      alert('日付と金額は必須です')
      return
    }
    onAdd({ date, amount: n, category, memo })
    setAmount('')
    setMemo('')
  }

  return (
    <section style={styles.section}>
      <h2 style={styles.h2}>手動入力</h2>
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <input
          type="date"
          value={date}
          onChange={(e) => setDate(e.target.value)}
        />
        <input
          type="number"
          placeholder="金額（支出は-）"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          style={{ width: 140 }}
        />
        <input
          type="text"
          placeholder="カテゴリ"
          value={category}
          onChange={(e) => setCategory(e.target.value)}
        />
        <input
          type="text"
          placeholder="メモ"
          value={memo}
          onChange={(e) => setMemo(e.target.value)}
          style={{ flex: 1, minWidth: 160 }}
        />
        <button onClick={submit}>追加</button>
      </div>
    </section>
  )
}

const styles: Record<string, React.CSSProperties> = {
  container: {
    maxWidth: 960,
    margin: '0 auto',
    padding: 16,
    fontFamily: 'system-ui, -apple-system, sans-serif',
    color: '#222',
  },
  h1: { fontSize: 24, margin: '8px 0 16px' },
  h2: { fontSize: 16, margin: '0 0 8px' },
  section: {
    marginBottom: 24,
    padding: 12,
    border: '1px solid #ddd',
    borderRadius: 6,
  },
  hint: { fontSize: 12, color: '#666', margin: '0 0 8px' },
  table: { borderCollapse: 'collapse', width: '100%', fontSize: 14 },
  trHead: { borderBottom: '1px solid #ccc', background: '#f7f7f7' },
  tr: { borderBottom: '1px solid #eee' },
  th: { textAlign: 'left', padding: '6px 4px' },
  td: { padding: '6px 4px' },
}
