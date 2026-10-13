"""Fraud detector Lambda: consumes Kinesis records, tracks per-user click
rates in DynamoDB, and raises SNS alerts when a threshold is exceeded."""

import base64
import json
import logging
import os
import time
from datetime import datetime, timezone

import boto3

# --- Structured JSON logging setup ---------------------------------------


class JsonFormatter(logging.Formatter):
    """Emit each log record as a single-line JSON object."""

    def format(self, record: logging.LogRecord) -> str:
        payload = {
            "level": record.levelname,
            "message": record.getMessage(),
            "logger": record.name,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
        # Merge any structured extras attached via logger.*(..., extra={"extra": {...}})
        if hasattr(record, "extra") and isinstance(record.extra, dict):
            payload.update(record.extra)
        return json.dumps(payload)


logger = logging.getLogger("fraud-detector")
if not logger.handlers:
    _handler = logging.StreamHandler()
    _handler.setFormatter(JsonFormatter())
    logger.addHandler(_handler)
logger.setLevel(logging.INFO)
logger.propagate = False  # avoid duplicate lines via the root logger

# --- AWS clients (module scope so they are reused across warm invocations) --

dynamodb = boto3.resource("dynamodb")
sns = boto3.client("sns")
cloudwatch = boto3.client("cloudwatch")

# --- Configuration from environment --------------------------------------

CLICK_COUNTS_TABLE = os.environ["CLICK_COUNTS_TABLE"]
ALERTS_TOPIC_ARN = os.environ["ALERTS_TOPIC_ARN"]
CLICKS_PER_USER_THRESHOLD = int(os.environ.get("CLICKS_PER_USER_THRESHOLD", "50"))

# TTL window: the click_count aggregate expires 10s after last write so the
# rate is measured over a rolling ~10s bucket rather than a user's lifetime.
TTL_WINDOW_SECONDS = 10

NAMESPACE = "ClickstreamAnalytics"


def _log(level: int, message: str, **fields: object) -> None:
    """Log a message with structured fields merged into the JSON output."""
    logger.log(level, message, extra={"extra": fields})


def _publish_alert(user_id: str, click_count: int, timestamp: str) -> None:
    """Publish a HIGH_CLICK_RATE alert to SNS."""
    alert = {
        "alert_type": "HIGH_CLICK_RATE",
        "user_id": user_id,
        "click_count": click_count,
        "threshold": CLICKS_PER_USER_THRESHOLD,
        "timestamp": timestamp,
    }
    sns.publish(
        TopicArn=ALERTS_TOPIC_ARN,
        Subject=f"Fraud alert: high click rate for user {user_id}",
        Message=json.dumps(alert),
    )


def handler(event: dict, context: object) -> dict:
    """Kinesis event source mapping entry point."""
    start = time.monotonic()  # wall-clock latency of the whole handler
    table = dynamodb.Table(CLICK_COUNTS_TABLE)

    events_processed = 0
    alerts_triggered = 0

    for record in event.get("Records", []):
        try:
            # Kinesis delivers the payload base64-encoded under kinesis.data.
            raw = base64.b64decode(record["kinesis"]["data"])
            payload = json.loads(raw)

            user_id = payload["user_id"]
            session_id = payload["session_id"]  # extracted per spec
        except (KeyError, ValueError, TypeError) as exc:
            # Malformed record: log and continue rather than failing the batch.
            _log(logging.WARNING, "skipping malformed record", error=str(exc))
            continue

        events_processed += 1

        ttl = int(time.time()) + TTL_WINDOW_SECONDS

        # Atomically bump the rolling click count and (re)set its TTL. ADD on a
        # missing attribute starts from 0, so the first click yields 1.
        resp = table.update_item(
            Key={"pk": f"user#{user_id}", "sk": "click_count"},
            UpdateExpression="ADD click_count :inc SET #ttl = :t",
            ExpressionAttributeNames={"#ttl": "ttl"},
            ExpressionAttributeValues={":inc": 1, ":t": ttl},
            ReturnValues="UPDATED_NEW",
        )
        # DynamoDB returns numbers as Decimal; coerce for comparison/JSON.
        click_count = int(resp["Attributes"]["click_count"])

        if click_count > CLICKS_PER_USER_THRESHOLD:
            # Debounce: alert at most once per fraud episode. We try to set an
            # "alerted" flag on the same item, conditional on it not already
            # being set. Only the FIRST click to cross the threshold in this
            # window wins the condition and publishes; every later click in the
            # same burst fails the condition and stays silent. The flag rides
            # the same TTL as the counter, so once the attack stops and the item
            # expires (>TTL_WINDOW_SECONDS with no clicks), a fresh burst is a
            # new episode and re-alerts. One email per attack, not per click.
            try:
                table.update_item(
                    Key={"pk": f"user#{user_id}", "sk": "click_count"},
                    UpdateExpression="SET alerted = :true, #ttl = :t",
                    ConditionExpression="attribute_not_exists(alerted)",
                    ExpressionAttributeNames={"#ttl": "ttl"},
                    ExpressionAttributeValues={":true": True, ":t": ttl},
                )
            except dynamodb.meta.client.exceptions.ConditionalCheckFailedException:
                # Already alerted this episode — stay quiet.
                pass
            else:
                timestamp = datetime.now(timezone.utc).isoformat()
                _publish_alert(user_id, click_count, timestamp)
                alerts_triggered += 1
                _log(
                    logging.INFO,
                    "fraud alert triggered",
                    user_id=user_id,
                    session_id=session_id,
                    click_count=click_count,
                    threshold=CLICKS_PER_USER_THRESHOLD,
                )

    latency_ms = (time.monotonic() - start) * 1000.0

    # Emit operational metrics in a single put_metric_data call.
    cloudwatch.put_metric_data(
        Namespace=NAMESPACE,
        MetricData=[
            {"MetricName": "FraudAlertsTriggered", "Value": alerts_triggered, "Unit": "Count"},
            {"MetricName": "EventsProcessed", "Value": events_processed, "Unit": "Count"},
            {"MetricName": "DetectionLatencyMs", "Value": latency_ms, "Unit": "Milliseconds"},
        ],
    )

    _log(
        logging.INFO,
        "batch complete",
        events_processed=events_processed,
        alerts_triggered=alerts_triggered,
        latency_ms=round(latency_ms, 2),
    )

    return {"statusCode": 200, "alerts": alerts_triggered}
