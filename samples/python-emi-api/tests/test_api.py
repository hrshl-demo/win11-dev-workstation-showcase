from decimal import Decimal

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.models import EmiRequest

client = TestClient(app)
VALID = {"principal": "2500000", "annual_rate_percent": "8.5", "tenure_months": 240}


def test_health() -> None:
    assert client.get("/health").json() == {"status": "ok"}


@pytest.mark.parametrize("numeric", [False, True])
def test_decimal_contract(numeric: bool) -> None:
    body = '{"principal":2500000,"annual_rate_percent":8.5,"tenure_months":240}'
    response = (
        client.post("/emi", content=body, headers={"content-type": "application/json"})
        if numeric else client.post("/emi", json=VALID)
    )
    assert response.status_code == 200
    result = response.json()
    assert result["emi"] == "21695.58"
    assert result["total_payment"] == "5206939.20"
    assert result["total_interest"] == "2706939.20"
    assert all(isinstance(value, str) for value in result.values())


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("principal", "0"), ("principal", "-1"), ("principal", "100000000.01"),
        ("principal", True), ("principal", "NaN"), ("principal", "1e100000"),
        ("principal", "1e9999999999999999999999999999999999999"),
        ("principal", "1e-19"), ("principal", "1" * 65),
        ("annual_rate_percent", "0"), ("annual_rate_percent", "36.01"),
        ("annual_rate_percent", "Infinity"), ("annual_rate_percent", "-1"),
        ("tenure_months", 0), ("tenure_months", 481), ("tenure_months", True),
        ("tenure_months", "240"), ("tenure_months", 1.5),
    ],
)
def test_bounded_validation(field: str, value: object) -> None:
    response = client.post("/emi", json={**VALID, field: value})
    assert response.status_code == 422
    assert response.json() == {"detail": "Invalid EMI request."}


@pytest.mark.parametrize("body", ['{"principal":NaN}', '{"principal":1,"principal":2}', "{"])
def test_invalid_json_is_safe(body: str) -> None:
    response = client.post("/emi", content=body, headers={"content-type": "application/json"})
    assert response.status_code == 400
    assert response.json() == {"detail": "Invalid JSON request."}


def test_unknown_fields_and_oversized_body() -> None:
    assert client.post("/emi", json={**VALID, "account": "SYN-ONLY"}).status_code == 422
    response = client.post("/emi", content=" " * 4097,
                           headers={"content-type": "application/json"})
    assert response.status_code == 413
    assert client.post("/emi", content="text").status_code == 415


def test_raw_numeric_precision_survives_edge_parse(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.main as main

    original = main.calculate_emi
    captured = []

    def inspect(request: EmiRequest):
        captured.append(request)
        return original(request)

    monkeypatch.setattr(main, "calculate_emi", inspect)
    response = client.post(
        "/emi",
        content='{"principal":1000000.123456789012345678,'
                '"annual_rate_percent":8.123456789012345678,"tenure_months":240}',
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 200
    assert captured[0].principal == Decimal("1000000.123456789012345678")
    assert captured[0].annual_rate_percent == Decimal("8.123456789012345678")
    assert client.post("/emi", json={
        "principal": "1000000.123456789012345678",
        "annual_rate_percent": "8.123456789012345678", "tenure_months": 240,
    }).json() == response.json()


def test_openapi_preserves_request_and_response_models() -> None:
    schema = client.get("/openapi.json").json()
    operation = schema["paths"]["/emi"]["post"]
    assert operation["requestBody"]["content"]["application/json"]["schema"]["$ref"].endswith("EmiRequest")
    assert schema["components"]["schemas"]["EmiResponse"]["properties"]["emi"]["type"] == "string"
    assert "/emi/schedule" in schema["paths"]


@pytest.mark.parametrize(
    "body",
    [
        '[1,2,3]',
        'null',
        '{"principal":100000000,"annual_rate_percent":36,"tenure_months":480.0}',
        '{"principal":1e100000,"annual_rate_percent":8,"tenure_months":12}',
    ],
)
def test_shape_and_raw_number_bounds(body: str) -> None:
    response = client.post("/emi", content=body, headers={"content-type": "application/json"})
    assert response.status_code == 422


def test_raw_unsupported_exponent_is_safe() -> None:
    response = client.post(
        "/emi", content='{"principal":1e99999999999999999999999999999999}',
        headers={"content-type": "application/json"},
    )
    assert response.status_code == 400


def test_internal_error_is_safe(monkeypatch: pytest.MonkeyPatch) -> None:
    import app.main as main

    def fail(request: EmiRequest):
        raise RuntimeError("Synthetic internal diagnostic ABCDE1234F")

    monkeypatch.setattr(main, "calculate_emi", fail)
    response = TestClient(app, raise_server_exceptions=False).post("/emi", json=VALID)
    assert response.status_code == 500
    assert response.json() == {"detail": "Unable to process request."}
