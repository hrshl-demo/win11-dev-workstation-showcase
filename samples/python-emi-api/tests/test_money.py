from decimal import Decimal

import pytest

from app.money import format_inr, money_string


@pytest.mark.parametrize(
    ("amount", "expected"),
    [
        ("2500000", "₹25,00,000.00"),
        ("123456789.5", "₹12,34,56,789.50"),
        ("100000", "₹1,00,000.00"),
        ("999", "₹999.00"),
        ("-1234567.8", "-₹12,34,567.80"),
        ("0", "₹0.00"),
        ("1.005", "₹1.01"),
        ("-1.005", "-₹1.01"),
        ("-0.001", "₹0.00"),
    ],
)
def test_indian_grouping(amount: str, expected: str) -> None:
    assert format_inr(Decimal(amount)) == expected


def test_fixed_decimal_string() -> None:
    assert money_string(Decimal("100")) == "100.00"
    assert money_string(Decimal("-0.001")) == "0.00"
