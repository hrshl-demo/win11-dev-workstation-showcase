---
name: extend-emi-api
description: Add and test an amortisation schedule with an optional one-time prepayment for the EMI API.
---
# Extend EMI API

1. Read samples/python-emi-api and its tests; preserve POST /emi and its fixed-decimal string contract.
2. Add POST /emi/schedule using the existing principal, annual_rate_percent and tenure_months validation. Optional prepayment has month (within tenure) and amount (positive, bounded money).
3. Keep EMI unchanged. Round each month's interest half-up to cents, apply the prepayment after that month's installment, cap it at the remaining balance and shorten tenure. Adjust the final installment to exactly close the balance; never leave a negative balance. Reject a payment that cannot cover interest rather than looping.
4. Return numbered rows containing payment, principal, interest, prepayment and remaining_balance as fixed two-decimal strings, plus actual tenure and exact totals. Bound all calculations to the original tenure.
5. Add tests for no prepayment, reduced tenure, first/last month, overpayment capping, invalid input, rounded final installment and principal/interest/payment reconciliation.
6. Run `uv run pytest` from samples/python-emi-api and fix failures. No application launches.

Done: the old contract still passes, schedule tests pass, final balance is 0.00 and totals reconcile without float money.
