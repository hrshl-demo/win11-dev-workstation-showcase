import json
import logging
import os
from decimal import Decimal, InvalidOperation
from typing import Callable

from fastapi import FastAPI, HTTPException, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from fastapi.routing import APIRoute
from starlette.responses import Response

from app.emi import calculate_emi
from app.logging_config import configure_logging
from app.models import EmiRequest, EmiResponse, ScheduleRequest, ScheduleResponse
from app.schedule import ScheduleError, calculate_schedule

MAX_BODY_BYTES = 4096
configure_logging()
logger = logging.getLogger("showcase.emi")


def reject_constant(value: str) -> None:
    raise ValueError("Non-finite JSON numbers are not supported.")


def unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate JSON property.")
        result[key] = value
    return result


class DecimalJSONRoute(APIRoute):
    def get_route_handler(self) -> Callable:
        original = super().get_route_handler()

        async def decimal_handler(request: Request) -> Response:
            if request.method == "POST":
                media_type = request.headers.get("content-type", "").split(";")[0].lower()
                if media_type != "application/json" and not (
                    media_type.startswith("application/") and media_type.endswith("+json")
                ):
                    raise HTTPException(415, "Use application/json.")
                body = bytearray()
                async for chunk in request.stream():
                    body.extend(chunk)
                    if len(body) > MAX_BODY_BYTES:
                        raise HTTPException(413, "Request body is too large.")
                try:
                    parsed = json.loads(
                        body,
                        parse_float=Decimal,
                        parse_constant=reject_constant,
                        object_pairs_hook=unique_object,
                    )
                except (ValueError, UnicodeError, RecursionError, InvalidOperation):
                    raise HTTPException(400, "Invalid JSON request.") from None
                request._body = bytes(body)
                request._json = parsed
            return await original(request)

        return decimal_handler


app = FastAPI(title="Synthetic INR EMI API", version="1.0.0")
app.router.route_class = DecimalJSONRoute


@app.exception_handler(RequestValidationError)
async def validation_error(request: Request, error: RequestValidationError) -> JSONResponse:
    return JSONResponse(status_code=422, content={"detail": "Invalid EMI request."})


@app.exception_handler(Exception)
async def internal_error(request: Request, error: Exception) -> JSONResponse:
    logger.error("EMI request failed", exc_info=error)
    return JSONResponse(status_code=500, content={"detail": "Unable to process request."})


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.post("/emi", response_model=EmiResponse)
def emi(request: EmiRequest) -> EmiResponse:
    result = calculate_emi(request)
    logger.info("Synthetic EMI calculation completed")
    return result


@app.post("/emi/schedule", response_model=ScheduleResponse)
def schedule(request: ScheduleRequest) -> ScheduleResponse:
    try:
        result = calculate_schedule(request)
    except ScheduleError:
        raise HTTPException(
            422, "Loan cannot be represented as an amortizing cent-denominated schedule."
        ) from None
    logger.info("Synthetic amortisation schedule completed")
    return result


if __name__ == "__main__":
    import uvicorn

    port = int(os.environ.get("PORT", "8080"))
    if not 1 <= port <= 65535:
        raise ValueError("PORT must be between 1 and 65535.")
    uvicorn.run("app.main:app", host="0.0.0.0", port=port, log_config=None)
