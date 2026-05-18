"""CSV import logic — new column contract: date,amount,category,memo.

CSV header (固定):
    date,amount,category,memo

各列:
    date     : YYYY-MM-DD (必須)
    amount   : 税込金額 int (必須, > 0)
    category : 9カテゴリのいずれか (空欄可, 空なら needs_review)
    memo     : 店舗名/メモ (空欄可)

バリデーション:
    - missing_date: date 空 or 形式不正
    - invalid_amount: amount 0以下 / 非数値 / 空
    - unknown_category: category が9カテゴリ以外 (空はOK、警告レベル)
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
    "invalid_amount": "金額は0より大きい整数を入力してください",
    "unknown_category": "不明なカテゴリです (空欄か9カテゴリのいずれか)",
}

EXPECTED_HEADER = "date,amount,category,memo"

VALID_CATEGORIES = {
    "食費", "酒類", "外食", "日用品",
    "交通費", "医療費", "娯楽費", "衣料費", "その他",
}

_DATE_RE = re.compile(r"^\d{4}-\d{2}-\d{2}$")


@dataclass
class CsvRow:
    date: str
    amount: int | None
    category: str
    memo: str
    validation_error: ValidationErrorCode | None = None
    validation_message: str | None = None


@dataclass
class CsvParseResult:
    rows: list[CsvRow]
    header_error: str | None = None
    parse_errors: list[str] = field(default_factory=list)


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
        # 4列必須, 不足分は空文字
        padded = (raw + [""] * 4)[:4]
        date_s, amount_s, category, memo = padded
        try:
            amount = int(amount_s) if amount_s.strip() else None
        except ValueError:
            amount = None
        rows.append(CsvRow(
            date=date_s.strip(),
            amount=amount,
            category=category.strip(),
            memo=memo.strip(),
        ))
    return CsvParseResult(rows=rows)


def validate_row(row: CsvRow) -> ValidationErrorCode | None:
    """1行のバリデーション."""
    # 日付
    if not row.date or not _DATE_RE.match(row.date):
        return "missing_date"
    try:
        y, m, d = row.date.split("-")
        date_type(int(y), int(m), int(d))
    except ValueError:
        return "missing_date"
    # 金額
    if row.amount is None or row.amount <= 0:
        return "invalid_amount"
    # カテゴリ (空はOK、指定があれば9カテゴリのいずれか)
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
