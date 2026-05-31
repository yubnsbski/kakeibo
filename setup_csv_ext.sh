#!/usr/bin/env bash
# CSV取込拡張: マイナス金額対応 + カテゴリ拡張(家賃/光熱費/通信費) + 同義語マッピング.
#
# 使い方:
#   cd /workspaces/kakeibo && bash setup_csv_ext.sh

set -u
REPO=/workspaces/kakeibo
cd "$REPO"

echo "============================================================"
echo "CSV取込拡張: マイナス金額 + カテゴリ拡張"
echo "============================================================"

# ===========================================================================
# 1. database.py に新カテゴリ3種追加
# ===========================================================================
echo "==> backend/app/database.py (家賃/光熱費/通信費 追加)"
cat > backend/app/database.py <<'EOF'
"""SQLite + SQLModel database wiring with seeding."""
from __future__ import annotations
import os
from collections.abc import Generator
from pathlib import Path
from sqlmodel import Session, SQLModel, create_engine, select

_BACKEND_ROOT = Path(__file__).resolve().parent.parent
_DEFAULT_DB_PATH = _BACKEND_ROOT / "data.db"
DB_PATH = os.getenv("KAKEIBO_DB_PATH", str(_DEFAULT_DB_PATH))
DB_URL = f"sqlite:///{DB_PATH}"

engine = create_engine(DB_URL, echo=False, connect_args={"check_same_thread": False})

# (name, desc, tax_rate, sort_order, is_income)
_INITIAL_CATEGORIES = [
    # 支出 - 既存9
    ("食費", "スーパー, コンビニ, 弁当, 食品", 8, 1, False),
    ("酒類", "ビール, ワイン, 日本酒, チューハイ", 10, 2, False),
    ("外食", "レストラン, カフェ, 居酒屋", 10, 3, False),
    ("日用品", "ドラッグストア, 洗剤, トイレ, キッチン", 10, 4, False),
    ("交通費", "電車, バス, タクシー, ガソリン, 駐車場", 10, 5, False),
    ("医療費", "病院, 薬局, 医薬品, 診察", 10, 6, False),
    ("娯楽費", "書店, 映画, ゲーム, 趣味, レジャー", 10, 7, False),
    ("衣料費", "アパレル, 靴, ファッション, クリーニング", 10, 8, False),
    ("その他", "判断できないもの", 10, 9, False),
    # 支出 - 新規3
    ("家賃", "家賃, 住居費", 10, 10, False),
    ("光熱費", "電気, ガス, 水道", 10, 11, False),
    ("通信費", "スマホ, インターネット, 固定電話", 10, 12, False),
    # 収入
    ("給与", "本業の給与収入", 0, 101, True),
    ("副収入", "副業, ボーナス, 副業収入", 0, 102, True),
    ("その他収入", "還付金, 贈与, 投資収益等", 0, 103, True),
]


def create_db_and_tables() -> None:
    from . import models  # noqa: F401
    SQLModel.metadata.create_all(engine)
    _seed_categories()


def _seed_categories() -> None:
    from .models import CategoryMaster
    with Session(engine) as session:
        existing = session.exec(select(CategoryMaster)).first()
        if existing is not None:
            existing_names = {c.name for c in session.exec(select(CategoryMaster)).all()}
            for name, desc, rate, order, is_income in _INITIAL_CATEGORIES:
                if name not in existing_names:
                    session.add(CategoryMaster(
                        name=name, description=desc, tax_rate=rate,
                        sort_order=order, is_income=is_income,
                    ))
            session.commit()
            return
        for name, desc, rate, order, is_income in _INITIAL_CATEGORIES:
            session.add(CategoryMaster(
                name=name, description=desc, tax_rate=rate,
                sort_order=order, is_income=is_income,
            ))
        session.commit()


def get_session() -> Generator[Session, None, None]:
    with Session(engine) as session:
        yield session
EOF

# ===========================================================================
# 2. csv_import.py を拡張(マイナス金額対応 + カテゴリ正規化)
# ===========================================================================
echo "==> backend/app/csv_import.py (マイナス金額 + 同義語マッピング)"
cat > backend/app/csv_import.py <<'EOF'
"""CSV import logic — supports negative amounts (expense) and category aliases.

CSV header: date,amount,category,memo

金額:
    - 正数 → 収入 (tx_type=income, amount=値)
    - 負数 → 支出 (tx_type=expense, amount=abs(値))
    - 0 → invalid_amount

カテゴリ:
    - 既知カテゴリ → そのまま
    - 同義語 → 正規化 (娯楽 → 娯楽費 等)
    - 不明 → unknown_category (needs_review で取込)
    - 空 → needs_review で取込
"""
from __future__ import annotations

import csv
import io
import re
from dataclasses import dataclass, field
from datetime import date as date_type
from typing import Literal

ValidationErrorCode = Literal[
    "missing_date", "invalid_amount", "unknown_category",
]

VALIDATION_MESSAGES: dict[ValidationErrorCode, str] = {
    "missing_date": "日付はYYYY-MM-DD形式で入力してください",
    "invalid_amount": "金額は0以外の整数を入力してください",
    "unknown_category": "不明なカテゴリです (空欄か既知カテゴリのいずれか)",
}

EXPECTED_HEADER = "date,amount,category,memo"

# 支出カテゴリ12種 + 収入カテゴリ3種
VALID_CATEGORIES = {
    # 支出 12
    "食費", "酒類", "外食", "日用品",
    "交通費", "医療費", "娯楽費", "衣料費", "その他",
    "家賃", "光熱費", "通信費",
    # 収入 3
    "給与", "副収入", "その他収入",
}

# 同義語マッピング
CATEGORY_ALIASES: dict[str, str] = {
    # 支出 同義語
    "娯楽": "娯楽費",
    "医療": "医療費",
    "衣服": "衣料費",
    "衣類": "衣料費",
    "ファッション": "衣料費",
    "外食費": "外食",
    "食事": "食費",
    "食料": "食費",
    "食品": "食費",
    "雑費": "その他",
    "ドラッグ": "日用品",
    "電気代": "光熱費",
    "ガス代": "光熱費",
    "水道代": "光熱費",
    "電気": "光熱費",
    "ガス": "光熱費",
    "水道": "光熱費",
    "スマホ": "通信費",
    "携帯": "通信費",
    "インターネット": "通信費",
    "住居費": "家賃",
    # 収入 同義語
    "収入": "給与",
    "副業": "副収入",
    "ボーナス": "副収入",
    "賞与": "副収入",
    "還付金": "その他収入",
    "投資": "その他収入",
}

INCOME_CATEGORIES = {"給与", "副収入", "その他収入"}

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


@dataclass
class CsvRow:
    date: str
    amount: int | None         # 絶対値 (符号は tx_type で表現)
    tx_type: str               # "expense" or "income"
    category: str              # 正規化後カテゴリ
    category_raw: str          # 元のカテゴリ名
    memo: str
    validation_error: ValidationErrorCode | None = None
    validation_message: str | None = None


@dataclass
class CsvParseResult:
    rows: list[CsvRow]
    header_error: str | None = None
    parse_errors: list[str] = field(default_factory=list)


def normalize_category(raw: str) -> str:
    """カテゴリ名を正規化. 同義語は変換、既知カテゴリはそのまま."""
    raw = raw.strip()
    if not raw:
        return ""
    if raw in VALID_CATEGORIES:
        return raw
    if raw in CATEGORY_ALIASES:
        return CATEGORY_ALIASES[raw]
    return raw  # 不明 (validate でエラー)


def parse_csv(csv_text: str) -> CsvParseResult:
    """CSVテキストをパース."""
    lines = [ln for ln in csv_text.splitlines() if ln.strip()]
    if not lines:
        return CsvParseResult(rows=[])

    header = lines[0].strip()
    if header != EXPECTED_HEADER:
        return CsvParseResult(
            rows=[],
            header_error=f"invalid CSV header. expected: {EXPECTED_HEADER}, got: {header}",
        )

    rows: list[CsvRow] = []
    reader = csv.reader(io.StringIO("\n".join(lines[1:])))
    for raw in reader:
        padded = (raw + [""] * 4)[:4]
        date_s, amount_s, category_raw, memo = [s.strip() for s in padded]

        # 金額をパース (マイナスOK)
        try:
            raw_amount = int(amount_s.replace(",", "")) if amount_s.strip() else None
        except ValueError:
            raw_amount = None

        # 符号で expense/income 判別
        if raw_amount is None:
            tx_type = "expense"
            abs_amount = None
        elif raw_amount > 0:
            tx_type = "income"
            abs_amount = raw_amount
        elif raw_amount < 0:
            tx_type = "expense"
            abs_amount = -raw_amount
        else:  # 0
            tx_type = "expense"
            abs_amount = 0

        # カテゴリ正規化
        category = normalize_category(category_raw)

        rows.append(CsvRow(
            date=date_s,
            amount=abs_amount,
            tx_type=tx_type,
            category=category,
            category_raw=category_raw,
            memo=memo,
        ))
    return CsvParseResult(rows=rows)


def validate_row(row: CsvRow) -> ValidationErrorCode | None:
    """1行のバリデーション."""
    if not row.date or not _DATE_RE.match(row.date):
        return "missing_date"
    try:
        y, m, d = row.date.split("-")
        date_type(int(y), int(m), int(d))
    except ValueError:
        return "missing_date"
    if row.amount is None or row.amount <= 0:
        return "invalid_amount"
    if row.category and row.category not in VALID_CATEGORIES:
        return "unknown_category"
    return None


def validate_all(rows: list[CsvRow]) -> list[CsvRow]:
    for row in rows:
        err = validate_row(row)
        if err:
            row.validation_error = err
            row.validation_message = VALIDATION_MESSAGES[err]
    return rows
EOF

# ===========================================================================
# 3. routers/csv_import.py を tx_type 対応に
# ===========================================================================
echo "==> backend/app/routers/csv_import.py (tx_type 対応)"
cat > backend/app/routers/csv_import.py <<'EOF'
"""CSV import API — supports expense/income via signed amount."""
from __future__ import annotations

from datetime import date as date_type
from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session

from app.csv_import import (
    CsvRow, ValidationErrorCode, parse_csv, validate_all,
    VALID_CATEGORIES, INCOME_CATEGORIES,
)
from app.database import get_session
from app.models import CategoryMaster, Transaction, calc_tax_amount

router = APIRouter(prefix="/api/csv", tags=["csv"])

_MAX_BYTES = 5 * 1024 * 1024


class CsvPreviewRow(BaseModel):
    date: str
    amount: int | None
    tx_type: str
    category: str
    category_raw: str
    memo: str
    validation_error: ValidationErrorCode | None = None
    validation_message: str | None = None


class CsvPreviewResponse(BaseModel):
    total: int
    error_count: int
    rows: list[CsvPreviewRow]
    header_error: str | None = None


class CsvCommitResponse(BaseModel):
    inserted: int
    skipped: int
    error_count: int


def _tax_rate_for(category: str | None, session: Session) -> int:
    if category is None or not category:
        return 10
    row = session.get(CategoryMaster, category)
    return row.tax_rate if row else 10


async def _read_csv(file: UploadFile) -> str:
    data = await file.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty file")
    if len(data) > _MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"too large: {len(data)} bytes")
    try:
        return data.decode("utf-8-sig")
    except UnicodeDecodeError:
        try:
            return data.decode("cp932")
        except UnicodeDecodeError as e:
            raise HTTPException(status_code=400, detail=f"decode failed: {e}") from e


@router.post("/preview", response_model=CsvPreviewResponse)
async def preview_csv(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    text = await _read_csv(file)
    parsed = parse_csv(text)
    if parsed.header_error:
        return CsvPreviewResponse(
            total=0, error_count=0, rows=[], header_error=parsed.header_error,
        )
    rows = validate_all(parsed.rows)
    err_count = sum(1 for r in rows if r.validation_error)
    return CsvPreviewResponse(
        total=len(rows),
        error_count=err_count,
        rows=[CsvPreviewRow(
            date=r.date, amount=r.amount, tx_type=r.tx_type,
            category=r.category, category_raw=r.category_raw, memo=r.memo,
            validation_error=r.validation_error,
            validation_message=r.validation_message,
        ) for r in rows],
    )


@router.post("/commit", response_model=CsvCommitResponse)
async def commit_csv(
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
):
    text = await _read_csv(file)
    parsed = parse_csv(text)
    if parsed.header_error:
        raise HTTPException(status_code=400, detail=parsed.header_error)

    rows = validate_all(parsed.rows)
    inserted = 0
    err_count = 0
    for row in rows:
        # 致命的エラーはスキップ
        if row.validation_error in ("missing_date", "invalid_amount"):
            err_count += 1
            continue

        # unknown_category → needs_review=true で取込 (カテゴリは空にする)
        if row.validation_error == "unknown_category":
            err_count += 1
            category = None
            needs_review = True
        elif not row.category:
            category = None
            needs_review = True
        else:
            category = row.category
            needs_review = False

        # tx_type 整合性チェック: 収入カテゴリなのに expense なら income に上書き
        # (ユーザー意図優先で symbol > category)
        # ただし category が income カテゴリで amount が正数なら income にすべき
        # 既に parser で符号で判定済みなので、ここでは尊重

        rate = _tax_rate_for(category, session)
        merchant = row.memo or "(空)"
        tx = Transaction(
            merchant_raw=merchant,
            merchant_normalized=merchant,
            items_text="",
            screening_category=category,
            needs_review=needs_review,
            reason=row.validation_error or "csv_import",
            confidence=1.0 if not needs_review else 0.0,
            amount=row.amount or 0,
            tax_amount=calc_tax_amount(row.amount or 0, rate),
            tx_type=row.tx_type,
            purchased_at=date_type.fromisoformat(row.date),
            memo=row.memo or None,
            status="manually_added",
        )
        session.add(tx)
        inserted += 1
    session.commit()
    return CsvCommitResponse(inserted=inserted, skipped=0, error_count=err_count)
EOF

# ===========================================================================
# 4. tests 更新
# ===========================================================================
echo "==> backend/tests/test_csv_import.py"
cat > backend/tests/test_csv_import.py <<'EOF'
"""CSV取込テスト (マイナス金額 + カテゴリ拡張対応)."""
from __future__ import annotations
from app.csv_import import EXPECTED_HEADER, parse_csv, validate_all, normalize_category


def _make_csv(*rows: str) -> str:
    return EXPECTED_HEADER + "\n" + "\n".join(rows)


def test_negative_amount_expense():
    """負数 → expense + abs(amount)."""
    csv = _make_csv("2026-05-15,-620,食費,セブン")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].tx_type == "expense"
    assert rows[0].amount == 620


def test_positive_amount_income():
    """正数 → income."""
    csv = _make_csv("2026-05-15,250000,給与,会社")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].tx_type == "income"
    assert rows[0].amount == 250000


def test_zero_amount_invalid():
    csv = _make_csv("2026-05-15,0,食費,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "invalid_amount"


def test_category_alias_娯楽():
    """娯楽 → 娯楽費."""
    csv = _make_csv("2026-05-15,-1000,娯楽,本")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "娯楽費"
    assert rows[0].category_raw == "娯楽"


def test_category_alias_医療():
    csv = _make_csv("2026-05-15,-1000,医療,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].category == "医療費"


def test_new_category_家賃():
    """家賃が既知カテゴリとして通る."""
    csv = _make_csv("2026-05-15,-85000,家賃,5月分")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "家賃"


def test_new_category_光熱費():
    csv = _make_csv("2026-05-15,-12500,光熱費,電気代")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "光熱費"


def test_new_category_通信費():
    csv = _make_csv("2026-05-15,-8900,通信費,スマホ")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "通信費"


def test_income_alias_収入():
    """収入 → 給与 (デフォルト)."""
    csv = _make_csv("2026-05-15,250000,収入,給与")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].category == "給与"
    assert rows[0].tx_type == "income"


def test_income_alias_副業():
    csv = _make_csv("2026-05-15,30000,副業,フリーランス")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].category == "副収入"


def test_unknown_category_kept():
    """不明カテゴリは unknown_category エラー (空欄で取込)."""
    csv = _make_csv("2026-05-15,-500,謎,")
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error == "unknown_category"


def test_comma_amount():
    """カンマ区切り 1,200 → 1200."""
    csv = _make_csv('"2026-05-15","-1,200","食費","ランチ"')
    rows = validate_all(parse_csv(csv).rows)
    assert rows[0].validation_error is None
    assert rows[0].amount == 1200
    assert rows[0].tx_type == "expense"


def test_normalize_category_function():
    """normalize_category 関数の単体テスト."""
    assert normalize_category("食費") == "食費"
    assert normalize_category("娯楽") == "娯楽費"
    assert normalize_category("不明XX") == "不明XX"
    assert normalize_category("") == ""
    assert normalize_category("  食費  ") == "食費"
EOF

# ===========================================================================
# 5. frontend/src/api.ts に tx_type, category_raw 追加
# ===========================================================================
echo "==> frontend/src/api.ts (CsvPreviewRow に tx_type, category_raw 追加)"
python3 <<'PYEOF'
from pathlib import Path
p = Path("frontend/src/api.ts")
text = p.read_text(encoding="utf-8")

old = """export interface CsvPreviewRow {
  date: string;
  amount: number | null;
  category: string;
  memo: string;
  validation_error: string | null;
  validation_message: string | null;
}"""
new = """export interface CsvPreviewRow {
  date: string;
  amount: number | null;
  tx_type: string;
  category: string;
  category_raw: string;
  memo: string;
  validation_error: string | null;
  validation_message: string | null;
}"""
if old in text:
    text = text.replace(old, new)
    p.write_text(text, encoding="utf-8")
    print("  api.ts CsvPreviewRow 更新")
else:
    print("  api.ts: 既存パターン不在")
PYEOF

# ===========================================================================
# 6. frontend/src/components/CsvImportCard.tsx を tx_type/正規化対応に
# ===========================================================================
echo "==> frontend/src/components/CsvImportCard.tsx"
cat > frontend/src/components/CsvImportCard.tsx <<'EOF'
import { useState } from "react";
import { previewCsv, commitCsv } from "../api";
import type { CsvPreviewResponse } from "../api";

interface Props {
  onImported: () => void;
}

export function CsvImportCard({ onImported }: Props) {
  const [file, setFile] = useState<File | null>(null);
  const [preview, setPreview] = useState<CsvPreviewResponse | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [importResult, setImportResult] = useState<string | null>(null);

  async function handlePreview() {
    if (!file) { setError("CSV未選択"); return; }
    setError(null); setImportResult(null); setBusy(true);
    try {
      setPreview(await previewCsv(file));
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  async function handleCommit() {
    if (!file) return;
    if (!confirm(`${preview?.total ?? 0}件を取り込みますか?`)) return;
    setBusy(true);
    try {
      const r = await commitCsv(file);
      setImportResult(`取込完了: ${r.inserted}件 (エラー${r.error_count}件)`);
      setPreview(null); setFile(null);
      onImported();
    } catch (e) { setError(String(e)); }
    finally { setBusy(false); }
  }

  return (
    <div className="card">
      <h2>CSV 一括取込</h2>
      <p className="hint">
        ヘッダ: <code>date,amount,category,memo</code><br />
        金額: 負数=支出 / 正数=収入<br />
        例: <code>2026-05-15,-620,食費,セブン</code> / <code>2026-05-25,250000,給与,会社</code>
      </p>
      <input type="file" accept=".csv,text/csv" onChange={(e) => {
        setFile(e.target.files?.[0] || null);
        setPreview(null);
        setImportResult(null);
      }} />
      <button onClick={handlePreview} disabled={busy || !file}>プレビュー</button>
      {error && <p className="err">{error}</p>}
      {importResult && <p style={{ color: "#1a7f37" }}>{importResult}</p>}

      {preview?.header_error && (
        <p className="err">ヘッダエラー: {preview.header_error}</p>
      )}

      {preview && !preview.header_error && (
        <div className="csv-preview">
          <p>
            総件数: <b>{preview.total}</b> /
            エラー件数: <b className={preview.error_count > 0 ? "err" : ""}>{preview.error_count}</b>
          </p>
          <div style={{ maxHeight: 320, overflowY: "auto" }}>
            <table className="tx-table" style={{ fontSize: "0.82em" }}>
              <thead>
                <tr>
                  <th>日付</th>
                  <th>種別</th>
                  <th style={{ textAlign: "right" }}>金額</th>
                  <th>カテゴリ</th>
                  <th>メモ</th>
                  <th>状態</th>
                </tr>
              </thead>
              <tbody>
                {preview.rows.map((row, i) => (
                  <tr key={i} className={row.validation_error ? "needs-review" : ""}>
                    <td>{row.date}</td>
                    <td>
                      <span style={{
                        color: row.tx_type === "income" ? "#1a7f37" : "#cf222e",
                        fontWeight: "bold",
                      }}>
                        {row.tx_type === "income" ? "収入" : "支出"}
                      </span>
                    </td>
                    <td style={{ textAlign: "right" }}>
                      {row.amount?.toLocaleString() ?? "-"}
                    </td>
                    <td>
                      {row.category || "(空)"}
                      {row.category && row.category !== row.category_raw && (
                        <small style={{ color: "#57606a" }}> ←{row.category_raw}</small>
                      )}
                    </td>
                    <td>{row.memo || "-"}</td>
                    <td>
                      {row.validation_error
                        ? <span className="badge review">{row.validation_message}</span>
                        : <span className="badge ok">OK</span>}
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
          <div className="actions" style={{ marginTop: 12 }}>
            <button onClick={handleCommit} disabled={busy}>取込実行</button>
          </div>
        </div>
      )}
    </div>
  );
}
EOF

# ===========================================================================
# 7. DB migration: 新カテゴリを追加 + tx_type 列確認
# ===========================================================================
echo ""
echo "==> data.db に新カテゴリ追加"
python3 <<'PYEOF'
import sqlite3, os
db = "/workspaces/kakeibo/backend/data.db"
if not os.path.exists(db):
    print("  data.db 不在、初回起動時に作成される")
else:
    con = sqlite3.connect(db)
    cur = con.cursor()
    NEW_CATS = [
        ("家賃", "家賃, 住居費", 10, 10, False),
        ("光熱費", "電気, ガス, 水道", 10, 11, False),
        ("通信費", "スマホ, インターネット, 固定電話", 10, 12, False),
    ]
    for name, desc, rate, order, is_income in NEW_CATS:
        try:
            cur.execute(
                "INSERT INTO category_master (name, description, tax_rate, sort_order, is_income) VALUES (?, ?, ?, ?, ?)",
                (name, desc, rate, order, 1 if is_income else 0)
            )
            print(f"  カテゴリ追加: {name}")
        except sqlite3.IntegrityError:
            print(f"  カテゴリ既存: {name}")
    con.commit()
    con.close()
PYEOF

# ===========================================================================
# 8. backend pytest
# ===========================================================================
echo ""
echo "==> pytest"
cd backend && uv run pytest tests/test_csv_import.py -v 2>&1 | tail -25
cd "$REPO"

# ===========================================================================
# 9. uvicorn 再起動
# ===========================================================================
echo ""
echo "==> uvicorn 再起動"
pkill -9 -f uvicorn 2>/dev/null || true
sleep 2
(cd /workspaces/kakeibo/backend && nohup uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 > /tmp/uvicorn.log 2>&1 &)
sleep 5

echo ""
echo "==> health"
curl -s http://localhost:8000/api/health; echo

echo ""
echo "==> カテゴリ一覧 (全15種)"
curl -s http://localhost:8000/api/categories | python3 -c "
import sys, json
data = json.load(sys.stdin)
print(f'  全{len(data)}カテゴリ')
for c in data:
    kind = '収入' if c['is_income'] else '支出'
    print(f'    [{kind}] {c[\"name\"]} ({c[\"tax_rate\"]}%)')
"

cat <<EOM

============================================================
CSV取込拡張 完了.

新機能:
  - マイナス金額 → expense, abs(amount)
  - プラス金額 → income, amount
  - 新カテゴリ: 家賃, 光熱費, 通信費
  - 同義語マッピング: 娯楽→娯楽費, 医療→医療費, 収入→給与, 等

確認手順:
  1. ブラウザで Ctrl+Shift+R
  2. 取込タブ → CSV取込で kakeibo-2026-05-16.csv をアップロード
  3. プレビュー → 49件 OK, エラー0件 期待
  4. 取込実行 → inserted=49件 期待
  5. グラフタブで収支サマリーに収入(305000円) + 支出 反映
============================================================
EOM
