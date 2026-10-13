#!/usr/bin/env python3
"""Kinesis clickstream event simulator.

Generates realistic clickstream events with Faker and streams them to an
AWS Kinesis Data Stream via put_records. Supports a normal mode (random
users) and a fraud mode (a single user hammering the stream fast enough to
trip a ">50 clicks / 10s" detector).
"""

from __future__ import annotations

import argparse
import hashlib
import json
import random
import signal
import sys
import time
import uuid
from datetime import datetime, timezone

import boto3
from faker import Faker

fake = Faker()

# Kinesis hard limit: at most 500 records per put_records call.
MAX_RECORDS_PER_BATCH = 500

# Realistic sample data used to synthesize events.
PAGE_URLS = [
    ("/", "home"),
    ("/products", "catalog"),
    ("/products/electronics", "catalog"),
    ("/products/clothing", "catalog"),
    ("/product/12345", "product_detail"),
    ("/product/67890", "product_detail"),
    ("/cart", "cart"),
    ("/checkout", "checkout"),
    ("/checkout/payment", "checkout"),
    ("/search?q=shoes", "search"),
    ("/account", "account"),
    ("/account/orders", "account"),
    ("/login", "auth"),
    ("/blog/top-10-gadgets", "content"),
    ("/support", "support"),
]

REFERRERS = [
    "https://www.google.com/",
    "https://www.bing.com/",
    "https://t.co/",
    "https://www.facebook.com/",
    "https://www.instagram.com/",
    "direct",
    "https://newsletter.example.com/",
]

DEVICES = ["mobile", "desktop", "tablet"]
BROWSERS = ["Chrome", "Safari", "Firefox", "Edge", "Samsung Internet"]
OSES = ["iOS", "Android", "Windows", "macOS", "Linux"]
COUNTRIES = ["CH", "DE", "US", "FR", "GB"]


def hash_ip(ip: str) -> str:
    """Return a stable SHA-256 hex digest of an IP address (no raw IP stored)."""
    return hashlib.sha256(ip.encode("utf-8")).hexdigest()


def generate_event(user_id: str) -> dict:
    """Build one realistic clickstream event for the given user id."""
    page_url, page_category = random.choice(PAGE_URLS)
    return {
        "event_id": str(uuid.uuid4()),
        # ISO8601 UTC with an explicit trailing 'Z'.
        "timestamp": datetime.now(timezone.utc).replace(tzinfo=None).isoformat() + "Z",
        "user_id": user_id,
        # Short random hex session id, e.g. sess_9f3a1c...
        "session_id": f"sess_{uuid.uuid4().hex[:12]}",
        "page_url": page_url,
        "page_category": page_category,
        "event_type": "page_view",
        "referrer": random.choice(REFERRERS),
        "device": random.choice(DEVICES),
        "browser": random.choice(BROWSERS),
        "os": random.choice(OSES),
        "country": random.choice(COUNTRIES),
        "city": fake.city(),
        "ip_hash": hash_ip(fake.ipv4_public()),
    }


def pick_user_id(fraud: bool, fixed_user_id: str) -> str:
    """Return the user id to use for the next event.

    In fraud mode we always return the fixed id so a single user hammers the
    stream; in normal mode we pick a random user from a large pool.
    """
    if fraud:
        return fixed_user_id
    return f"user_{random.randint(1, 10000)}"


class Simulator:
    """Owns the Kinesis client, pacing, and cumulative counters."""

    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.client = boto3.client("kinesis", region_name=args.region)
        self.stream_name = args.stream_name
        self.sent = 0
        self.errors = 0
        self.start_time = time.monotonic()
        self._running = True

    def stop(self, *_: object) -> None:
        """Signal handler: request a clean shutdown."""
        self._running = False

    def _build_records(self, count: int) -> list[dict]:
        """Create `count` Kinesis records with the user id as PartitionKey."""
        records = []
        for _ in range(count):
            user_id = pick_user_id(self.args.fraud, self.args.user_id)
            event = generate_event(user_id)
            records.append(
                {
                    "Data": json.dumps(event).encode("utf-8"),
                    # PartitionKey = user_id keeps a user's events on one shard,
                    # which is what lets the fraud detector see them in order.
                    "PartitionKey": user_id,
                }
            )
        return records

    def _put_with_retry(self, records: list[dict]) -> None:
        """Send a batch, then retry any partially-failed records once."""
        try:
            resp = self.client.put_records(StreamName=self.stream_name, Records=records)
        except Exception as exc:  # noqa: BLE001 - surface any AWS/client error
            self.errors += len(records)
            print(f"[error] put_records failed: {exc}", file=sys.stderr)
            return

        failed_count = resp.get("FailedRecordCount", 0)
        self.sent += len(records) - failed_count

        if not failed_count:
            return

        # Collect only the records that failed for a single retry pass.
        retry_records = [
            records[i]
            for i, result in enumerate(resp.get("Records", []))
            if result.get("ErrorCode")
        ]
        print(f"[warn] {failed_count} record(s) failed, retrying once", file=sys.stderr)

        try:
            retry_resp = self.client.put_records(
                StreamName=self.stream_name, Records=retry_records
            )
        except Exception as exc:  # noqa: BLE001
            self.errors += len(retry_records)
            print(f"[error] retry put_records failed: {exc}", file=sys.stderr)
            return

        retry_failed = retry_resp.get("FailedRecordCount", 0)
        self.sent += len(retry_records) - retry_failed
        self.errors += retry_failed
        if retry_failed:
            print(
                f"[error] {retry_failed} record(s) still failed after retry",
                file=sys.stderr,
            )

    def run(self) -> None:
        """Main loop: emit `rate` events/sec, paced in one-second windows."""
        rate = self.args.rate
        duration = self.args.duration
        last_report = time.monotonic()
        last_report_sent = 0

        print(
            f"Starting simulator: stream='{self.stream_name}' "
            f"region='{self.args.region}' rate={rate}/s "
            f"mode={'FRAUD' if self.args.fraud else 'normal'}"
            + (f" user_id={self.args.user_id}" if self.args.fraud else "")
        )

        while self._running:
            window_start = time.monotonic()

            # Stop once we've run for the requested duration.
            if duration is not None and (window_start - self.start_time) >= duration:
                break

            # Emit `rate` events this second, chunked to the 500-record cap.
            remaining = rate
            while remaining > 0 and self._running:
                chunk = min(remaining, MAX_RECORDS_PER_BATCH)
                self._put_with_retry(self._build_records(chunk))
                remaining -= chunk

            # Per-second progress: totals plus the rate achieved this window.
            now = time.monotonic()
            if now - last_report >= 1.0:
                interval = now - last_report
                effective = (self.sent - last_report_sent) / interval
                print(
                    f"[progress] sent={self.sent} errors={self.errors} "
                    f"effective_rate={effective:.1f}/s"
                )
                last_report = now
                last_report_sent = self.sent

            # Sleep off the remainder of the one-second pacing window.
            elapsed = time.monotonic() - window_start
            if elapsed < 1.0:
                time.sleep(1.0 - elapsed)

        self.summary()

    def summary(self) -> None:
        """Print a final run summary."""
        total = time.monotonic() - self.start_time
        avg = self.sent / total if total > 0 else 0.0
        print("\n--- Summary ---")
        print(f"Total events sent : {self.sent}")
        print(f"Total errors      : {self.errors}")
        print(f"Elapsed seconds   : {total:.1f}")
        print(f"Average rate      : {avg:.1f}/s")


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    """Define and parse the command-line interface."""
    parser = argparse.ArgumentParser(description="Kinesis clickstream event simulator.")
    parser.add_argument(
        "--rate", type=int, default=50, help="Events per second (default: 50)."
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=None,
        help="Run duration in seconds (default: run until Ctrl+C).",
    )
    parser.add_argument(
        "--fraud",
        action="store_true",
        help="Fraud mode: a single --user-id hammers the stream.",
    )
    parser.add_argument(
        "--user-id",
        default="user_fraudster",
        help="Fixed user id used in fraud mode.",
    )
    parser.add_argument(
        "--stream-name",
        default="clickstream-events",
        help="Kinesis stream name (default: clickstream-events).",
    )
    parser.add_argument(
        "--region",
        default="eu-central-1",
        help="AWS region (default: eu-central-1).",
    )
    return parser.parse_args(argv)


def main() -> int:
    args = parse_args()
    sim = Simulator(args)
    # Clean Ctrl+C: flip the running flag and let run() print the summary.
    signal.signal(signal.SIGINT, sim.stop)
    signal.signal(signal.SIGTERM, sim.stop)
    sim.run()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
