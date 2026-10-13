"""Firehose transformation Lambda: enriches each record with a processing
timestamp and an ingest-to-process lag, then re-emits it for delivery."""

import base64
import json
from datetime import datetime, timezone


def _parse_timestamp(value: str) -> datetime:
    """Parse an ISO8601 timestamp, tolerating a trailing 'Z' (UTC)."""
    # Normalise a trailing 'Z' to '+00:00' so fromisoformat accepts it
    # consistently across runtimes.
    if value.endswith("Z"):
        value = value[:-1] + "+00:00"
    parsed = datetime.fromisoformat(value)
    # Treat naive timestamps as UTC so the subtraction below is well-defined.
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def handler(event: dict, context: object) -> dict:
    """Firehose transformation entry point."""
    output = []

    for record in event["records"]:
        record_id = record["recordId"]
        try:
            # Firehose delivers the source data base64-encoded under 'data'.
            raw = base64.b64decode(record["data"])
            payload = json.loads(raw)

            now = datetime.now(timezone.utc)
            payload["processed_at"] = now.isoformat() + "Z"

            # Lag from the event's own timestamp to processing time. Guard
            # against a missing or unparseable timestamp: leave lag unset.
            try:
                event_ts = _parse_timestamp(payload["timestamp"])
                payload["processing_lag_ms"] = int(
                    (now - event_ts).total_seconds() * 1000
                )
            except (KeyError, ValueError, TypeError):
                # Non-fatal: the record is still valid without a lag figure.
                pass

            transformed = json.dumps(payload).encode("utf-8")
            output.append(
                {
                    "recordId": record_id,
                    "result": "Ok",
                    "data": base64.b64encode(transformed).decode("utf-8"),
                }
            )
        except Exception:  # noqa: BLE001 - any per-record failure is isolated
            # Mark just this record failed; Firehose reroutes it without
            # dropping the rest of the batch.
            output.append({"recordId": record_id, "result": "ProcessingFailed"})

    return {"records": output}
