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
