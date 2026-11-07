from decimal import Decimal, localcontext

from app.models import EmiRequest, EmiResponse
from app.money import format_inr, money_string, round_money


def calculate_emi(request: EmiRequest) -> EmiResponse:
    with localcontext() as context:
        context.prec = 50
        monthly_rate = request.annual_rate_percent / Decimal("1200")
        growth = (Decimal("1") + monthly_rate) ** request.tenure_months
        emi = round_money(request.principal * monthly_rate * growth / (growth - 1))
        total = round_money(emi * request.tenure_months)
        interest = round_money(total - request.principal)
        return EmiResponse(
            emi=money_string(emi),
            total_payment=money_string(total),
            total_interest=money_string(interest),
            emi_inr=format_inr(emi),
            total_payment_inr=format_inr(total),
            total_interest_inr=format_inr(interest),
        )
