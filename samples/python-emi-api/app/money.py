from decimal import Decimal, ROUND_HALF_UP, localcontext

CENT = Decimal("0.01")


def round_money(amount: Decimal) -> Decimal:
    with localcontext() as context:
        context.prec = 50
        result = amount.quantize(CENT, rounding=ROUND_HALF_UP)
        return result.copy_abs() if result.is_zero() else result


def money_string(amount: Decimal) -> str:
    return format(round_money(amount), ".2f")


def format_inr(amount: Decimal) -> str:
    rounded = round_money(amount)
    digits, fraction = format(rounded.copy_abs(), ".2f").split(".")
    if len(digits) > 3:
        leading, last = digits[:-3], digits[-3:]
        groups = []
        while leading:
            groups.insert(0, leading[-2:])
            leading = leading[:-2]
        digits = ",".join([*groups, last])
    sign = "-" if rounded < 0 else ""
    return f"{sign}₹{digits}.{fraction}"
