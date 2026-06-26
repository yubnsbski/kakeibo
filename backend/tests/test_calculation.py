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
        self.assertEqual(result.net_amount, 1364)
        self.assertEqual(result.tax_amount, 136)
        self.assertEqual(result.amount_mode, "tax_included")

    def test_full_width_input_and_symbols(self) -> None:
        result = calculate_amount("（１００＋５０）×２", 8)
        self.assertEqual(result.amount, 300)
        self.assertEqual(result.net_amount, 278)
        self.assertEqual(result.tax_amount, 22)

    def test_unicode_minus_is_normalized(self) -> None:
        result = calculate_amount("1000−100", 10)
        self.assertEqual(result.amount, 900)

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

    def test_unknown_amount_mode_is_rejected(self) -> None:
        with self.assertRaises(PriceExpressionError):
            calculate_amount("100", 10, "unknown")  # type: ignore[arg-type]

    def test_inclusive_tax_examples(self) -> None:
        ten_percent = calculate_amount("1100", 10, "tax_included")
        self.assertEqual(ten_percent.input_amount, 1100)
        self.assertEqual(ten_percent.amount, 1100)
        self.assertEqual(ten_percent.net_amount, 1000)
        self.assertEqual(ten_percent.tax_amount, 100)

        reduced_rate = calculate_amount("1080", 8, "tax_included")
        self.assertEqual(reduced_rate.net_amount, 1000)
        self.assertEqual(reduced_rate.tax_amount, 80)

    def test_exclusive_tax_examples(self) -> None:
        ten_percent = calculate_amount("1000", 10, "tax_excluded")
        self.assertEqual(ten_percent.input_amount, 1000)
        self.assertEqual(ten_percent.net_amount, 1000)
        self.assertEqual(ten_percent.tax_amount, 100)
        self.assertEqual(ten_percent.amount, 1100)
        self.assertEqual(ten_percent.amount_mode, "tax_excluded")

        reduced_rate = calculate_amount("1000", 8, "tax_excluded")
        self.assertEqual(reduced_rate.tax_amount, 80)
        self.assertEqual(reduced_rate.amount, 1080)

    def test_exclusive_tax_is_rounded_half_up(self) -> None:
        result = calculate_amount("15", 10, "tax_excluded")
        self.assertEqual(result.tax_amount, 2)
        self.assertEqual(result.amount, 17)


if __name__ == "__main__":
    unittest.main()
