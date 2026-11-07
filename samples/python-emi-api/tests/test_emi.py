from decimal import Decimal, getcontext

import pytest

from app.emi import calculate_emi
from app.models import EmiRequest


@pytest.mark.parametrize(
    ("principal", "rate", "months", "expected"),
    [
        ("2500000", "8.5", 240, "21695.58"),
        ("1000000", "10.5", 60, "21493.90"),
        ("500000", "12", 36, "16607.15"),
    ],
)
def test_prescribed_emi(principal: str, rate: str, months: int, expected: str) -> None:
    result = calculate_emi(
        EmiRequest(principal=Decimal(principal), annual_rate_percent=Decimal(rate),
                   tenure_months=months)
    )
    assert result.emi == expected


def test_totals_use_rounded_emi() -> None:
    result = calculate_emi(
        EmiRequest(principal=Decimal("2500000"), annual_rate_percent=Decimal("8.5"),
                   tenure_months=240)
    )
    assert result.emi_inr == "₹21,695.58"
    assert result.total_payment == "5206939.20"
    assert result.total_interest == "2706939.20"
    assert result.total_payment_inr == "₹52,06,939.20"
    assert result.total_interest_inr == "₹27,06,939.20"


def test_precision_is_local_and_small_rates_are_finite() -> None:
    original = getcontext().prec
    getcontext().prec = 12
    try:
        result = calculate_emi(
            EmiRequest(principal=Decimal("100000000"), annual_rate_percent=Decimal("1e-18"),
                       tenure_months=480)
        )
        assert result.emi == "208333.33"
        assert getcontext().prec == 12
    finally:
        getcontext().prec = original
