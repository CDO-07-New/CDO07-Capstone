"""
Lambda Transformer — Kinesis → Timestream for InfluxDB Bridge
CDO-07 · Task Force 4 · Foresight Lens

Reads raw telemetry from Kinesis Data Streams, validates schema per
Telemetry Contract v1.0, strips PII, then writes clean records to
Timestream for InfluxDB via the InfluxDB v2 HTTP write API (Line Protocol).

Telemetry Contract v1.0 — expected Kinesis payload:
  {
    "ts":          "2026-06-29T10:00:00Z",  # RFC3339 UTC  (required)
    "tenant_id":   "tnt-abc123",            # required
    "service_id":  "payment-gateway",       # required (Kinesis partition key)
    "metric_type": "cpu_usage_percent",     # required
    "value":       85.5,                    # float        (required)
    "labels":      {"region": "us-east-1"} # optional
  }

Line Protocol format written to InfluxDB:
  <metric_type>,service_id=<sid>,tenant_id=<tid>[,<label>=<val>] value=<v> <unix_ns>
"""

import base64
import json
import logging
import os
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from typing import Any

import boto3
from botocore.config import Config

logger = logging.getLogger()
logger.setLevel(os.environ.get("LOG_LEVEL", "INFO"))

# ---------------------------------------------------------------------------
# PII fields — stripped before any downstream storage (03_security_design §1.4)
# ---------------------------------------------------------------------------
PII_FIELDS = frozenset(["customer_id", "email", "ip_address", "user_agent"])

# ---------------------------------------------------------------------------
# Telemetry Contract v1.0 — required fields
# ---------------------------------------------------------------------------
REQUIRED_FIELDS = {"service_id", "metric_type", "value", "ts"}

# ---------------------------------------------------------------------------
# InfluxDB connection config — injected by Terraform via env vars
# ---------------------------------------------------------------------------
INFLUXDB_URL        = os.environ.get("INFLUXDB_URL", "")          # https://<host>:8086
INFLUXDB_BUCKET     = os.environ.get("INFLUXDB_BUCKET", "service-metrics")
INFLUXDB_ORG        = os.environ.get("INFLUXDB_ORG", "cdo-07")
INFLUXDB_SECRET_ARN = os.environ.get("INFLUXDB_SECRET_ARN", "")   # Secrets Manager ARN

AWS_REGION = os.environ.get("AWS_REGION", "us-east-1")

# ---------------------------------------------------------------------------
# AWS Secrets Manager client — retrieve InfluxDB operator token
# ---------------------------------------------------------------------------
_secretsmanager = boto3.client(
    "secretsmanager",
    region_name=AWS_REGION,
    config=Config(retries={"max_attempts": 3, "mode": "standard"}),
)

# Token is cached per Lambda warm instance (reset on cold start)
_influxdb_token_cache: str | None = None


def _get_influxdb_token() -> str:
    """Retrieve InfluxDB operator token from Secrets Manager (cached per warm instance)."""
    global _influxdb_token_cache
    if _influxdb_token_cache:
        return _influxdb_token_cache

    if not INFLUXDB_SECRET_ARN:
        raise RuntimeError("INFLUXDB_SECRET_ARN env var not set")

    logger.info("Fetching InfluxDB token from Secrets Manager: %s", INFLUXDB_SECRET_ARN)
    resp = _secretsmanager.get_secret_value(SecretId=INFLUXDB_SECRET_ARN)
    secret = json.loads(resp["SecretString"])

    # AWS stores token under key "operator_token" per Timestream InfluxDB docs
    token = secret.get("operator_token") or secret.get("token") or secret.get("password")
    if not token:
        raise RuntimeError(
            f"InfluxDB token not found in secret. Available keys: {list(secret.keys())}"
        )

    _influxdb_token_cache = token
    return token


# ---------------------------------------------------------------------------
# Handler
# ---------------------------------------------------------------------------
def handler(event: dict, context: Any) -> dict:
    """Process Kinesis records, validate schema, drop PII, write to InfluxDB."""
    records = event.get("Records", [])
    logger.info("Received %d Kinesis records", len(records))

    line_protocol_lines: list[str] = []
    dropped = 0

    for record in records:
        try:
            payload = base64.b64decode(record["kinesis"]["data"])
            data = json.loads(payload)

            # PII Firewall (03_security_design §1.4)
            for field in PII_FIELDS:
                data.pop(field, None)

            # Accept legacy field names for backward compat
            if "timestamp" in data and "ts" not in data:
                data["ts"] = data.pop("timestamp")
            if "metric_name" in data and "metric_type" not in data:
                data["metric_type"] = data.pop("metric_name")

            # Schema validation
            if not REQUIRED_FIELDS.issubset(data.keys()):
                missing = REQUIRED_FIELDS - data.keys()
                logger.warning("Dropping record — missing fields: %s", missing)
                dropped += 1
                continue

            line = _to_line_protocol(data)
            if line:
                line_protocol_lines.append(line)
            else:
                dropped += 1

        except (json.JSONDecodeError, KeyError, ValueError) as exc:
            logger.error("Failed to decode/validate record: %s", exc)
            dropped += 1

    clean_count = len(line_protocol_lines)
    logger.info(
        "Processed %d records: %d valid, %d dropped",
        len(records), clean_count, dropped,
    )

    written = 0
    if line_protocol_lines and INFLUXDB_URL:
        written = _write_to_influxdb(line_protocol_lines)
    elif not INFLUXDB_URL:
        logger.error("INFLUXDB_URL not set — skipping write. %d records processed locally.", clean_count)

    return {
        "statusCode": 200,
        "body": json.dumps({"received": len(records), "written": written, "dropped": dropped}),
    }


# ---------------------------------------------------------------------------
# Convert telemetry dict → InfluxDB Line Protocol string
# ---------------------------------------------------------------------------
def _to_line_protocol(data: dict) -> str | None:
    """
    Build an InfluxDB v2 line protocol string from a telemetry record.

    Format: <measurement>,<tag_key>=<tag_val>[,...] value=<float> <unix_ns>
    Example:
      cpu_usage_percent,service_id=payment-gateway,tenant_id=tnt-abc123 value=85.5 1719619200000000000
    """
    try:
        measurement = _escape_lp(str(data["metric_type"]))
        value       = float(data["value"])
        ts_ns       = _parse_ts_to_ns(data["ts"])

        # Tags — service_id and tenant_id are mandatory dimensions
        tags: list[str] = [f"service_id={_escape_lp(str(data['service_id']))}"]
        tenant_id = data.get("tenant_id")
        if tenant_id:
            tags.append(f"tenant_id={_escape_lp(str(tenant_id))}")

        # Optional label tags (region, db_type, cache_type, queue_name...)
        labels = data.get("labels") or {}
        for k, v in labels.items():
            if v is not None and k not in ("service_id", "tenant_id"):
                tags.append(f"{_escape_lp(str(k))}={_escape_lp(str(v))}")

        # Sort tags lexicographically (InfluxDB best practice for write performance)
        tags.sort()
        tag_set = ",".join(tags)

        return f"{measurement},{tag_set} value={value} {ts_ns}"

    except (KeyError, ValueError, TypeError) as exc:
        logger.error("Failed to build line protocol from %s: %s", data, exc)
        return None


def _escape_lp(s: str) -> str:
    """Escape special characters in InfluxDB line protocol tag keys/values."""
    return s.replace(" ", "\\ ").replace(",", "\\,").replace("=", "\\=")


def _parse_ts_to_ns(ts: Any) -> int:
    """Convert RFC3339 string or epoch to nanoseconds for InfluxDB line protocol."""
    if isinstance(ts, (int, float)):
        val = int(ts)
        # Epoch seconds → ns
        if val < 10**12:
            return val * 1_000_000_000
        # Epoch ms → ns
        if val < 10**15:
            return val * 1_000_000
        return val  # already ns

    ts_str = str(ts).strip()
    # Timestream query format: "2026-06-29 10:00:00.000000000"
    if " " in ts_str and "T" not in ts_str:
        ts_str = ts_str.replace(" ", "T").split(".")[0] + "Z"
    ts_str = ts_str.replace("Z", "+00:00")

    dt = datetime.fromisoformat(ts_str)
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return int(dt.timestamp() * 1_000_000_000)


# ---------------------------------------------------------------------------
# Write line protocol to InfluxDB v2 HTTP API in batches of 5000 lines
# (InfluxDB best practice: batch size 5000 per write request)
# ---------------------------------------------------------------------------
def _write_to_influxdb(lines: list[str]) -> int:
    """POST line protocol to InfluxDB /api/v2/write. Returns count written."""
    token = _get_influxdb_token()
    batch_size = 5000
    written = 0

    write_url = (
        f"{INFLUXDB_URL.rstrip('/')}/api/v2/write"
        f"?org={urllib.parse.quote(INFLUXDB_ORG)}"
        f"&bucket={urllib.parse.quote(INFLUXDB_BUCKET)}"
        f"&precision=ns"
    )

    for i in range(0, len(lines), batch_size):
        batch = lines[i : i + batch_size]
        body  = "\n".join(batch).encode("utf-8")

        req = urllib.request.Request(
            write_url,
            data=body,
            method="POST",
            headers={
                "Authorization": f"Token {token}",
                "Content-Type": "text/plain; charset=utf-8",
                "Content-Encoding": "identity",
            },
        )

        try:
            with urllib.request.urlopen(req, timeout=10) as resp:
                # HTTP 204 No Content = success
                logger.info(
                    "InfluxDB write batch %d/%d: %d lines → HTTP %d",
                    (i // batch_size) + 1,
                    -(-len(lines) // batch_size),
                    len(batch),
                    resp.status,
                )
            written += len(batch)

        except urllib.error.HTTPError as exc:
            body_err = exc.read().decode("utf-8", errors="replace")
            logger.error(
                "InfluxDB write HTTP %d: %s — re-raising for Kinesis retry",
                exc.code, body_err,
            )
            raise  # Kinesis event source mapping will retry with bisect-on-error
        except Exception as exc:
            logger.error("InfluxDB write failed: %s — re-raising for Kinesis retry", exc)
            raise

    logger.info("Total written to InfluxDB: %d / %d lines", written, len(lines))
    return written
