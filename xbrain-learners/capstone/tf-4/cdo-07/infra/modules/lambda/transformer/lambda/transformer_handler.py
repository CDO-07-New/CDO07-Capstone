"""
Lambda Transformer — Kinesis → Timestream Bridge
CDO-07 · Task Force 4 · Foresight Lens

Reads raw telemetry from Kinesis Data Streams, validates the schema,
drops any PII fields (03_security_design §1.4 PII Firewall),
and writes clean records to Amazon Timestream for InfluxDB.

Telemetry Contract v1.0 schema expected from Kinesis:
  {
    "ts":          "2026-06-29T10:00:00Z",   # RFC3339 UTC  (required)
    "tenant_id":   "tnt-abc123",             # required
    "service_id":  "payment-gateway",        # required — Kinesis partition key
    "metric_type": "cpu_usage_percent",      # required
    "value":       85.5,                     # float        (required)
    "labels":      {"region": "us-east-1"}  # optional
  }

Timestream write uses measure_name = metric_type, measure_value = value.
Dimensions: service_id, tenant_id (enables per-service/tenant queries).
"""

import base64
import json
import logging
import os
import time
from typing import Any

import boto3
from botocore.config import Config

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# ---------------------------------------------------------------------------
# PII fields — must be stripped before any downstream storage (§1.4)
# ---------------------------------------------------------------------------
PII_FIELDS = frozenset(["customer_id", "email", "ip_address", "user_agent"])

# ---------------------------------------------------------------------------
# Telemetry Contract v1.0 — required fields from Kinesis payload
# ---------------------------------------------------------------------------
REQUIRED_FIELDS = {"service_id", "metric_type", "value", "ts"}

# ---------------------------------------------------------------------------
# Timestream config — injected by Terraform
# ---------------------------------------------------------------------------
TIMESTREAM_DB    = os.environ.get("TIMESTREAM_DATABASE_NAME", "")
TIMESTREAM_TABLE = os.environ.get("TIMESTREAM_TABLE_NAME", "")
AWS_REGION       = os.environ.get("AWS_REGION", "us-east-1")

# ---------------------------------------------------------------------------
# Timestream client (reused across invocations for connection pooling)
# ---------------------------------------------------------------------------
_timestream = boto3.client(
    "timestream-write",
    region_name=AWS_REGION,
    config=Config(retries={"max_attempts": 3, "mode": "standard"}),
)

# Timestream requires DescribeEndpoints first (SDK handles this automatically
# with endpoint discovery — boto3 timestream-write client does it internally).


def handler(event: dict, context: Any) -> dict:
    """Process Kinesis records, validate schema, drop PII, write to Timestream."""
    records = event.get("Records", [])
    logger.info("Received %d Kinesis records", len(records))

    timestream_records: list[dict] = []
    dropped = 0

    for record in records:
        try:
            payload = base64.b64decode(record["kinesis"]["data"])
            data = json.loads(payload)

            # --- PII Firewall: strip sensitive fields (03_security_design §1.4) ---
            for field in PII_FIELDS:
                data.pop(field, None)

            # --- Schema validation: Telemetry Contract v1.0 required fields ---
            # Accept both "ts" (contract) and legacy "timestamp" key
            if "timestamp" in data and "ts" not in data:
                data["ts"] = data.pop("timestamp")
            # Accept "metric_name" as alias for "metric_type" (legacy mock services)
            if "metric_name" in data and "metric_type" not in data:
                data["metric_type"] = data.pop("metric_name")

            if not REQUIRED_FIELDS.issubset(data.keys()):
                missing = REQUIRED_FIELDS - data.keys()
                logger.warning("Dropping record with missing fields: %s", missing)
                dropped += 1
                continue

            # --- Build Timestream record ---
            ts_record = _build_timestream_record(data)
            if ts_record:
                timestream_records.append(ts_record)
            else:
                dropped += 1

        except (json.JSONDecodeError, KeyError, ValueError) as exc:
            logger.error("Failed to decode/validate record: %s", exc)
            dropped += 1

    clean_count = len(timestream_records)
    logger.info(
        "Processed %d records: %d valid, %d dropped",
        len(records),
        clean_count,
        dropped,
    )

    # --- Write to Timestream in batches of 100 (AWS limit per WriteRecords call) ---
    written = 0
    if timestream_records and TIMESTREAM_DB and TIMESTREAM_TABLE:
        written = _write_to_timestream(timestream_records)
    elif not TIMESTREAM_DB or not TIMESTREAM_TABLE:
        logger.error(
            "TIMESTREAM_DATABASE_NAME or TIMESTREAM_TABLE_NAME not set — skipping write. "
            "Processed %d valid records locally only.",
            clean_count,
        )

    return {
        "statusCode": 200,
        "body": json.dumps({
            "received": len(records),
            "written": written,
            "dropped": dropped,
        }),
    }


# ---------------------------------------------------------------------------
# Build a single Timestream WriteRecords record from a telemetry payload
# ---------------------------------------------------------------------------
def _build_timestream_record(data: dict) -> dict | None:
    """Convert a validated telemetry dict to a Timestream record dict."""
    try:
        # Parse timestamp → epoch milliseconds
        ts_raw = data["ts"]
        time_ms = _parse_ts_to_ms(ts_raw)

        # Dimensions: service_id + tenant_id for per-service/tenant queries
        dimensions = [
            {"Name": "service_id", "Value": str(data["service_id"])},
        ]
        tenant_id = data.get("tenant_id")
        if tenant_id:
            dimensions.append({"Name": "tenant_id", "Value": str(tenant_id)})

        # Optional label dimensions (e.g. region, db_type, cache_type, queue_name)
        labels = data.get("labels") or {}
        for k, v in labels.items():
            if k not in ("service_id", "tenant_id") and v is not None:
                dimensions.append({"Name": str(k)[:256], "Value": str(v)[:2048]})

        metric_type = str(data["metric_type"])
        value = float(data["value"])

        return {
            "Dimensions": dimensions,
            "MeasureName": metric_type,
            "MeasureValue": str(value),
            "MeasureValueType": "DOUBLE",
            "Time": str(time_ms),
            "TimeUnit": "MILLISECONDS",
        }
    except (KeyError, ValueError, TypeError) as exc:
        logger.error("Failed to build Timestream record from %s: %s", data, exc)
        return None


# ---------------------------------------------------------------------------
# Parse RFC3339 / Timestream timestamp string to epoch milliseconds
# ---------------------------------------------------------------------------
def _parse_ts_to_ms(ts: str) -> int:
    """Convert RFC3339 UTC string or epoch millis string to int milliseconds."""
    # If already numeric (epoch ms or s)
    if isinstance(ts, (int, float)):
        val = int(ts)
        # If looks like epoch seconds (< 1e12), convert to ms
        return val * 1000 if val < 10**12 else val

    ts_str = str(ts).strip()

    # Timestream query returns: "2026-06-29 10:00:00.000000000"
    if " " in ts_str and "T" not in ts_str:
        ts_str = ts_str.replace(" ", "T").split(".")[0] + "Z"

    # Normalize Z → +00:00 for fromisoformat (Python 3.10 handles Z, 3.11+ also)
    ts_str = ts_str.replace("Z", "+00:00")

    from datetime import datetime, timezone
    dt = datetime.fromisoformat(ts_str)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1000)


# ---------------------------------------------------------------------------
# Write records to Timestream in batches of 100
# ---------------------------------------------------------------------------
def _write_to_timestream(records: list[dict]) -> int:
    """Batch-write records to Timestream. Returns count of successfully written records."""
    batch_size = 100  # AWS Timestream WriteRecords limit
    written = 0

    for i in range(0, len(records), batch_size):
        batch = records[i : i + batch_size]
        try:
            resp = _timestream.write_records(
                DatabaseName=TIMESTREAM_DB,
                TableName=TIMESTREAM_TABLE,
                Records=batch,
                CommonAttributes={},
            )
            records_ingested = resp.get("RecordsIngested", {})
            batch_written = records_ingested.get("Total", len(batch))
            written += batch_written
            logger.info(
                "Timestream batch %d/%d: wrote %d/%d records",
                (i // batch_size) + 1,
                -(-len(records) // batch_size),
                batch_written,
                len(batch),
            )
        except _timestream.exceptions.RejectedRecordsException as exc:
            # Some records rejected (e.g. duplicate timestamp) — log and continue
            rejected = exc.response.get("RejectedRecords", [])
            logger.warning(
                "Timestream rejected %d record(s) in batch (likely duplicate timestamps): %s",
                len(rejected),
                rejected,
            )
            written += len(batch) - len(rejected)
        except Exception as exc:
            logger.error("Timestream write_records failed for batch starting at %d: %s", i, exc)
            # Re-raise so Kinesis event source mapping can retry with bisect-on-error
            raise

    logger.info("Total written to Timestream: %d / %d", written, len(records))
    return written
