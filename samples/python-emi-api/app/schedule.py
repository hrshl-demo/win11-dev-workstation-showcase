from decimal import Decimal, localcontext

from app.emi import calculate_emi
from app.models import ScheduleRequest, ScheduleResponse, ScheduleRow
from app.money import money_string, round_money


class ScheduleError(ValueError):
    pass


def calculate_schedule(request: ScheduleRequest) -> ScheduleResponse:
    with localcontext() as context:
        context.prec = 50
        fixed_emi = Decimal(calculate_emi(request).emi)
        starting_principal = round_money(request.principal)
        if fixed_emi <= 0 or starting_principal <= 0:
            raise ScheduleError("Loan does not produce a positive cent-denominated schedule.")

        balance = starting_principal
        monthly_rate = request.annual_rate_percent / Decimal("1200")
        prepayment_amount = (
            round_money(request.prepayment.amount) if request.prepayment else Decimal("0")
        )
        total_payment = Decimal("0")
        total_interest = Decimal("0")
        total_prepayment = Decimal("0")
        rows = []

        for month in range(1, request.tenure_months + 1):
            interest = round_money(balance * monthly_rate)
            payoff = round_money(balance + interest)
            payment = payoff if month == request.tenure_months else min(fixed_emi, payoff)
            principal = round_money(payment - interest)
            if principal <= 0:
                raise ScheduleError("Rounded installments do not reduce principal.")
            balance = round_money(balance - principal)
            prepayment = Decimal("0")
            if request.prepayment and request.prepayment.month == month:
                prepayment = min(prepayment_amount, balance)
                balance = round_money(balance - prepayment)

            total_payment += payment + prepayment
            total_interest += interest
            total_prepayment += prepayment
            rows.append(
                ScheduleRow(
                    month=month,
                    payment=money_string(payment),
                    principal=money_string(principal),
                    interest=money_string(interest),
                    prepayment=money_string(prepayment),
                    remaining_balance=money_string(balance),
                )
            )
            if balance == 0:
                break

        return ScheduleResponse(
            emi=money_string(fixed_emi),
            rows=rows,
            actual_tenure_months=len(rows),
            total_principal=money_string(starting_principal),
            total_payment=money_string(total_payment),
            total_interest=money_string(total_interest),
            total_prepayment=money_string(total_prepayment),
        )
