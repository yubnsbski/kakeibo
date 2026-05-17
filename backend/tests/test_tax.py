"""Tax calculation tests."""
import pytest
from app.models import calc_tax_amount


@pytest.mark.parametrize("amount, rate, expected", [
    (620, 8, 46), (1080, 8, 80), (1100, 10, 100), (550, 10, 50),
    (0, 10, 0), (-100, 10, 0), (1000, 0, 0), (1000, -5, 0),
])
def test_calc_tax_amount(amount, rate, expected):
    assert calc_tax_amount(amount, rate) == expected
