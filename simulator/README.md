# Clickstream Event Simulator

Generates realistic clickstream events with [Faker](https://faker.readthedocs.io/)
and streams them to an AWS Kinesis Data Stream via `put_records`.

It has two modes:

- **Normal** — random users browsing, useful for baseline traffic.
- **Fraud** — a single user id hammers the stream fast enough to trip a
  `>50 clicks / 10s` fraud detector downstream.

> **Prerequisite:** the Kinesis stream must already be deployed. The simulator
> only produces events; it does not create the stream.

## Install

Use a virtual environment so `boto3`/`faker` don't touch your system Python:

```bash
# from the simulator/ directory
python3 -m venv .venv
source .venv/bin/activate          # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Python 3.12 is expected. When you're done, `deactivate` leaves the venv.

> The `.venv/` directory is git-ignored — it never gets committed.

## AWS credentials

The simulator uses the standard AWS credential chain — no profile or keys are
hardcoded. Point it at your credentials before running:

```bash
export AWS_PROFILE=training
```

You can also use environment variables (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`,
`AWS_SESSION_TOKEN`) or an instance/role profile. The region comes from the
`--region` flag (default `eu-central-1`), not from your profile.

## Usage

### Normal mode

50 events/sec (default), run until Ctrl+C:

```bash
python simulator.py --stream-name clickstream-events --region eu-central-1
```

100 events/sec for 60 seconds:

```bash
python simulator.py --rate 100 --duration 60
```

### Fraud mode

A single user firing 200 events/sec to trip the `>50 clicks / 10s` detector:

```bash
python simulator.py --fraud --user-id user_42 --rate 200
```

## CLI reference

| Flag            | Default              | Description                                        |
| --------------- | -------------------- | -------------------------------------------------- |
| `--rate`        | `50`                 | Events per second.                                 |
| `--duration`    | *(forever)*          | Run duration in seconds; omit to run until Ctrl+C. |
| `--fraud`       | `false`              | Enable fraud mode (single user hammers stream).    |
| `--user-id`     | `user_fraudster`     | Fixed user id used in fraud mode.                  |
| `--stream-name` | `clickstream-events` | Target Kinesis stream name.                        |
| `--region`      | `eu-central-1`       | AWS region.                                        |

## Behaviour notes

- Events are batched and sent with `put_records` (max 500 records/batch).
- `PartitionKey` is the `user_id`, so a user's events land on one shard in order.
- Partial failures (`FailedRecordCount`) are logged and the failed records are
  retried once.
- Progress is logged every second (events sent, errors, effective rate).
- Ctrl+C shuts down cleanly and prints a final summary.
