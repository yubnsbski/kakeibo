from __future__ import annotations

import unittest

from app.calculation import (
    PriceExpressionError,
    calculate_amount,
    evaluate_price_expression,
)


class PriceExpressionTest(unittest.TestCase):
    def test_operator_precedence_and_parentheses(self) -> None:
        result = calculate_amount("1000 + (250 * 2)", 10)
        self.assertEqual(result.amount, 1500)
        self.assertEqual(result.tax_amount, 136)

    def test_full_width_input_and_symbols(self) -> None:
        result = calculate_amount("（１００＋５０）×２", 8)
        self.assertEqual(result.amount, 300)
        self.assertEqual(result.tax_amount, 22)

    def test_division_and_half_up_yen_rounding(self) -> None:
        self.assertEqual(calculate_amount("100 / 3", 0).amount, 33)
        self.assertEqual(calculate_amount("1 / 2", 0).amount, 1)

    def test_unary_operators(self) -> None:
        self.assertEqual(evaluate_price_expression("-(2-5)"), 3)

    def test_division_by_zero_is_rejected(self) -> None:
        with self.assertRaisesRegex(PriceExpressionError, "0では割れません"):
            calculate_amount("100 / (2 - 2)", 10)

    def test_code_like_input_is_rejected(self) -> None:
        for expression in ("__import__('os')", "2**8", "1e3", "[1]"):
            with self.subTest(expression=expression):
                with self.assertRaises(PriceExpressionError):
                    calculate_amount(expression, 10)

    def test_mismatched_parentheses_are_rejected(self) -> None:
        with self.assertRaises(PriceExpressionError):
            calculate_amount("(100 + 20", 10)

    def test_non_positive_result_is_rejected(self) -> None:
        with self.assertRaises(PriceExpressionError):
            calculate_amount("100 - 100", 10)

    def test_tax_rate_range_is_validated(self) -> None:
        with self.assertRaises(PriceExpressionError):
            calculate_amount("100", 101)

    def test_inclusive_tax_examples(self) -> None:
        self.assertEqual(calculate_amount("1100", 10).tax_amount, 100)
        self.assertEqual(calculate_amount("1080", 8).tax_amount, 80)


if __name__ == "__main__":
    unittest.main()
