import re
from decimal import Decimal, InvalidOperation
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

from app.money import round_money

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


class Prepayment(BaseModel):
    model_config = ConfigDict(extra="forbid")

    month: Annotated[int, Field(strict=True, ge=1, le=480)]
    amount: Annotated[DecimalInput, Field(le=Decimal("100000000"))]

    @field_validator("amount", mode="before")
    @classmethod
    def validate_amount(cls, value: object) -> object:
        return EmiRequest.validate_decimal_input(value)

    @field_validator("amount")
    @classmethod
    def validate_cent_amount(cls, value: Decimal) -> Decimal:
        if round_money(value) <= 0:
            raise ValueError("Prepayment must round to at least one paise.")
        return value


class ScheduleRequest(EmiRequest):
    prepayment: Prepayment | None = None

    @model_validator(mode="after")
    def validate_prepayment_month(self) -> "ScheduleRequest":
        if self.prepayment and self.prepayment.month > self.tenure_months:
            raise ValueError("Prepayment month must be within the original tenure.")
        return self


MoneyText = Annotated[str, Field(pattern=r"^\d+\.\d{2}$")]


class ScheduleRow(BaseModel):
    month: Annotated[int, Field(strict=True, ge=1, le=480)]
    payment: MoneyText
    principal: MoneyText
    interest: MoneyText
    prepayment: MoneyText
    remaining_balance: MoneyText


class ScheduleResponse(BaseModel):
    emi: MoneyText
    rows: Annotated[list[ScheduleRow], Field(min_length=1, max_length=480)]
    actual_tenure_months: Annotated[int, Field(strict=True, ge=1, le=480)]
    total_principal: MoneyText
    total_payment: MoneyText
    total_interest: MoneyText
    total_prepayment: MoneyText
