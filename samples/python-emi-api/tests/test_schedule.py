import re
from decimal import Decimal, getcontext, localcontext

import pytest
from fastapi.testclient import TestClient

from app.emi import calculate_emi
from app.main import app
from app.models import ScheduleRequest, ScheduleResponse
from app.money import round_money
from app.schedule import ScheduleError, calculate_schedule

client = TestClient(app)
LOAN = {"principal": "2500000", "annual_rate_percent": "8.5", "tenure_months": 240}


def assert_reconciles(request: ScheduleRequest, result: ScheduleResponse) -> None:
    with localcontext() as context:
        context.prec = 50
        balance = round_money(request.principal)
        principal = Decimal("0")
        payment = Decimal("0")
        interest = Decimal("0")
        prepayment = Decimal("0")
        for month, row in enumerate(result.rows, 1):
            assert row.month == month
            for field in ("payment", "principal", "interest", "prepayment", "remaining_balance"):
                value = getattr(row, field)
                assert isinstance(value, str)
                assert re.fullmatch(r"\d+\.\d{2}", value)
            assert Decimal(row.payment) == Decimal(row.principal) + Decimal(row.interest)
            assert Decimal(row.interest) == round_money(
                balance * request.annual_rate_percent / Decimal("1200")
            )
            balance -= Decimal(row.principal) + Decimal(row.prepayment)
            assert balance >= 0
            assert Decimal(row.remaining_balance) == balance
            principal += Decimal(row.principal)
            payment += Decimal(row.payment)
            interest += Decimal(row.interest)
            prepayment += Decimal(row.prepayment)

        assert balance == 0
        assert result.rows[-1].remaining_balance == "0.00"
        assert result.actual_tenure_months == len(result.rows)
        assert Decimal(result.total_principal) == principal + prepayment == round_money(request.principal)
        assert Decimal(result.total_payment) == payment + prepayment
        assert Decimal(result.total_interest) == interest
        assert Decimal(result.total_prepayment) == prepayment
        assert Decimal(result.total_payment) == Decimal(result.total_principal) + interest
        assert result.emi == calculate_emi(request).emi


@pytest.mark.parametrize(
    ("principal", "rate", "months"),
    [
        ("2500000", "8.5", 240),
        ("1000000", "10.5", 60),
        ("500000", "12", 36),
        ("1.00", "1", 12),
        ("100000000", "36", 480),
        ("10000", "10", 1),
        ("1000000.123456789012345678", "8.123456789012345678", 240),
    ],
)
def test_no_prepayment_closes_and_reconciles(
    principal: str, rate: str, months: int
) -> None:
    request = ScheduleRequest(principal=principal, annual_rate_percent=rate, tenure_months=months)
    result = calculate_schedule(request)
    assert_reconciles(request, result)
    assert result.total_prepayment == "0.00"
    assert all(row.prepayment == "0.00" for row in result.rows)
    assert result.actual_tenure_months <= months


def test_original_emi_stays_unchanged_and_prepayment_shortens_tenure() -> None:
    original = calculate_schedule(ScheduleRequest(**LOAN))
    request = ScheduleRequest(**LOAN, prepayment={"month": 12, "amount": "500000"})
    result = calculate_schedule(request)
    assert_reconciles(request, result)
    assert result.emi == original.emi == "21695.58"
    assert result.actual_tenure_months < original.actual_tenure_months
    assert Decimal(result.total_interest) < Decimal(original.total_interest)
    assert result.rows[11].prepayment == "500000.00"
    assert sum(row.prepayment != "0.00" for row in result.rows) == 1
    assert all(row.payment == result.emi for row in result.rows[:-1])


@pytest.mark.parametrize("month", [1, 240])
def test_first_and_last_month_prepayments(month: int) -> None:
    request = ScheduleRequest(**LOAN, prepayment={"month": month, "amount": "10000"})
    result = calculate_schedule(request)
    assert_reconciles(request, result)
    if month == 1:
        assert result.rows[0].prepayment == "10000.00"
    else:
        assert result.total_prepayment == "0.00"
        assert result.rows[-1].prepayment == "0.00"


def test_prepayment_is_capped_after_installment_and_closes_in_first_month() -> None:
    request = ScheduleRequest(
        principal="1000", annual_rate_percent="12", tenure_months=12,
        prepayment={"month": 1, "amount": "100000"},
    )
    result = calculate_schedule(request)
    assert_reconciles(request, result)
    assert result.actual_tenure_months == 1
    assert result.rows[0].payment == result.emi == "88.85"
    assert result.rows[0].prepayment == "921.15"
    assert result.total_payment == "1010.00"
    assert result.total_interest == "10.00"


def test_final_installment_adjusts_to_exact_remaining_balance() -> None:
    request = ScheduleRequest(principal="1", annual_rate_percent="1", tenure_months=12)
    result = calculate_schedule(request)
    assert result.emi == "0.08"
    assert result.rows[-1].payment == "0.12"
    assert result.rows[-1].principal == "0.12"
    assert result.rows[-1].remaining_balance == "0.00"
    assert_reconciles(request, result)


def test_monthly_interest_and_prepayment_round_half_up() -> None:
    request = ScheduleRequest(
        principal="100.50", annual_rate_percent="12", tenure_months=12,
        prepayment={"month": 1, "amount": "10.005"},
    )
    result = calculate_schedule(request)
    assert result.rows[0].interest == "1.01"
    assert result.rows[0].prepayment == "10.01"
    assert_reconciles(request, result)


def test_schedule_precision_is_local() -> None:
    request = ScheduleRequest(**LOAN, prepayment={"month": 12, "amount": "500000"})
    expected = calculate_schedule(request)
    original = getcontext().prec
    getcontext().prec = 10
    try:
        assert calculate_schedule(request) == expected
        assert getcontext().prec == 10
    finally:
        getcontext().prec = original


@pytest.mark.parametrize(
    "prepayment",
    [
        {"month": 0, "amount": "1"},
        {"month": 241, "amount": "1"},
        {"month": 481, "amount": "1"},
        {"month": True, "amount": "1"},
        {"month": "1", "amount": "1"},
        {"month": 1, "amount": "0"},
        {"month": 1, "amount": "-1"},
        {"month": 1, "amount": "0.001"},
        {"month": 1, "amount": "100000000.01"},
        {"month": 1, "amount": "NaN"},
        {"month": 1, "amount": "Infinity"},
        {"month": 1, "amount": True},
        {"month": 1, "amount": "1e100000"},
        {"month": 1, "amount": "1e-19"},
        {"month": 1, "amount": "1", "extra": "synthetic"},
        {"month": 1},
        {"amount": "1"},
        "invalid",
    ],
)
def test_invalid_prepayments_are_rejected_safely(prepayment: object) -> None:
    response = client.post("/emi/schedule", json={**LOAN, "prepayment": prepayment})
    assert response.status_code == 422
    assert response.json() == {"detail": "Invalid EMI request."}


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("principal", "0"),
        ("principal", "-1"),
        ("principal", "100000000.01"),
        ("annual_rate_percent", "0"),
        ("annual_rate_percent", "36.01"),
        ("tenure_months", 0),
        ("tenure_months", 481),
    ],
)
def test_original_loan_bounds_apply_to_schedule(field: str, value: object) -> None:
    response = client.post("/emi/schedule", json={**LOAN, field: value})
    assert response.status_code == 422


@pytest.mark.parametrize("principal", ["0.001", "0.01", "0.50"])
def test_zero_or_nonamortizing_rounded_emi_fails_without_looping(principal: str) -> None:
    payload = {"principal": principal, "annual_rate_percent": "36", "tenure_months": 480}
    with pytest.raises(ScheduleError):
        calculate_schedule(ScheduleRequest(**payload))
    response = client.post("/emi/schedule", json=payload)
    assert response.status_code == 422
    assert response.json() == {
        "detail": "Loan cannot be represented as an amortizing cent-denominated schedule."
    }


def test_schedule_http_contract_and_null_optional_prepayment() -> None:
    for payload in [LOAN, {**LOAN, "prepayment": None}]:
        response = client.post("/emi/schedule", json=payload)
        assert response.status_code == 200
        result = ScheduleResponse.model_validate(response.json())
        assert_reconciles(ScheduleRequest(**payload), result)
        assert result.rows[0].payment == "21695.58"
        assert result.rows[0].interest == "17708.33"
        assert result.rows[0].principal == "3987.25"
        assert result.rows[0].remaining_balance == "2496012.75"


def test_nested_numeric_prepayment_uses_exact_decimal_edge_parser(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    import app.main as main

    original = main.calculate_schedule
    captured = []

    def inspect(request: ScheduleRequest) -> ScheduleResponse:
        captured.append(request)
        return original(request)

    monkeypatch.setattr(main, "calculate_schedule", inspect)
    response = client.post(
        "/emi/schedule",
        content='{"principal":1000000.123456789012345678,'
                '"annual_rate_percent":8.123456789012345678,"tenure_months":240,'
                '"prepayment":{"month":1,"amount":1234.123456789012345678}}',
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 200
    assert captured[0].principal == Decimal("1000000.123456789012345678")
    assert captured[0].annual_rate_percent == Decimal("8.123456789012345678")
    assert captured[0].prepayment.amount == Decimal("1234.123456789012345678")
    assert response.json()["rows"][0]["prepayment"] == "1234.12"


def test_schedule_openapi_and_body_limits() -> None:
    schema = client.get("/openapi.json").json()
    operation = schema["paths"]["/emi/schedule"]["post"]
    assert operation["requestBody"]["content"]["application/json"]["schema"]["$ref"].endswith("ScheduleRequest")
    row = schema["components"]["schemas"]["ScheduleRow"]
    assert row["properties"]["payment"]["type"] == "string"
    assert client.post("/emi/schedule", content=" " * 4097,
                       headers={"content-type": "application/json"}).status_code == 413
    assert client.post("/emi/schedule", content="{",
                       headers={"content-type": "application/json"}).status_code == 400
