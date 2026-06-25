"""Safe arithmetic for user-entered tax-inclusive amounts."""
from __future__ import annotations

from dataclasses import dataclass
from decimal import Decimal, InvalidOperation, ROUND_HALF_EVEN, ROUND_HALF_UP, localcontext
import unicodedata

MAX_EXPRESSION_LENGTH = 200
MAX_NESTING_DEPTH = 20


class PriceExpressionError(ValueError):
    """Raised when an amount expression is invalid or unsafe."""


@dataclass(frozen=True)
class AmountCalculation:
    amount: int
    tax_rate: int
    tax_amount: int


def normalize_price_expression(expression: str) -> str:
    """Normalize full-width input and reject everything outside the grammar."""
    normalized = unicodedata.normalize("NFKC", expression)
    normalized = normalized.replace("×", "*").replace("÷", "/")
    normalized = "".join(normalized.split())

    if not normalized:
        raise PriceExpressionError("金額式を入力してください")
    if len(normalized) > MAX_EXPRESSION_LENGTH:
        raise PriceExpressionError("金額式が長すぎます")

    allowed = set("0123456789.+-*/()")
    invalid = sorted({char for char in normalized if char not in allowed})
    if invalid:
        raise PriceExpressionError(f"使用できない文字があります: {''.join(invalid)}")

    return normalized


class _ExpressionParser:
    """Recursive-descent parser for +, -, *, / and parentheses."""

    def __init__(self, expression: str) -> None:
        self.expression = expression
        self.position = 0
        self.depth = 0

    def parse(self) -> Decimal:
        value = self._parse_expression()
        if self.position != len(self.expression):
            raise PriceExpressionError(
                f"位置{self.position + 1}付近の式を解釈できません"
            )
        return value

    def _peek(self) -> str | None:
        if self.position >= len(self.expression):
            return None
        return self.expression[self.position]

    def _consume(self, expected: str | None = None) -> str:
        char = self._peek()
        if char is None:
            raise PriceExpressionError("式が途中で終わっています")
        if expected is not None and char != expected:
            raise PriceExpressionError(f"'{expected}' が必要です")
        self.position += 1
        return char

    def _parse_expression(self) -> Decimal:
        value = self._parse_term()
        while self._peek() in {"+", "-"}:
            operator = self._consume()
            right = self._parse_term()
            value = value + right if operator == "+" else value - right
        return value

    def _parse_term(self) -> Decimal:
        value = self._parse_factor()
        while self._peek() in {"*", "/"}:
            operator = self._consume()
            right = self._parse_factor()
            if operator == "*":
                value *= right
            else:
                if right == 0:
                    raise PriceExpressionError("0では割れません")
                value /= right
        return value

    def _parse_factor(self) -> Decimal:
        char = self._peek()
        if char in {"+", "-"}:
            operator = self._consume()
            value = self._parse_factor()
            return value if operator == "+" else -value

        if char == "(":
            self.depth += 1
            if self.depth > MAX_NESTING_DEPTH:
                raise PriceExpressionError("括弧の入れ子が深すぎます")
            self._consume("(")
            value = self._parse_expression()
            if self._peek() != ")":
                raise PriceExpressionError("閉じ括弧 ')' が必要です")
            self._consume(")")
            self.depth -= 1
            return value

        return self._parse_number()

    def _parse_number(self) -> Decimal:
        start = self.position
        digit_count = 0
        dot_count = 0

        while True:
            char = self._peek()
            if char is not None and char.isdigit():
                digit_count += 1
                self.position += 1
                continue
            if char == ".":
                dot_count += 1
                if dot_count > 1:
                    raise PriceExpressionError("小数点が多すぎます")
                self.position += 1
                continue
            break

        if digit_count == 0:
            raise PriceExpressionError(f"位置{start + 1}に数値が必要です")

        token = self.expression[start:self.position]
        try:
            return Decimal(token)
        except InvalidOperation as exc:
            raise PriceExpressionError("数値を解釈できません") from exc


def evaluate_price_expression(expression: str) -> Decimal:
    normalized = normalize_price_expression(expression)
    with localcontext() as context:
        context.prec = MAX_EXPRESSION_LENGTH * 2
        value = _ExpressionParser(normalized).parse()
    if not value.is_finite():
        raise PriceExpressionError("計算結果が有限値ではありません")
    return value


def round_yen(value: Decimal) -> int:
    return int(value.to_integral_value(rounding=ROUND_HALF_UP))


def calc_tax_amount(amount_incl_tax: int, tax_rate: int) -> int:
    """Return the tax included in an integer tax-inclusive amount."""
    if amount_incl_tax <= 0 or tax_rate <= 0:
        return 0
    with localcontext() as context:
        context.prec = MAX_EXPRESSION_LENGTH * 2
        tax = Decimal(amount_incl_tax) * tax_rate / Decimal(100 + tax_rate)
        return int(tax.to_integral_value(rounding=ROUND_HALF_EVEN))


def calculate_amount(expression: str, tax_rate: int) -> AmountCalculation:
    if not 0 <= tax_rate <= 100:
        raise PriceExpressionError("税率は0〜100の整数で入力してください")

    amount = round_yen(evaluate_price_expression(expression))
    if amount <= 0:
        raise PriceExpressionError("計算結果は1円以上にしてください")

    return AmountCalculation(
        amount=amount,
        tax_rate=tax_rate,
        tax_amount=calc_tax_amount(amount, tax_rate),
    )
