# lambda/window-feeder/app.py

import csv
import io
import json
import logging
import os
import re
import uuid
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

import boto3
from botocore.config import Config

LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

REGION = os.environ.get("AWS_REGION", "us-east-1")
INFLUXDB_URL = os.environ.get("INFLUXDB_URL")
INFLUXDB_BUCKET = os.environ.get("INFLUXDB_BUCKET")
INFLUXDB_ORG = os.environ.get("INFLUXDB_ORG")
INFLUXDB_SECRET_ARN = os.environ.get("INFLUXDB_SECRET_ARN")
INFLUXDB_QUERY_WINDOW = os.environ.get("INFLUXDB_QUERY_WINDOW")
METRIC_WINDOW_STEP_SECONDS = int(os.environ.get("METRIC_WINDOW_STEP_SECONDS", "300"))
FORWARD_FILL_LOOKBACK_SECONDS = int(os.environ.get("FORWARD_FILL_LOOKBACK_SECONDS", "900"))
AI_ENGINE_PREDICT_URL = os.environ.get("AI_ENGINE_PREDICT_URL")
AI_ENGINE_TIMEOUT_SECONDS = int(os.environ.get("AI_ENGINE_TIMEOUT_SECONDS", "5"))
DEPLOYMENT_VERSION = os.environ.get("DEPLOYMENT_VERSION")
INFERENCE_ENABLED_PARAMETER_NAME = os.environ.get("INFERENCE_ENABLED_PARAMETER_NAME")
DRIFT_ALERT_SNS_TOPIC_ARN = os.environ.get("DRIFT_ALERT_SNS_TOPIC_ARN")

# Client = Đối tượng trong code để gọi API của 1 AWS service
boto_config = Config(
    region_name=REGION,
    retries={"max_attempts": 3, "mode": "standard"},
)
ssm_client = boto3.client("ssm", config=boto_config)
secretsmanager_client = boto3.client("secretsmanager", config=boto_config)
sns_client = boto3.client("sns", config=boto_config)

_influxdb_token_cache = None


# 1. Liệt kê các biến môi trường bắt buộc
# 2. Kiểm tra biến nào thiếu thì fail sớm
# 3. Đọc env vars và gán vào biến global để Lambda dùng
def load_config():
    """Reload Lambda runtime configuration from environment variables."""
    global REGION
    global INFLUXDB_URL, INFLUXDB_BUCKET, INFLUXDB_ORG, INFLUXDB_SECRET_ARN, INFLUXDB_QUERY_WINDOW
    global METRIC_WINDOW_STEP_SECONDS, FORWARD_FILL_LOOKBACK_SECONDS
    global AI_ENGINE_PREDICT_URL, AI_ENGINE_TIMEOUT_SECONDS, DEPLOYMENT_VERSION
    global INFERENCE_ENABLED_PARAMETER_NAME, DRIFT_ALERT_SNS_TOPIC_ARN

    required = [
        "AWS_REGION",
        "INFLUXDB_URL",
        "INFLUXDB_BUCKET",
        "INFLUXDB_ORG",
        "INFLUXDB_SECRET_ARN",
        "INFLUXDB_QUERY_WINDOW",
        "METRIC_WINDOW_STEP_SECONDS",
        "FORWARD_FILL_LOOKBACK_SECONDS",
        "AI_ENGINE_PREDICT_URL",
        "AI_ENGINE_TIMEOUT_SECONDS",
        "DEPLOYMENT_VERSION",
        "INFERENCE_ENABLED_PARAMETER_NAME",
        "DRIFT_ALERT_SNS_TOPIC_ARN",
    ]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

    REGION = os.environ["AWS_REGION"]
    INFLUXDB_URL = os.environ["INFLUXDB_URL"]
    INFLUXDB_BUCKET = os.environ["INFLUXDB_BUCKET"]
    INFLUXDB_ORG = os.environ["INFLUXDB_ORG"]
    INFLUXDB_SECRET_ARN = os.environ["INFLUXDB_SECRET_ARN"]
    INFLUXDB_QUERY_WINDOW = os.environ["INFLUXDB_QUERY_WINDOW"]
    METRIC_WINDOW_STEP_SECONDS = int(os.environ["METRIC_WINDOW_STEP_SECONDS"])
    FORWARD_FILL_LOOKBACK_SECONDS = int(os.environ["FORWARD_FILL_LOOKBACK_SECONDS"])
    AI_ENGINE_PREDICT_URL = os.environ["AI_ENGINE_PREDICT_URL"]
    AI_ENGINE_TIMEOUT_SECONDS = int(os.environ["AI_ENGINE_TIMEOUT_SECONDS"])
    DEPLOYMENT_VERSION = os.environ["DEPLOYMENT_VERSION"]
    INFERENCE_ENABLED_PARAMETER_NAME = os.environ["INFERENCE_ENABLED_PARAMETER_NAME"]
    DRIFT_ALERT_SNS_TOPIC_ARN = os.environ["DRIFT_ALERT_SNS_TOPIC_ARN"]

# Hàm này gọi tới SSM Parameter Store để check xem cái biến Chạy dự báo true hay false
def is_inference_enabled() -> bool:
    """Read the operational inference gate from SSM Parameter Store."""
    load_config()
    try:
        logger.info("Checking SSM parameter: %s", INFERENCE_ENABLED_PARAMETER_NAME)
        parameter = ssm_client.get_parameter(Name=INFERENCE_ENABLED_PARAMETER_NAME)
        is_enabled = parameter["Parameter"]["Value"].lower() == "true"
        logger.info("Inference enabled status: %s", is_enabled)
        return is_enabled
    except Exception as exc:
        logger.error("Failed to read SSM parameter: %s", exc)
        return False

# Hàm này lấy token kết nối InfluxDB từ AWS Secrets Manager + Cache token nào vào memory
def _get_influxdb_token() -> str:
    global _influxdb_token_cache
    load_config()
    if _influxdb_token_cache:
        return _influxdb_token_cache

    response = secretsmanager_client.get_secret_value(SecretId=INFLUXDB_SECRET_ARN)
    secret = response.get("SecretString")
    if not secret:
        raise RuntimeError("InfluxDB secret does not contain SecretString")

    token = secret
    try:
        payload = json.loads(secret)
        for key in ("token", "operatorToken", "operator_token", "authToken", "auth_token"):
            if payload.get(key):
                token = payload[key]
                break
    except json.JSONDecodeError:
        token = secret

    _influxdb_token_cache = token
    return token


# Hàm này dùng để chuyển chuỗi thời gian ngắn như "5m", "2h", "1d" thành số giây
def _parse_duration_seconds(duration: str) -> int:
    match = re.fullmatch(r"\s*(\d+)\s*(s|m|h|d)\s*", duration)
    if not match:
        raise ValueError(f"Unsupported duration format: {duration}")

    amount = int(match.group(1))
    unit_seconds = {"s": 1, "m": 60, "h": 3600, "d": 86400}
    return amount * unit_seconds[match.group(2)]


def _format_influx_duration(seconds: int) -> str:
    return f"{seconds}s"

# Làm sạch chuỗi để dùng an toàn trong Flux query string
def _escape_flux_string(value: str) -> str:
    return value.replace("\\", "\\\\").replace('"', '\\"')

# Đảm bảo timestamp metric luôn sạch, parse được, và thống nhất về UTC.
def _parse_metric_timestamp(value: str) -> datetime:
    normalized = value.strip().replace("Z", "+00:00")
    if " " in normalized and "T" not in normalized:
        normalized = normalized.replace(" ", "T")
    if "." in normalized:
        head, tail = normalized.split(".", 1)
        fraction = tail
        suffix = ""
        for marker in ("+", "-"):
            if marker in tail:
                fraction, suffix = tail.split(marker, 1)
                suffix = marker + suffix
                break
        normalized = f"{head}.{fraction[:6].ljust(6, '0')}{suffix}"
    parsed = datetime.fromisoformat(normalized)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)

# Hàm này chuyển một object datetime thành chuỗi timestamp chuẩn UTC để đưa vào payload JSON.
def _format_payload_timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")

# Hàm này dùng để làm tròn thời gian xuống theo mốc cố định.
# Ví dụ nếu step_seconds = 300, tức là bước 5 phút.
def _floor_time(value: datetime, step_seconds: int) -> datetime:
    epoch_seconds = int(value.timestamp())
    return datetime.fromtimestamp(
        epoch_seconds - (epoch_seconds % step_seconds),
        tz=timezone.utc,
    )

# Từ cục dữ liệu nhận vào, lấy ra 4 field, gom lại thành 1 {} rồi trả về
def _metric_series_key(row: dict) -> tuple: # dict: Kiểu dữ liệu lưu trữ dạng key, value
    return (
        row.get("tenant_id"),
        row.get("service_id"),
        row.get("metric_type"),
        row.get("measure_name"),
    )

# Lấy ra giá trị của cái key tên "Value" rồi lấy giá trị của cái key này đem đi check 
def _numeric_metric_value(row: dict):
    value = row.get("value")
    if value is None:
        return None
    return float(value)

# chuyển kết quả CSV trả về từ InfluxDB thành list các dict metric dễ xử lý
def _parse_influx_csv(csv_text: str) -> list[dict]:
    data_lines = [
        line for line in csv_text.splitlines()
        if line and not line.startswith("#")
    ]
    if not data_lines:
        return []

    rows = []
    reader = csv.DictReader(io.StringIO("\n".join(data_lines)))
    for item in reader:
        if not item.get("_time") or not item.get("_value"):
            continue
        rows.append({
            "time": item["_time"],
            "service_id": item.get("service_id") or "unknown",
            "tenant_id": item.get("tenant_id") or "unknown",
            "metric_type": item.get("_measurement") or item.get("metric_type") or "unknown",
            "measure_name": item.get("_field") or "value",
            "value": item["_value"],
        })
    return rows

# chuẩn hóa dữ liệu metric thành các mốc thời gian đều nhau, rồi forward-fill các điểm bị thiếu.
def build_imputed_metric_window(metrics_data: dict) -> dict:
    """Build a regular time grid and forward-fill missing metric points per series."""
    load_config()
    rows = metrics_data.get("rows", [])
    parsed_rows = []

    for row in rows:
        try:
            parsed_rows.append({
                **row,
                "_time": _parse_metric_timestamp(row["time"]),
                "_value": _numeric_metric_value(row),
            })
        except (KeyError, TypeError, ValueError) as exc:
            logger.warning("Skipping malformed metric row during imputation: %s. row=%s", exc, row)

    if not parsed_rows:
        return {
            **metrics_data,
            "imputation": {
                "method": "forward_fill",
                "step_seconds": METRIC_WINDOW_STEP_SECONDS,
                "lookback_seconds": FORWARD_FILL_LOOKBACK_SECONDS,
                "status": "no_valid_rows",
            },
            "imputed_rows": [],
        }

    window_seconds = _parse_duration_seconds(metrics_data["window"])
    step_seconds = METRIC_WINDOW_STEP_SECONDS
    target_end = _floor_time(max(row["_time"] for row in parsed_rows), step_seconds)
    target_start = target_end - timedelta(seconds=window_seconds) + timedelta(seconds=step_seconds)

    by_series = {}
    for row in parsed_rows:
        if row["_value"] is None:
            continue
        by_series.setdefault(_metric_series_key(row), []).append(row)

    imputed_rows = []
    missing_seed_count = 0
    bucket_count = int(window_seconds / step_seconds)

    for series_key, series_rows in sorted(by_series.items()):
        series_rows.sort(key=lambda item: item["_time"])
        row_index = 0
        last_value = None

        for bucket_offset in range(bucket_count):
            bucket_time = target_start + timedelta(seconds=bucket_offset * step_seconds)
            exact_point = None

            while row_index < len(series_rows) and series_rows[row_index]["_time"] <= bucket_time:
                last_value = series_rows[row_index]["_value"]
                exact_point = series_rows[row_index]
                row_index += 1

            if last_value is None:
                missing_seed_count += 1
                continue

            tenant_id, service_id, metric_type, measure_name = series_key
            is_imputed = exact_point is None or exact_point["_time"] != bucket_time
            imputed_rows.append({
                "time": _format_payload_timestamp(bucket_time),
                "service_id": service_id,
                "tenant_id": tenant_id,
                "metric_type": metric_type,
                "measure_name": measure_name,
                "value": last_value,
                "imputed": is_imputed,
                "imputation_method": "forward_fill" if is_imputed else "observed",
            })

    return {
        **metrics_data,
        "rows_raw": rows,
        "rows": imputed_rows,
        "imputed_rows": imputed_rows,
        "imputation": {
            "method": "forward_fill",
            "step_seconds": step_seconds,
            "lookback_seconds": FORWARD_FILL_LOOKBACK_SECONDS,
            "target_start": _format_payload_timestamp(target_start),
            "target_end": _format_payload_timestamp(target_end),
            "series_count": len(by_series),
            "raw_row_count": len(rows),
            "imputed_row_count": len(imputed_rows),
            "missing_seed_count": missing_seed_count,
            "status": "ok",
        },
    }


def query_influxdb_metrics(window: str | None = None) -> dict:
    """Query the recent metric window from Timestream for InfluxDB."""
    load_config()
    query_window = window or INFLUXDB_QUERY_WINDOW
    query_window_seconds = _parse_duration_seconds(query_window)
    query_window_with_lookback = _format_influx_duration(
        query_window_seconds + FORWARD_FILL_LOOKBACK_SECONDS
    )
    flux = f'''
        from(bucket: "{_escape_flux_string(INFLUXDB_BUCKET)}")
          |> range(start: -{query_window_with_lookback})
          |> filter(fn: (r) => r._field == "value")
          |> keep(columns: ["_time", "_measurement", "_field", "_value", "service_id", "tenant_id"])
          |> sort(columns: ["_time"])
    '''

    query_url = f"{INFLUXDB_URL.rstrip('/')}/api/v2/query?org={urllib.parse.quote(INFLUXDB_ORG)}"
    request = urllib.request.Request(
        query_url,
        data=json.dumps({"query": flux, "type": "flux"}).encode("utf-8"),
        method="POST",
        headers={
            "Authorization": f"Token {_get_influxdb_token()}",
            "Accept": "application/csv",
            "Content-Type": "application/json",
        },
    )

    logger.info("Querying InfluxDB bucket %s with window %s", INFLUXDB_BUCKET, query_window)
    try:
        with urllib.request.urlopen(request, timeout=AI_ENGINE_TIMEOUT_SECONDS) as response:
            body = response.read().decode("utf-8")
        rows = _parse_influx_csv(body)
        logger.info("Successfully queried %d rows from InfluxDB.", len(rows))
        metrics_data = {
            "source": "timestream-influxdb",
            "bucket": INFLUXDB_BUCKET,
            "org": INFLUXDB_ORG,
            "window": query_window,
            "query_window_with_lookback": query_window_with_lookback,
            "rows": rows,
        }
        return build_imputed_metric_window(metrics_data)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        logger.error("InfluxDB query HTTP %d: %s", exc.code, body)
        raise
    except Exception as exc:
        logger.error("Error querying InfluxDB: %s", exc)
        raise


def _build_signal_window_row(row: dict) -> dict:
    signal = {
        "ts": row["time"],
        "tenant_id": row.get("tenant_id") or "unknown",
        "service_id": row.get("service_id") or "unknown",
        "metric_type": row.get("metric_type") or "unknown",
        "value": float(row["value"]),
    }

    labels = {}
    if row.get("measure_name"):
        labels["measure_name"] = row["measure_name"]
    if "imputed" in row:
        labels["imputed"] = row["imputed"]
    if row.get("imputation_method"):
        labels["imputation_method"] = row["imputation_method"]
    if labels:
        signal["labels"] = labels

    return signal


def build_ai_predict_requests(metrics_data: dict) -> list[dict]:
    """Convert the internal metric window into AI API Contract v1 requests."""
    load_config()
    rows = metrics_data.get("rows", [])
    if not rows:
        return []

    signals_by_tenant = {}
    for row in rows:
        signal = _build_signal_window_row(row)
        signals_by_tenant.setdefault(signal["tenant_id"], []).append(signal)

    imputation = metrics_data.get("imputation", {})
    start_ts = imputation.get("target_start")
    end_ts = imputation.get("target_end")
    if not start_ts or not end_ts:
        parsed_times = [_parse_metric_timestamp(row["time"]) for row in rows if row.get("time")]
        start_ts = _format_payload_timestamp(min(parsed_times))
        end_ts = _format_payload_timestamp(max(parsed_times))

    requests_to_send = []
    for tenant_id, signal_window in sorted(signals_by_tenant.items()):
        payload = {
            "signal_window": signal_window,
            "context": {
                "deployment_version": DEPLOYMENT_VERSION,
                "time_range": {
                    "start_ts": start_ts,
                    "end_ts": end_ts,
                },
            },
        }
        requests_to_send.append({
            "tenant_id": tenant_id,
            "correlation_id": str(uuid.uuid4()),
            "payload": payload,
        })

    return requests_to_send


def invoke_ai_engine(metrics_data: dict) -> dict:
    """Post the prepared metric window to AI Engine /v1/predict."""
    load_config()
    logger.info("Invoking AI Engine at: %s", AI_ENGINE_PREDICT_URL)
    predict_requests = build_ai_predict_requests(metrics_data)
    responses = []

    try:
        for predict_request in predict_requests:
            body = json.dumps(predict_request["payload"], separators=(",", ":"))
            headers = {
                "Content-Type": "application/json",
                "X-Tenant-Id": predict_request["tenant_id"],
                "X-Correlation-Id": predict_request["correlation_id"],
            }
            request = urllib.request.Request(
                AI_ENGINE_PREDICT_URL,
                data=body.encode("utf-8"),
                method="POST",
                headers=headers,
            )

            with urllib.request.urlopen(request, timeout=AI_ENGINE_TIMEOUT_SECONDS) as response:
                status_code = response.getcode()
                response_body = response.read().decode("utf-8")

            logger.info("AI Engine responded with status %s for tenant %s", status_code, predict_request["tenant_id"])
            ai_response = json.loads(response_body)
            ai_response.setdefault("tenant_id", predict_request["tenant_id"])
            ai_response.setdefault("correlation_id", predict_request["correlation_id"])
            responses.append(ai_response)

        if len(responses) == 1:
            return responses[0]

        return {
            "responses": responses,
            "anomaly": any(item.get("anomaly", False) for item in responses),
            "drift_detected": any(
                item.get("drift_detected", False) or item.get("anomaly", False)
                for item in responses
            ),
        }
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        logger.error("AI Engine HTTP %d: %s", exc.code, body)
        # HTTP 422: signal_window < 120 points (insufficient history, e.g. fresh deploy).
        # This is expected in the first 2h after a new deployment. Do NOT crash.
        # Publish a soft notice and return a "no-data" response instead.
        if exc.code == 422:
            logger.warning(
                "AI Engine rejected payload (422 Unprocessable): probably insufficient metric history "
                "(signal_window < 120 points). Skipping prediction for this cycle. "
                "System will auto-recover once 2h of data has accumulated."
            )
            return {
                "anomaly": False,
                "severity": 0.0,
                "recommendation": None,
                "reasoning": "Insufficient metric history (< 120 min). Prediction skipped.",
                "fallback": True,
                "fallback_reason": "signal_window_too_short",
            }
        raise
    except urllib.error.URLError as exc:
        logger.error("Failed to invoke AI Engine: %s", exc)
        raise


def publish_drift_alert(ai_response: dict):
    """Publish drift alerts returned by AI Engine."""
    load_config()
    if ai_response.get("drift_detected", False) or ai_response.get("anomaly", False):
        message = {
            "reason": "drift_detected",
            "source": "window-feeder",
            "details": ai_response,
        }
        logger.warning("Drift detected. Publishing alert to %s", DRIFT_ALERT_SNS_TOPIC_ARN)
        try:
            sns_client.publish(
                TopicArn=DRIFT_ALERT_SNS_TOPIC_ARN,
                Subject=f"Drift Detected in {os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'window-feeder')}",
                Message=json.dumps(message, indent=2),
            )
        except Exception as exc:
            logger.error("Failed to publish SNS alert: %s", exc)


def publish_window_feeder_failure(error: Exception, stage: str, event: dict):
    """Publish AI/query failures so the Fail-Open Fallback Lambda can run."""
    load_config()
    message = {
        "reason": "window_feeder_failed",
        "source": "window-feeder",
        "stage": stage,
        "error_type": type(error).__name__,
        "error": str(error),
        "event": event,
        "timestamp_utc": datetime.now(timezone.utc).isoformat(),
    }
    logger.warning("Publishing Window Feeder failure to %s", DRIFT_ALERT_SNS_TOPIC_ARN)
    try:
        sns_client.publish(
            TopicArn=DRIFT_ALERT_SNS_TOPIC_ARN,
            Subject="window_feeder_failed",
            Message=json.dumps(message, indent=2, default=str),
        )
    except Exception as exc:
        logger.error("Failed to publish Window Feeder failure alert: %s", exc)


def handler(event, context):
    """Lambda entry point invoked by EventBridge."""
    load_config()
    logger.info("Handler started. Event: %s", json.dumps(event))

    if not is_inference_enabled():
        logger.warning("Inference is disabled via SSM parameter. Exiting.")
        return {"statusCode": 200, "body": "Inference disabled."}

    try:
        query_window = event.get("window") if isinstance(event, dict) else None
        metrics_data = query_influxdb_metrics(window=query_window)
        if not metrics_data.get("rows"):
            logger.warning("No metrics data returned from InfluxDB. Exiting.")
            return {"statusCode": 200, "body": "No metrics data."}

        ai_response = invoke_ai_engine(metrics_data)
        publish_drift_alert(ai_response)

        logger.info("Handler finished successfully.")
        return {"statusCode": 200, "body": json.dumps(ai_response)}

    except Exception as exc:
        logger.critical("Window Feeder failed: %s", exc, exc_info=True)
        publish_window_feeder_failure(exc, stage="window_feeder", event=event if isinstance(event, dict) else {})
        raise
