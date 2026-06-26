# lambda/window-feeder/app.py

import os
import json
import logging
from datetime import datetime, timezone
from urllib.parse import urlparse

import boto3
import requests
from botocore.config import Config
from requests_aws4auth import AWS4Auth

# =================================================================
# Constants & Configuration
# =================================================================
# Cau hinh logging
# Mot thuc hanh tot la dat muc do log thong qua mot bien moi truong.
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
logger = logging.getLogger()
logger.setLevel(LOG_LEVEL)

# Tai tat ca cac bien moi truong can thiet.
# Viec nay giup lam ro cac cau hinh ma ham Lambda phu thuoc vao
# va se bao loi ngay lap tuc neu thieu mot bien nao do.
try:
    REGION = os.environ["AWS_REGION"]
    # Cac bien moi truong nay duoc truyen vao tu khoi `module "window_feeder"` trong file layer4-lambda.tf
    AMP_WORKSPACE_ID = os.environ["AMP_WORKSPACE_ID"]
    AMP_QUERY_WINDOW = os.environ["AMP_QUERY_WINDOW"]
    AI_ENGINE_PREDICT_URL = os.environ["AI_ENGINE_PREDICT_URL"]
    AI_ENGINE_TIMEOUT_SECONDS = int(os.environ["AI_ENGINE_TIMEOUT_SECONDS"])
    AUDIT_S3_BUCKET = os.environ["AUDIT_S3_BUCKET"]
    AUDIT_S3_PREFIX = os.environ["AUDIT_S3_PREFIX"]
    INFERENCE_ENABLED_PARAMETER_NAME = os.environ["INFERENCE_ENABLED_PARAMETER_NAME"]
    DRIFT_ALERT_SNS_TOPIC_ARN = os.environ["DRIFT_ALERT_SNS_TOPIC_ARN"]
except KeyError as e:
    logger.error(f"Missing required environment variable: {e}")
    raise

# =================================================================
# AWS Clients Initialization
# =================================================================
# Khoi tao cac client cua AWS SDK (boto3) ben ngoai ham handler.
# Dieu nay cho phep Lambda tai su dung cac ket noi giua cac lan goi, giup cai thien hieu nang.
boto_config = Config(
    region_name=REGION,
    retries={'max_attempts': 3, 'mode': 'standard'} # Tu dong thu lai 3 lan neu co loi tam thoi
)
ssm_client = boto3.client("ssm", config=boto_config) # Dung de doc tham so tu SSM Parameter Store
aps_client = boto3.client("aps", config=boto_config) # Dung de truy van Amazon Managed Prometheus
s3_client = boto3.client("s3", config=boto_config)   # Dung de ghi audit log vao S3
sns_client = boto3.client("sns", config=boto_config) # Dung de gui canh bao toi SNS

# Thiet lap co che xac thuc AWS Signature Version 4 (SigV4).
# Can thiet khi goi den cac endpoint duoc bao ve bang IAM,
# vi du nhu API Gateway hoac mot Application Load Balancer (ALB) co cau hinh xac thuc IAM.
credentials = boto3.Session().get_credentials()
aws_auth = AWS4Auth(
    credentials.access_key,
    credentials.secret_key,
    REGION,
    'execute-api', # Use 'execute-api' for API Gateway, or 'aps' for Prometheus etc.
    session_token=credentials.token
)


# =================================================================
# Helper Functions
# =================================================================

def is_inference_enabled() -> bool:
    """Kiem tra "cong" dieu khien hoat dong trong SSM Parameter Store."""
    try:
        logger.info(f"Checking SSM parameter: {INFERENCE_ENABLED_PARAMETER_NAME}")
        parameter = ssm_client.get_parameter(Name=INFERENCE_ENABLED_PARAMETER_NAME)
        is_enabled = parameter["Parameter"]["Value"].lower() == "true"
        logger.info(f"Inference enabled status: {is_enabled}")
        return is_enabled
    except Exception as e:
        logger.error(f"Failed to read SSM parameter: {e}")
        # An toan la tren het: neu khong doc duoc tham so, mac dinh la he thong dang tat.
        return False

def query_prometheus_metrics() -> dict:
    """Truy van du lieu metrics trong khoang thoi gian gan nhat tu Amazon Managed Prometheus (AMP)."""
    # Day la mot cau truy van PromQL mau. Ban can thay the no bang cau truy van thuc te cua minh.
    promql_query = f'sum(rate(http_requests_total[{AMP_QUERY_WINDOW}])) by (service_id, tenant_id)'
    
    logger.info(f"Querying AMP workspace {AMP_WORKSPACE_ID} with query: {promql_query}")
    
    try:
        response = aps_client.query_metrics(
            workspaceId=AMP_WORKSPACE_ID,
            query=promql_query
        )
        logger.info("Successfully queried metrics from AMP.")
        # Ban se can xu ly ket qua tra ve va dinh dang lai cho phu hop voi yeu cau cua AI Engine.
        # Day la mot vi du don gian.
        return response['data']
    except Exception as e:
        logger.error(f"Error querying AMP: {e}")
        raise

def invoke_ai_engine(metrics_data: dict) -> dict:
    """Gui du lieu metrics den AI Engine de nhan du bao."""
    logger.info(f"Invoking AI Engine at: {AI_ENGINE_PREDICT_URL}")
    
    try:
        response = requests.post(
            AI_ENGINE_PREDICT_URL,
            json=metrics_data, # Gui du lieu duoi dang JSON
            timeout=AI_ENGINE_TIMEOUT_SECONDS, # Dat thoi gian cho de tranh Lambda bi treo
            # auth=aws_auth # Bo comment dong nay neu ALB cua ban duoc bao ve bang IAM
        )
        response.raise_for_status()  # Raises an HTTPError for bad responses (4xx or 5xx)
        logger.info(f"AI Engine responded with status: {response.status_code}")
        return response.json()
    except requests.exceptions.RequestException as e:
        logger.error(f"Failed to invoke AI Engine: {e}")
        raise

def write_audit_log(input_data: dict, output_data: dict):
    """Ghi mot ban ghi kiem toan (audit record) vao S3."""
    timestamp = datetime.now(timezone.utc)
    audit_record = {
        "invocation_time_utc": timestamp.isoformat(),
        "source": "window-feeder",
        "input_to_ai_engine": input_data,
        "response_from_ai_engine": output_data,
    }
    
    # Su dung timestamp trong ten file (key) de dam bao tinh duy nhat.
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
        # Khong raise loi o day, vi viec ghi audit that bai khong nen lam dung luong xu ly chinh.

def publish_drift_alert(ai_response: dict):
    """Gui canh bao do lech (drift) toi SNS neu AI Engine phat hien."""
    if ai_response.get("drift_detected", False): # Kiem tra co 'drift_detected' trong phan hoi cua AI
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
# Main Lambda Handler
# =================================================================

def handler(event, context):
    """
    Ham xu ly chinh cua Lambda (entry point).
    Dieu phoi toan bo quy trinh: Kiem tra Cong -> Truy van -> Du bao -> Ghi Audit -> Canh bao.
    """
    logger.info(f"Handler started. Event: {json.dumps(event)}")

    # Buoc 1: Kiem tra "cong" dieu khien hoat dong
    if not is_inference_enabled():
        logger.warning("Inference is disabled via SSM parameter. Exiting.")
        return {"statusCode": 200, "body": "Inference disabled."}

    try:
        # Buoc 2: Truy van du lieu chuoi thoi gian
        metrics_data = query_prometheus_metrics()
        if not metrics_data:
            logger.warning("No metrics data returned from AMP. Exiting.")
            return {"statusCode": 200, "body": "No metrics data."}

        # Buoc 3: Goi den AI Engine de du bao
        ai_response = invoke_ai_engine(metrics_data)

        # Buoc 4: Ghi lai nhat ky kiem toan (luon thuc hien, du du bao thanh cong hay khong)
        write_audit_log(input_data=metrics_data, output_data=ai_response)

        # Buoc 5: Xu ly va gui canh bao neu co do lech
        publish_drift_alert(ai_response)

        logger.info("Handler finished successfully.")
        return {"statusCode": 200, "body": json.dumps(ai_response)}

    except Exception as e:
        # Xu ly moi loi khong mong muon xay ra trong qua trinh thuc thi
        logger.critical(f"An unhandled error occurred in the handler: {e}", exc_info=True)
        # Tuy chon: ban co the gui mot canh bao loi toi SNS tai day.
        # Raise lai exception de AWS Lambda biet rang lan thuc thi nay da that bai.
        raise
