"""
Lambda Window Feeder — CDO-07 · Task Force 4 · Foresight Lens

EventBridge triggers this Lambda every 5 minutes.
Workflow:
  1. Check SSM inference gate (cost circuit breaker)
  2. Query Timestream for InfluxDB via Flux API for the last 2h window
  3. Map rows → AI API Contract v1.0 signal_window payload
  4. POST to AI Engine /v1/predict with required headers
  5. Write audit log to S3
  6. Publish SNS alert if AI reports anomaly=true

InfluxDB connection: HTTP API via INFLUXDB_URL (not boto3 timestream-write).
Auth token fetched from Secrets Manager (INFLUXDB_SECRET_ARN).
"""

import json
import logging
import os
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import datetime, timedelta, timezone

import boto3
import requests
from botocore.config import Config

# =================================================================
# Logging
# =================================================================
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

# =================================================================
# Environment variables — injected by Terraform
# =================================================================
REGION = os.environ.get("AWS_REGION", "us-east-1")

# InfluxDB (replaces Timestream LiveAnalytics)
INFLUXDB_URL        = os.environ.get("INFLUXDB_URL", "")
INFLUXDB_BUCKET     = os.environ.get("INFLUXDB_BUCKET", "service-metrics")
INFLUXDB_ORG        = os.environ.get("INFLUXDB_ORG", "cdo-07")
INFLUXDB_SECRET_ARN = os.environ.get("INFLUXDB_SECRET_ARN", "")
INFLUXDB_QUERY_WINDOW = os.environ.get("INFLUXDB_QUERY_WINDOW", "2h")

# AI Engine
AI_ENGINE_PREDICT_URL    = os.environ.get("AI_ENGINE_PREDICT_URL", "")
AI_ENGINE_TIMEOUT_SECONDS = int(os.environ.get("AI_ENGINE_TIMEOUT_SECONDS", "5"))

# Audit / alerts
AUDIT_S3_BUCKET   = os.environ.get("AUDIT_S3_BUCKET", "")
AUDIT_S3_PREFIX   = os.environ.get("AUDIT_S3_PREFIX", "window-feeder/")
DRIFT_ALERT_SNS_TOPIC_ARN = os.environ.get("DRIFT_ALERT_SNS_TOPIC_ARN", "")
INFERENCE_ENABLED_PARAMETER_NAME = os.environ.get("INFERENCE_ENABLED_PARAMETER_NAME", "")

# =================================================================
# AWS clients
# =================================================================
_boto_config = Config(region_name=REGION, retries={"max_attempts": 3, "mode": "standard"})
_ssm            = boto3.client("ssm",            config=_boto_config)
_secretsmanager = boto3.client("secretsmanager", config=_boto_config)
_s3             = boto3.client("s3",             config=_boto_config)
_sns            = boto3.client("sns",            config=_boto_config)

# InfluxDB token cache (reset on cold start)
_influxdb_token_cache: str | None = None


# =================================================================
# Config validation
# =================================================================
def _validate_env() -> None:
    required = [
        "AWS_REGION", "INFLUXDB_URL", "INFLUXDB_SECRET_ARN",
        "AI_ENGINE_PREDICT_URL", "AUDIT_S3_BUCKET", "AUDIT_S3_PREFIX",
        "INFERENCE_ENABLED_PARAMETER_NAME", "DRIFT_ALERT_SNS_TOPIC_ARN",
    ]
    missing = [k for k in required if not os.environ.get(k)]
    if missing:
        raise RuntimeError(f"Missing required env vars: {', '.join(missing)}")


# =================================================================
# InfluxDB token
# =================================================================
def _get_influxdb_token() -> str:
    global _influxdb_token_cache
    if _influxdb_token_cache:
        return _influxdb_token_cache
    logger.info("Fetching InfluxDB token from Secrets Manager: %s", INFLUXDB_SECRET_ARN)
    resp   = _secretsmanager.get_secret_value(SecretId=INFLUXDB_SECRET_ARN)
    secret = json.loads(resp["SecretString"])
    token  = secret.get("operator_token") or secret.get("token") or secret.get("password")
    if not token:
        raise RuntimeError(f"InfluxDB token not found. Available keys: {list(secret.keys())}")
    _influxdb_token_cache = token
    return token


# =================================================================
# Step 1 — SSM inference gate
# =================================================================
def is_inference_enabled() -> bool:
    """Returns True only when SSM parameter value == 'true'."""
    if not INFERENCE_ENABLED_PARAMETER_NAME:
        return False
    try:
        resp = _ssm.get_parameter(Name=INFERENCE_ENABLED_PARAMETER_NAME)
        enabled = resp["Parameter"]["Value"].lower() == "true"
        logger.info("Inference gate: %s", enabled)
        return enabled
    except Exception as exc:
        logger.error("Failed to read SSM parameter: %s", exc)
        return False  # fail-safe: treat as disabled


# =================================================================
# Step 2 — Query InfluxDB via Flux API
# =================================================================
def query_influxdb_metrics() -> dict:
    """
    Query the last INFLUXDB_QUERY_WINDOW of telemetry from InfluxDB using Flux.
    Returns a dict with 'rows' list compatible with _build_predict_payload().
    """
    token = _get_influxdb_token()

    # Flux query — returns all fields in the service-metrics bucket for the window
    flux_query = f"""
from(bucket: "{INFLUXDB_BUCKET}")
  |> range(start: -{INFLUXDB_QUERY_WINDOW})
  |> filter(fn: (r) => r._measurement != "")
  |> pivot(rowKey: ["_time", "service_id", "tenant_id"], columnKey: ["_field"], valueColumn: "_value")
  |> keep(columns: ["_time", "_measurement", "service_id", "tenant_id", "value"])
"""

    query_url = (
        f"{INFLUXDB_URL.rstrip('/')}/api/v2/query"
        f"?org={urllib.parse.quote(INFLUXDB_ORG)}"
    )

    req = urllib.request.Request(
        query_url,
        data=flux_query.encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Token {token}",
            "Content-Type":  "application/vnd.flux",
            "Accept":        "application/csv",
        },
    )

    logger.info("Querying InfluxDB bucket=%s window=%s", INFLUXDB_BUCKET, INFLUXDB_QUERY_WINDOW)

    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            csv_body = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        err_body = exc.read().decode("utf-8", errors="replace")
        logger.error("InfluxDB query HTTP %d: %s", exc.code, err_body)
        raise

    rows = _parse_flux_csv(csv_body)
    logger.info("InfluxDB returned %d rows", len(rows))

    return {
        "source":  "influxdb",
        "bucket":  INFLUXDB_BUCKET,
        "org":     INFLUXDB_ORG,
        "window":  INFLUXDB_QUERY_WINDOW,
        "rows":    rows,
    }


def _parse_flux_csv(csv_text: str) -> list[dict]:
    """
    Parse Flux annotated CSV response into a list of row dicts.
    Each row: {ts, service_id, tenant_id, metric_type, value}
    """
    rows: list[dict] = []
    if not csv_text.strip():
        return rows

    lines = csv_text.splitlines()
    headers: list[str] = []

    for line in lines:
        # Skip annotation rows (start with #) and empty lines
        if not line or line.startswith("#"):
            continue
        cols = line.split(",")

        # First non-annotation line is the header row
        if not headers:
            headers = cols
            continue

        if len(cols) != len(headers):
            continue

        row_dict = dict(zip(headers, cols))

        # Map InfluxDB column names → Telemetry Contract field names
        try:
            ts_raw      = row_dict.get("_time", "")
            measurement = row_dict.get("_measurement", "")
            value_raw   = row_dict.get("value", "")
            service_id  = row_dict.get("service_id", "")
            tenant_id   = row_dict.get("tenant_id", "")

            if not ts_raw or not measurement or not value_raw:
                continue

            rows.append({
                "ts":          ts_raw,
                "service_id":  service_id,
                "tenant_id":   tenant_id,
                "metric_type": measurement,
                "value":       float(value_raw),
            })
        except (ValueError, KeyError):
            continue

    return rows


# =================================================================
# Step 3 — Map rows → AI API Contract v1.0 payload
# =================================================================
def _build_predict_payload(metrics_data: dict) -> dict:
    """
    Map InfluxDB rows → POST /v1/predict request body per AI API Contract v1.0.

    Required body:
      signal_window[]: [{ts, tenant_id, service_id, metric_type, value, labels?}]
      context: {deployment_version, time_range: {start_ts, end_ts}}
    """
    rows = metrics_data.get("rows", [])
    now  = datetime.now(timezone.utc)

    signal_window: list[dict] = []
    for row in rows:
        ts_raw    = row.get("ts")
        value_raw = row.get("value")
        if not ts_raw or value_raw is None:
            continue

        # Normalize timestamp to RFC3339
        ts_str = str(ts_raw).strip()
        if not ts_str.endswith("Z") and "+" not in ts_str:
            ts_str += "Z"

        signal_window.append({
            "ts":          ts_str,
            "tenant_id":   row.get("tenant_id", "tenant-cdo-07"),
            "service_id":  row.get("service_id", "unknown"),
            "metric_type": row.get("metric_type", "unknown"),
            "value":       float(value_raw),
            "labels":      {"region": "us-east-1"},
        })

    # time_range from query window
    window_str   = INFLUXDB_QUERY_WINDOW or "2h"
    window_hours = int(window_str.replace("h", "")) if "h" in window_str else 2
    start_ts     = (now - timedelta(hours=window_hours)).isoformat()
    end_ts       = now.isoformat()

    return {
        "signal_window": signal_window,
        "context": {
            "deployment_version": os.environ.get("AWS_LAMBDA_FUNCTION_VERSION", "latest"),
            "time_range": {
                "start_ts": start_ts,
                "end_ts":   end_ts,
            },
        },
    }


# =================================================================
# Step 4 — Call AI Engine
# =================================================================
def invoke_ai_engine(metrics_data: dict) -> dict:
    """POST signal_window to AI Engine /v1/predict per AI API Contract v1.0."""
    payload = _build_predict_payload(metrics_data)

    if not payload["signal_window"]:
        logger.warning("No valid signal rows after mapping — skipping AI invoke.")
        return {"anomaly": False, "severity": 0.0, "reasoning": "No signal data."}

    logger.info("Sending %d signal rows to AI Engine at %s",
                len(payload["signal_window"]), AI_ENGINE_PREDICT_URL)

    tenant_id = payload["signal_window"][0].get("tenant_id", "tenant-cdo-07")
    headers   = {
        "Content-Type":     "application/json",
        "X-Tenant-Id":      tenant_id,       # AI API Contract: required
        "X-Correlation-Id": str(uuid.uuid4()),  # optional trace id
    }

    try:
        resp = requests.post(
            AI_ENGINE_PREDICT_URL,
            json=payload,
            headers=headers,
            timeout=AI_ENGINE_TIMEOUT_SECONDS,
        )
        resp.raise_for_status()
        logger.info("AI Engine responded HTTP %d", resp.status_code)
        return resp.json()
    except requests.exceptions.RequestException as exc:
        logger.error("Failed to invoke AI Engine: %s", exc)
        raise


# =================================================================
# Step 5 — Audit log
# =================================================================
def write_audit_log(input_data: dict, output_data: dict) -> None:
    """Write invocation audit record to S3."""
    timestamp = datetime.now(timezone.utc)
    record    = {
        "invocation_time_utc":    timestamp.isoformat(),
        "source":                 "window-feeder",
        "input_to_ai_engine":     input_data,
        "response_from_ai_engine": output_data,
    }
    s3_key = (
        f"{AUDIT_S3_PREFIX.strip('/')}/"
        f"{timestamp.strftime('%Y/%m/%d/%H-%M-%S-%f')}.json"
    )
    logger.info("Writing audit log to s3://%s/%s", AUDIT_S3_BUCKET, s3_key)
    try:
        _s3.put_object(
            Bucket=AUDIT_S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(record, indent=2),
            ContentType="application/json",
        )
    except Exception as exc:
        # Audit failure must not block the main flow
        logger.error("Failed to write audit log: %s", exc)


# =================================================================
# Step 6 — SNS anomaly alert
# =================================================================
def publish_drift_alert(ai_response: dict) -> None:
    """Publish SNS alert when AI Engine reports anomaly=true."""
    # AI API Contract v1.0: field is "anomaly" (bool), not "drift_detected"
    if not ai_response.get("anomaly", False):
        logger.info("AI Engine: anomaly=false — no alert.")
        return

    severity       = ai_response.get("severity", 0.0)
    recommendation = ai_response.get("recommendation", {})
    reasoning      = ai_response.get("reasoning", "")
    audit_id       = ai_response.get("audit_id", "")

    subject = (
        f"[DRIFT] anomaly=true severity={severity:.2f} | "
        f"{recommendation.get('action_verb','?')} {recommendation.get('target','?')}"
    )[:100]

    message = {
        "source":         "window-feeder",
        "anomaly":        True,
        "severity":       severity,
        "recommendation": recommendation,
        "reasoning":      reasoning,
        "audit_id":       audit_id,
        "function":       os.environ.get("AWS_LAMBDA_FUNCTION_NAME", "window-feeder"),
    }

    logger.warning(
        "Anomaly detected | severity=%.2f | action=%s | audit_id=%s",
        severity, recommendation.get("action_verb"), audit_id,
    )

    try:
        _sns.publish(
            TopicArn=DRIFT_ALERT_SNS_TOPIC_ARN,
            Subject=subject,
            Message=json.dumps(message, indent=2),
        )
    except Exception as exc:
        logger.error("Failed to publish SNS alert: %s", exc)


# =================================================================
# Handler
# =================================================================
def handler(event: dict, context) -> dict:
    """Lambda entry point — orchestrates the full window-feeder workflow."""
    _validate_env()
    logger.info("Window Feeder started. Event: %s", json.dumps(event))

    # Step 1: Inference gate
    if not is_inference_enabled():
        logger.warning("Inference disabled via SSM — exiting early.")
        return {"statusCode": 200, "body": "Inference disabled."}

    try:
        # Step 2: Query InfluxDB
        metrics_data = query_influxdb_metrics()
        if not metrics_data.get("rows"):
            logger.warning("No metrics data from InfluxDB — exiting.")
            return {"statusCode": 200, "body": "No metrics data."}

        # Step 3+4: Call AI Engine
        ai_response = invoke_ai_engine(metrics_data)

        # Step 5: Audit
        write_audit_log(input_data=metrics_data, output_data=ai_response)

        # Step 6: Alert
        publish_drift_alert(ai_response)

        logger.info("Window Feeder completed successfully.")
        return {"statusCode": 200, "body": json.dumps(ai_response)}

    except Exception as exc:
        logger.critical("Unhandled error in Window Feeder: %s", exc, exc_info=True)
        raise  # Let Lambda mark invocation as failed → SNS DLQ / Fail-Open Fallback
