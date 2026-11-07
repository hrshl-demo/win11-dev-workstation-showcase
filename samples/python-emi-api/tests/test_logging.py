import io
import json
import logging

import pytest

from app.logging_config import JsonFormatter, PiiMaskingFilter, mask_pii


@pytest.mark.parametrize(
    "synthetic",
    [
        "ABCDE1234F", "abcde1234f", "0000 1111 2222", "0000-1111-2222",
        "000011112222", "9000000000", "+91 9000000000", "000000000000000001",
    ],
)
def test_synthetic_pii_is_masked(synthetic: str) -> None:
    assert mask_pii(f"synthetic={synthetic}") == "synthetic=[MASKED]"


def test_filter_formats_arguments_and_json_logs() -> None:
    output = io.StringIO()
    handler = logging.StreamHandler(output)
    handler.setFormatter(JsonFormatter())
    handler.addFilter(PiiMaskingFilter())
    logger = logging.getLogger("test.synthetic")
    logger.handlers = [handler]
    logger.propagate = False
    logger.setLevel(logging.INFO)
    try:
        logger.info("Synthetic PAN %s; mobile %s", "ABCDE1234F", "9000000000")
        result = json.loads(output.getvalue())
        assert result["message"] == "Synthetic PAN [MASKED]; mobile [MASKED]"
        assert result["level"] == "INFO"
        assert result["logger"] == "test.synthetic"
        assert result["timestamp"]
    finally:
        logger.handlers = []
        logger.propagate = True


def test_exception_text_is_masked() -> None:
    try:
        raise ValueError("Synthetic PAN ABCDE1234F")
    except ValueError:
        import sys

        record = logging.LogRecord("synthetic", logging.ERROR, "", 1, "failed", (), sys.exc_info())
    payload = JsonFormatter().format(record)
    assert "ABCDE1234F" not in payload
    assert "[MASKED]" in json.loads(payload)["exception"]
