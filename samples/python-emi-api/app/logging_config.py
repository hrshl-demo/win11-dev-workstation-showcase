import json
import logging
import re
import traceback
from datetime import datetime, timezone

PII_PATTERNS = (
    re.compile(r"\b[A-Z]{5}[0-9]{4}[A-Z]\b", re.IGNORECASE),
    re.compile(r"(?<!\d)\d{4}[ -]?\d{4}[ -]?\d{4}(?!\d)"),
    re.compile(r"(?<!\d)(?:\+91[ -]?)?[6-9]\d{9}(?!\d)"),
    re.compile(r"(?<!\d)\d{9,18}(?!\d)"),
)


def mask_pii(message: str) -> str:
    for pattern in PII_PATTERNS:
        message = pattern.sub("[MASKED]", message)
    return message


class PiiMaskingFilter(logging.Filter):
    def filter(self, record: logging.LogRecord) -> bool:
        record.msg = mask_pii(record.getMessage())
        record.args = ()
        return True


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        result = {
            "timestamp": datetime.fromtimestamp(record.created, timezone.utc).isoformat(),
            "level": record.levelname,
            "logger": record.name,
            "message": mask_pii(record.getMessage()),
        }
        if record.exc_info:
            result["exception"] = mask_pii(
                "".join(traceback.format_exception(*record.exc_info))
            )
        return json.dumps(result, ensure_ascii=False)


def configure_logging() -> None:
    handler = logging.StreamHandler()
    handler.addFilter(PiiMaskingFilter())
    handler.setFormatter(JsonFormatter())
    logging.getLogger().handlers = [handler]
    logging.getLogger().setLevel(logging.INFO)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers = []
        logger.propagate = True
