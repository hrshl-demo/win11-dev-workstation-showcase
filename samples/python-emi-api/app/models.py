import re
from decimal import Decimal, InvalidOperation
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator

DecimalInput = Annotated[Decimal, Field(gt=0, max_digits=28, decimal_places=18)]


class EmiRequest(BaseModel):
    model_config = ConfigDict(extra="forbid")

    principal: Annotated[DecimalInput, Field(le=Decimal("100000000"))]
    annual_rate_percent: Annotated[DecimalInput, Field(le=Decimal("36"))]
    tenure_months: Annotated[int, Field(strict=True, ge=1, le=480)]

    @field_validator("principal", "annual_rate_percent", mode="before")
    @classmethod
    def validate_decimal_input(cls, value: object) -> object:
        if isinstance(value, bool) or isinstance(value, float):
            raise ValueError("Use a decimal string or JSON decimal number.")
        if not isinstance(value, (str, Decimal, int)):
            raise ValueError("A decimal amount is required.")
        text = str(value)
        if len(text) > 64 or not re.fullmatch(
            r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?", text
        ):
            raise ValueError("Invalid decimal input.")
        try:
            number = Decimal(text)
        except InvalidOperation:
            raise ValueError("Invalid decimal input.") from None
        if not number.is_finite() or not -18 <= number.as_tuple().exponent <= 8:
            raise ValueError("Use a finite decimal with at most 18 decimal places.")
        return number


class EmiResponse(BaseModel):
    emi: str = Field(pattern=r"^\d+\.\d{2}$")
    total_payment: str = Field(pattern=r"^\d+\.\d{2}$")
    total_interest: str = Field(pattern=r"^-?\d+\.\d{2}$")
    emi_inr: str
    total_payment_inr: str
    total_interest_inr: str
