# lambda/window-feeder/app.py

import os
import json
import logging
import re
from datetime import datetime, timedelta, timezone

import boto3
import requests
from botocore.config import Config

# =================================================================
# Hằng số và cấu hình
# =================================================================
# Cấu hình logging.
# Best practice là đặt mức độ log thông qua biến môi trường.
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

REGION = os.environ.get("AWS_REGION", "us-east-1")
TIMESTREAM_DATABASE_NAME = os.environ.get("TIMESTREAM_DATABASE_NAME")
TIMESTREAM_TABLE_NAME = os.environ.get("TIMESTREAM_TABLE_NAME")
TIMESTREAM_QUERY_WINDOW = os.environ.get("TIMESTREAM_QUERY_WINDOW")
METRIC_WINDOW_STEP_SECONDS = int(os.environ.get("METRIC_WINDOW_STEP_SECONDS", "300"))
FORWARD_FILL_LOOKBACK_SECONDS = int(os.environ.get("FORWARD_FILL_LOOKBACK_SECONDS", "900"))
AI_ENGINE_PREDICT_URL = os.environ.get("AI_ENGINE_PREDICT_URL")
AI_ENGINE_TIMEOUT_SECONDS = int(os.environ.get("AI_ENGINE_TIMEOUT_SECONDS", "5"))
AUDIT_S3_BUCKET = os.environ.get("AUDIT_S3_BUCKET")
AUDIT_S3_PREFIX = os.environ.get("AUDIT_S3_PREFIX")
INFERENCE_ENABLED_PARAMETER_NAME = os.environ.get("INFERENCE_ENABLED_PARAMETER_NAME")
DRIFT_ALERT_SNS_TOPIC_ARN = os.environ.get("DRIFT_ALERT_SNS_TOPIC_ARN")

# Tải và kiểm tra cấu hình runtime từ biến môi trường của Lambda.
# Hàm này được gọi bên trong các hàm khác thay vì chỉ lúc import để unit test
# có thể vá biến môi trường trước khi chạy mã Lambda.
def load_config():
    """Nạp lại cấu hình từ environment để Lambda và unit test dùng cùng một luồng chạy."""
    global REGION
    global TIMESTREAM_DATABASE_NAME, TIMESTREAM_TABLE_NAME, TIMESTREAM_QUERY_WINDOW
    global METRIC_WINDOW_STEP_SECONDS, FORWARD_FILL_LOOKBACK_SECONDS
    global AI_ENGINE_PREDICT_URL, AI_ENGINE_TIMEOUT_SECONDS
    global AUDIT_S3_BUCKET, AUDIT_S3_PREFIX, INFERENCE_ENABLED_PARAMETER_NAME, DRIFT_ALERT_SNS_TOPIC_ARN

    required = [
        "AWS_REGION",
        "TIMESTREAM_DATABASE_NAME",
        "TIMESTREAM_TABLE_NAME",
        "TIMESTREAM_QUERY_WINDOW",
        "METRIC_WINDOW_STEP_SECONDS",
        "FORWARD_FILL_LOOKBACK_SECONDS",
        "AI_ENGINE_PREDICT_URL",
        "AI_ENGINE_TIMEOUT_SECONDS",
        "AUDIT_S3_BUCKET",
        "AUDIT_S3_PREFIX",
        "INFERENCE_ENABLED_PARAMETER_NAME",
        "DRIFT_ALERT_SNS_TOPIC_ARN",
    ]
    missing = [name for name in required if not os.environ.get(name)]
    if missing:
        raise RuntimeError(f"Missing required environment variables: {', '.join(missing)}")

    REGION = os.environ["AWS_REGION"]
    TIMESTREAM_DATABASE_NAME = os.environ["TIMESTREAM_DATABASE_NAME"]
    TIMESTREAM_TABLE_NAME = os.environ["TIMESTREAM_TABLE_NAME"]
    TIMESTREAM_QUERY_WINDOW = os.environ["TIMESTREAM_QUERY_WINDOW"]
    METRIC_WINDOW_STEP_SECONDS = int(os.environ["METRIC_WINDOW_STEP_SECONDS"])
    FORWARD_FILL_LOOKBACK_SECONDS = int(os.environ["FORWARD_FILL_LOOKBACK_SECONDS"])
    AI_ENGINE_PREDICT_URL = os.environ["AI_ENGINE_PREDICT_URL"]
    AI_ENGINE_TIMEOUT_SECONDS = int(os.environ["AI_ENGINE_TIMEOUT_SECONDS"])
    AUDIT_S3_BUCKET = os.environ["AUDIT_S3_BUCKET"]
    AUDIT_S3_PREFIX = os.environ["AUDIT_S3_PREFIX"]
    INFERENCE_ENABLED_PARAMETER_NAME = os.environ["INFERENCE_ENABLED_PARAMETER_NAME"]
    DRIFT_ALERT_SNS_TOPIC_ARN = os.environ["DRIFT_ALERT_SNS_TOPIC_ARN"]

# =================================================================
# Khởi tạo AWS client
# =================================================================
# Khởi tạo các client của AWS SDK (boto3) bên ngoài hàm handler.
# Điều này cho phép Lambda tái sử dụng kết nối giữa các lần gọi, giúp cải thiện hiệu năng.
boto_config = Config(
    region_name=REGION,
    retries={'max_attempts': 3, 'mode': 'standard'} # Tự động thử lại 3 lần nếu có lỗi tạm thời
)
ssm_client = boto3.client("ssm", config=boto_config) # Dùng để đọc tham số từ SSM Parameter Store
timestream_query_client = boto3.client("timestream-query", config=boto_config) # Dùng để truy vấn Amazon Timestream
s3_client = boto3.client("s3", config=boto_config)   # Dùng để ghi audit log vào S3
sns_client = boto3.client("sns", config=boto_config) # Dùng để gửi cảnh báo tới SNS

# =================================================================
# Các hàm hỗ trợ
# =================================================================

# Đọc cờ điều khiển vận hành từ SSM Parameter Store.
# Nếu tham số này không đúng bằng "true", Lambda sẽ thoát sớm và không
# truy vấn Timestream hoặc gọi AI Engine.
def is_inference_enabled() -> bool:
    """Kiểm tra "cổng" điều khiển hoạt động trong SSM Parameter Store."""
    load_config()
    try:
        logger.info(f"Checking SSM parameter: {INFERENCE_ENABLED_PARAMETER_NAME}")
        parameter = ssm_client.get_parameter(Name=INFERENCE_ENABLED_PARAMETER_NAME)
        is_enabled = parameter["Parameter"]["Value"].lower() == "true"
        logger.info(f"Inference enabled status: {is_enabled}")
        return is_enabled
    except Exception as e:
        logger.error(f"Failed to read SSM parameter: {e}")
        # An toàn là trên hết: nếu không đọc được tham số, mặc định là hệ thống đang tắt.
        return False

# Chuyển một giá trị ô Timestream thành giá trị Python thông thường.
# Timestream có thể trả về dạng scalar, array, row và time-series, nên hàm hỗ trợ
# này chuẩn hóa dữ liệu trước khi payload được gửi đến AI Engine.
def _parse_timestream_value(value: dict):
    if value.get("NullValue"):
        return None
    if "ScalarValue" in value:
        return value["ScalarValue"]
    if "TimeSeriesValue" in value:
        return [
            {
                "time": item["Time"],
                "value": _parse_timestream_value(item["Value"]),
            }
            for item in value["TimeSeriesValue"]
        ]
    if "ArrayValue" in value:
        return [_parse_timestream_value(item) for item in value["ArrayValue"]]
    if "RowValue" in value:
        return _parse_timestream_row(value["RowValue"])
    return None

# Chuyển một dòng Timestream thành dictionary với khóa là tên cột.
# Điều này giúp mã phía sau không phụ thuộc vào cấu trúc phản hồi lồng nhau của Timestream.
def _parse_timestream_row(row: dict) -> dict:
    return {
        column["Name"]: _parse_timestream_value(value)
        for column, value in zip(row["ColumnInfo"], row["Data"])
    }

# Truy vấn cửa sổ metrics trượt từ Amazon Timestream.
# Đây là phía đọc của luồng nạp dữ liệu Kinesis -> Firehose -> Transformer -> Timestream
# được thể hiện trong sơ đồ kiến trúc.
def _parse_duration_seconds(duration: str) -> int:
    match = re.fullmatch(r"\s*(\d+)\s*(s|m|h|d)\s*", duration)
    if not match:
        raise ValueError(f"Unsupported duration format: {duration}")

    amount = int(match.group(1))
    unit_seconds = {
        "s": 1,
        "m": 60,
        "h": 3600,
        "d": 86400,
    }
    return amount * unit_seconds[match.group(2)]


def _format_timestream_duration(seconds: int) -> str:
    return f"{seconds}s"


def _parse_timestream_timestamp(value: str) -> datetime:
    normalized = value.replace("T", " ").replace("Z", "")
    if "." in normalized:
        head, fraction = normalized.split(".", 1)
        normalized = f"{head}.{fraction[:6].ljust(6, '0')}"
        parsed = datetime.strptime(normalized, "%Y-%m-%d %H:%M:%S.%f")
    else:
        parsed = datetime.strptime(normalized, "%Y-%m-%d %H:%M:%S")
    return parsed.replace(tzinfo=timezone.utc)


def _format_payload_timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat().replace("+00:00", "Z")


def _floor_time(value: datetime, step_seconds: int) -> datetime:
    epoch_seconds = int(value.timestamp())
    return datetime.fromtimestamp(
        epoch_seconds - (epoch_seconds % step_seconds),
        tz=timezone.utc,
    )


def _metric_series_key(row: dict) -> tuple:
    return (
        row.get("tenant_id"),
        row.get("service_id"),
        row.get("metric_type"),
        row.get("measure_name"),
    )


def _numeric_metric_value(row: dict):
    value = row.get("value")
    if value is None:
        return None
    return float(value)


def build_imputed_metric_window(metrics_data: dict) -> dict:
    """Build a regular time grid and forward-fill missing metric points per series."""
    load_config()
    rows = metrics_data.get("rows", [])
    parsed_rows = []

    for row in rows:
        try:
            parsed_rows.append({
                **row,
                "_time": _parse_timestream_timestamp(row["time"]),
                "_value": _numeric_metric_value(row),
            })
        except (KeyError, TypeError, ValueError) as exc:
            logger.warning("Skipping malformed Timestream row during imputation: %s. row=%s", exc, row)

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


def query_timestream_metrics() -> dict:
    """Truy vấn dữ liệu metrics trong khoảng thời gian gần nhất từ Amazon Timestream."""
    load_config()
    query_window_seconds = _parse_duration_seconds(TIMESTREAM_QUERY_WINDOW)
    query_window_with_lookback = _format_timestream_duration(
        query_window_seconds + FORWARD_FILL_LOOKBACK_SECONDS
    )
    query = f'''
        SELECT
          time,
          service_id,
          tenant_id,
          metric_type,
          measure_name,
          measure_value::double AS value
        FROM "{TIMESTREAM_DATABASE_NAME}"."{TIMESTREAM_TABLE_NAME}"
        WHERE time >= ago({query_window_with_lookback})
        ORDER BY time ASC
    '''

    logger.info(
        "Querying Timestream table %s.%s with window %s",
        TIMESTREAM_DATABASE_NAME,
        TIMESTREAM_TABLE_NAME,
        TIMESTREAM_QUERY_WINDOW,
    )

    try:
        response = timestream_query_client.query(QueryString=query)
        rows = [
            _parse_timestream_row({
                "ColumnInfo": response["ColumnInfo"],
                "Data": row["Data"],
            })
            for row in response.get("Rows", [])
        ]
        logger.info("Successfully queried %d rows from Timestream.", len(rows))
        metrics_data = {
            "source": "timestream",
            "database": TIMESTREAM_DATABASE_NAME,
            "table": TIMESTREAM_TABLE_NAME,
            "window": TIMESTREAM_QUERY_WINDOW,
            "query_window_with_lookback": query_window_with_lookback,
            "rows": rows,
        }
        return build_imputed_metric_window(metrics_data)
    except Exception as e:
        logger.error(f"Error querying Timestream: {e}")
        raise

# Gửi payload metrics Timestream đã chuẩn hóa đến API /v1/predict của AI Engine.
# Timeout được cấu hình nên thấp hơn timeout của Lambda để lỗi được trả về có thể dự đoán,
# thay vì treo cho đến khi Lambda bị kết thúc.
def invoke_ai_engine(metrics_data: dict) -> dict:
    """Gửi dữ liệu metrics đến AI Engine để nhận dự báo."""
    load_config()
    logger.info(f"Invoking AI Engine at: {AI_ENGINE_PREDICT_URL}")
    
    try:
        response = requests.post(
            AI_ENGINE_PREDICT_URL,
            json=metrics_data, # Gửi dữ liệu dưới dạng JSON
            timeout=AI_ENGINE_TIMEOUT_SECONDS, # Đặt thời gian chờ để tránh Lambda bị treo
            # auth=aws_auth # Bỏ comment dòng này nếu ALB của bạn được bảo vệ bằng IAM
        )
        response.raise_for_status()  # Ném HTTPError nếu phản hồi lỗi (4xx hoặc 5xx)
        logger.info(f"AI Engine responded with status: {response.status_code}")
        return response.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to invoke AI Engine: {e}")
        raise

# Lưu input và phản hồi AI thành một object audit trong S3.
# Lỗi audit chỉ được ghi log và không raise vì lỗi quan sát không nên chặn
# luồng inference chính sau khi dự báo đã hoàn tất.
def write_audit_log(input_data: dict, output_data: dict):
    """Ghi một bản ghi kiểm toán (audit record) vào S3."""
    load_config()
    timestamp = datetime.now(timezone.utc)
    audit_record = {
        "invocation_time_utc": timestamp.isoformat(),
        "source": "window-feeder",
        "input_to_ai_engine": input_data,
        "response_from_ai_engine": output_data,
    }
    
    # Sử dụng timestamp trong tên file (key) để đảm bảo tính duy nhất.
    s3_key = f"{AUDIT_S3_PREFIX.strip('/')}/{timestamp.strftime('%Y/%m/%d/%H-%M-%S-%f')}.json"
    
    logger.info(f"Writing audit log to s3://{AUDIT_S3_BUCKET}/{s3_key}")
    try:
        s3_client.put_object(
            Bucket=AUDIT_S3_BUCKET,
            Key=s3_key,
            Body=json.dumps(audit_record, indent=2),
            ContentType="application/json"
        )
    except Exception as e:
        logger.error(f"Failed to write audit log to S3: {e}")
        # Không raise lỗi ở đây, vì việc ghi audit thất bại không nên làm dừng luồng xử lý chính.

# Chỉ phát cảnh báo drift khi phản hồi AI đánh dấu rõ ràng drift_detected.
# SNS topic sẽ phân phối cảnh báo đến các kênh thông báo như Slack hoặc quy trình on-call.
def publish_drift_alert(ai_response: dict):
    """Gửi cảnh báo độ lệch (drift) tới SNS nếu AI Engine phát hiện."""
    load_config()
    if ai_response.get("drift_detected", False): # Kiểm tra có 'drift_detected' trong phản hồi của AI
        message = {
            "default": json.dumps(ai_response, indent=2),
            "subject": f"Drift Detected in {os.environ.get('AWS_LAMBDA_FUNCTION_NAME', 'window-feeder')}",
            "message": f"AI Engine detected a drift. Details: \n{json.dumps(ai_response, indent=2)}"
        }
        logger.warning(f"Drift detected. Publishing alert to {DRIFT_ALERT_SNS_TOPIC_ARN}")
        try:
            sns_client.publish(
                TopicArn=DRIFT_ALERT_SNS_TOPIC_ARN,
                Message=json.dumps({'default': json.dumps(message)}),
                MessageStructure='json'
            )
        except Exception as e:
            logger.error(f"Failed to publish SNS alert: {e}")


# =================================================================
# Handler chính của Lambda
# =================================================================

# Điểm vào của Lambda, được EventBridge gọi theo lịch đã cấu hình.
# Hàm này điều phối toàn bộ workflow window-feeder: kiểm tra cờ điều khiển,
# truy vấn metrics, dự báo AI, ghi audit và cảnh báo drift nếu cần.
def handler(event, context):
    """
    Hàm xử lý chính của Lambda (entry point).
    Điều phối toàn bộ quy trình: Kiểm tra Cổng -> Truy vấn -> Dự báo -> Ghi Audit -> Cảnh báo.
    """
    load_config()
    logger.info(f"Handler started. Event: {json.dumps(event)}")

    # Bước 1: Kiểm tra "cổng" điều khiển hoạt động
    if not is_inference_enabled():
        logger.warning("Inference is disabled via SSM parameter. Exiting.")
        return {"statusCode": 200, "body": "Inference disabled."}

    try:
        # Bước 2: Truy vấn dữ liệu chuỗi thời gian
        metrics_data = query_timestream_metrics()
        if not metrics_data.get("rows"):
            logger.warning("No metrics data returned from Timestream. Exiting.")
            return {"statusCode": 200, "body": "No metrics data."}

        # Bước 3: Gọi đến AI Engine để dự báo
        ai_response = invoke_ai_engine(metrics_data)

        # Bước 4: Ghi lại nhật ký kiểm toán (luôn thực hiện, dù dự báo thành công hay không)
        write_audit_log(input_data=metrics_data, output_data=ai_response)

        # Bước 5: Xử lý và gửi cảnh báo nếu có độ lệch
        publish_drift_alert(ai_response)

        logger.info("Handler finished successfully.")
        return {"statusCode": 200, "body": json.dumps(ai_response)}

    except Exception as e:
        # Xử lý mọi lỗi không mong muốn xảy ra trong quá trình thực thi
        logger.critical(f"An unhandled error occurred in the handler: {e}", exc_info=True)
        # Tùy chọn: bạn có thể gửi một cảnh báo lỗi tới SNS tại đây.
        # Raise lại exception để AWS Lambda biết rằng lần thực thi này đã thất bại.
        raise
