---
applyTo: "**/*.py"
---
# Python

Use FastAPI, pytest and uv with type hints. Pin dependencies and commit uv.lock.
Use Decimal end-to-end at precision 50 for loan calculations, ROUND_HALF_UP to cents, and fixed two-decimal JSON strings.
Keep pure monetary functions separate from HTTP handlers. Cover validation, INR grouping, structured masked logs and in-process HTTP behavior.
Run `uv run pytest` from samples/python-emi-api; never start a server to substitute for tests.
