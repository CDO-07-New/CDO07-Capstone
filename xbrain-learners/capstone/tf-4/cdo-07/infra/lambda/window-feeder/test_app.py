import os
import json
import boto3
import pytest
from moto import mock_aws
import requests_mock

# Import ham can test tu file app.py
# De import duoc, can them duong dan cua thu muc cha vao sys.path
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import app

# Ten cua SSM parameter dung cho test
TEST_PARAM_NAME = "/test/inference-enabled"

@pytest.fixture(scope='function')
def aws_credentials():
    """Mocked AWS Credentials for moto."""
    os.environ["AWS_ACCESS_KEY_ID"] = "testing"
    os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
    os.environ["AWS_SECURITY_TOKEN"] = "testing"
    os.environ["AWS_SESSION_TOKEN"] = "testing"
    os.environ["AWS_REGION"] = "us-east-1"

@pytest.fixture(scope='function')
def mock_aws_services(aws_credentials):
    """Fixture de mock cac dich vu AWS can thiet."""
    with mock_aws():
        yield {
            "ssm": boto3.client("ssm", region_name="us-east-1"),
            "s3": boto3.client("s3", region_name="us-east-1"),
            "sns": boto3.client("sns", region_name="us-east-1"),
            "aps": boto3.client("aps", region_name="us-east-1"),
        }

@pytest.fixture
def set_env_vars(monkeypatch):
    """Fixture de set bien moi truong cho Lambda."""
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    monkeypatch.setenv("AMP_WORKSPACE_ID", "ws-12345")
    monkeypatch.setenv("AMP_QUERY_WINDOW", "1h")
    monkeypatch.setenv("AI_ENGINE_PREDICT_URL", "http://test-ai-engine/v1/predict")
    monkeypatch.setenv("AI_ENGINE_TIMEOUT_SECONDS", "5")
    monkeypatch.setenv("AUDIT_S3_BUCKET", "test-audit-bucket")
    monkeypatch.setenv("AUDIT_S3_PREFIX", "test-prefix/")
    monkeypatch.setenv("INFERENCE_ENABLED_PARAMETER_NAME", "/test/inference-enabled")
    monkeypatch.setenv("DRIFT_ALERT_SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123456789012:test-drift-topic")

# ===================================
# Unit Tests for Helper Functions
# ===================================

def test_inference_is_enabled(mock_aws_services, set_env_vars):
    """Kiem tra truong hop inference duoc bat (enabled)."""
    # Chuan bi: Tao mot parameter "true" trong SSM gia lap
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true", Type="String")

    # Thuc thi: Goi ham can test
    result = app.is_inference_enabled()

    # Khang dinh: Ket qua phai la True
    assert result is True

def test_write_audit_log(mock_aws_services, set_env_vars):
    """Kiem tra ham ghi audit log ra S3."""
    mock_aws_services["s3"].create_bucket(Bucket="test-audit-bucket")
    app.write_audit_log({"input": "data"}, {"output": "data"})

    # Kiem tra xem co object nao duoc tao ra trong bucket khong
    objects = mock_aws_services["s3"].list_objects_v2(Bucket="test-audit-bucket")
    assert len(objects["Contents"]) == 1
    assert objects["Contents"][0]["Key"].startswith("test-prefix/")

def test_publish_drift_alert_when_drift_detected(mocker, set_env_vars):
    """Kiem tra ham gui SNS khi phat hien drift."""
    # Mock client SNS de theo doi viec goi ham
    mock_sns_publish = mocker.patch("app.sns_client.publish")
    
    # Thuc thi voi du lieu co drift
    app.publish_drift_alert({"drift_detected": True, "details": "..."})

    # Khang dinh: Ham publish cua SNS duoc goi 1 lan
    mock_sns_publish.assert_called_once()

def test_publish_drift_alert_when_no_drift(mocker, set_env_vars):
    """Kiem tra ham KHONG gui SNS khi khong co drift."""
    mock_sns_publish = mocker.patch("app.sns_client.publish")
    
    # Thuc thi voi du lieu khong co drift
    app.publish_drift_alert({"drift_detected": False})

    # Khang dinh: Ham publish cua SNS khong duoc goi
    mock_sns_publish.assert_not_called()

# ===================================
# Integration Tests for Main Handler
# ===================================

def test_handler_happy_path_with_drift(mock_aws_services, set_env_vars, mocker):
    """Kiem tra toan bo luong xu ly thanh cong va co phat hien drift."""
    # Chuan bi: Mock tat ca cac dependency
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true", Type="String")
    mock_aws_services["s3"].create_bucket(Bucket="test-audit-bucket")
    mock_aws_services["sns"].create_topic(Name="test-drift-topic")
    
    mocker.patch("app.aps_client.query_metrics", return_value={"data": {"result": "some_metrics"}})
    mock_sns_publish = mocker.patch("app.sns_client.publish")

    with requests_mock.Mocker() as m:
        m.post("http://test-ai-engine/v1/predict", json={"prediction": "ok", "drift_detected": True})
        
        # Thuc thi
        response = app.handler({}, None)

    # Khang dinh
    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["drift_detected"] is True
    
    # Kiem tra audit log da duoc ghi
    objects = mock_aws_services["s3"].list_objects_v2(Bucket="test-audit-bucket")
    assert len(objects["Contents"]) == 1

    # Kiem tra canh bao drift da duoc gui
    mock_sns_publish.assert_called_once()

def test_handler_inference_disabled(mock_aws_services, set_env_vars):
    """Kiem tra truong hop inference bi tat (disabled)."""
    # Chuan bi: Tao mot parameter "false" trong SSM gia lap
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="false", Type="String")

    # Thuc thi
    response = app.handler({}, None)

    # Khang dinh: Ham tra ve ngay lap tuc
    assert response["statusCode"] == 200
    assert response["body"] == "Inference disabled."

def test_handler_ai_engine_fails(mock_aws_services, set_env_vars, mocker):
    """Kiem tra truong hop AI Engine tra ve loi 500."""
    # Chuan bi
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true", Type="String")
    mocker.patch("app.aps_client.query_metrics", return_value={"data": {"result": "some_metrics"}})

    with requests_mock.Mocker() as m:
        m.post("http://test-ai-engine/v1/predict", status_code=500)
        
        # Thuc thi va khang dinh rang ham se raise exception
        with pytest.raises(Exception) as excinfo:
            app.handler({}, None)
        
        assert "500 Server Error" in str(excinfo.value)