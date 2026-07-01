import json
import os
import sys
import urllib.error
from unittest.mock import Mock

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import app


class FakeSsmClient:
    def __init__(self):
        self.parameters = {}

    def put_parameter(self, Name, Value, Type):
        self.parameters[Name] = {"Value": Value, "Type": Type}

    def get_parameter(self, Name):
        if Name not in self.parameters:
            raise KeyError(Name)
        return {"Parameter": self.parameters[Name]}


class FakeSecretsManagerClient:
    def __init__(self):
        self.secrets = {}

    def put_secret_value(self, SecretId, SecretString):
        self.secrets[SecretId] = SecretString

    def get_secret_value(self, SecretId):
        if SecretId not in self.secrets:
            raise KeyError(SecretId)
        return {"SecretString": self.secrets[SecretId]}


class FakeS3Client:
    def __init__(self):
        self.buckets = {}

    def create_bucket(self, Bucket):
        self.buckets[Bucket] = {}

    def put_object(self, Bucket, Key, Body, ContentType):
        self.buckets.setdefault(Bucket, {})[Key] = {
            "Body": Body,
            "ContentType": ContentType,
        }

    def list_objects_v2(self, Bucket):
        contents = [{"Key": key} for key in self.buckets.get(Bucket, {})]
        return {"Contents": contents} if contents else {}


class FakeSnsClient:
    def __init__(self):
        self.messages = []

    def create_topic(self, Name):
        return {"TopicArn": f"arn:aws:sns:us-east-1:123456789012:{Name}"}

    def publish(self, **kwargs):
        self.messages.append(kwargs)
        return {"MessageId": "test-message-id"}


class FakeHttpResponse:
    def __init__(self, body: dict, status_code: int = 200):
        self.body = json.dumps(body).encode("utf-8")
        self.status_code = status_code

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, traceback):
        return False

    def getcode(self):
        return self.status_code

    def read(self):
        return self.body


@pytest.fixture(scope="function")
def mock_aws_services(monkeypatch):
    clients = {
        "ssm": FakeSsmClient(),
        "secretsmanager": FakeSecretsManagerClient(),
        "s3": FakeS3Client(),
        "sns": FakeSnsClient(),
    }
    monkeypatch.setattr(app, "ssm_client", clients["ssm"])
    monkeypatch.setattr(app, "secretsmanager_client", clients["secretsmanager"])
    monkeypatch.setattr(app, "sns_client", clients["sns"])
    app._influxdb_token_cache = None
    yield clients


@pytest.fixture
def set_env_vars(monkeypatch):
    monkeypatch.setenv("AWS_REGION", "us-east-1")
    monkeypatch.setenv("INFLUXDB_URL", "https://test-influxdb:8086")
    monkeypatch.setenv("INFLUXDB_BUCKET", "service-metrics")
    monkeypatch.setenv("INFLUXDB_ORG", "cdo-07")
    monkeypatch.setenv("INFLUXDB_SECRET_ARN", "arn:aws:secretsmanager:us-east-1:123456789012:secret:influx")
    monkeypatch.setenv("INFLUXDB_QUERY_WINDOW", "1h")
    monkeypatch.setenv("METRIC_WINDOW_STEP_SECONDS", "300")
    monkeypatch.setenv("FORWARD_FILL_LOOKBACK_SECONDS", "900")
    monkeypatch.setenv("AI_ENGINE_PREDICT_URL", "http://test-ai-engine/v1/predict")
    monkeypatch.setenv("AI_ENGINE_TIMEOUT_SECONDS", "5")
    monkeypatch.setenv("DEPLOYMENT_VERSION", "test-version")
    monkeypatch.setenv("INFERENCE_ENABLED_PARAMETER_NAME", "/test/inference-enabled")
    monkeypatch.setenv("DRIFT_ALERT_SNS_TOPIC_ARN", "arn:aws:sns:us-east-1:123456789012:test-drift-topic")


def test_inference_is_enabled(mock_aws_services, set_env_vars):
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true", Type="String")

    result = app.is_inference_enabled()

    assert result is True


def test_publish_drift_alert_when_drift_detected(mock_aws_services, set_env_vars):
    app.publish_drift_alert({"drift_detected": True, "details": "..."})

    assert len(mock_aws_services["sns"].messages) == 1
    assert mock_aws_services["sns"].messages[0]["Subject"].startswith("Drift Detected")


def test_publish_drift_alert_when_no_drift(mock_aws_services, set_env_vars):
    app.publish_drift_alert({"drift_detected": False})

    assert mock_aws_services["sns"].messages == []


def test_parse_influx_csv_to_metric_rows():
    csv_text = """#datatype,string,long,dateTime:RFC3339,dateTime:RFC3339,dateTime:RFC3339,double,string,string,string
#group,false,false,true,true,false,false,true,true,true
#default,_result,,,,,,,,
,result,table,_start,_stop,_time,_value,_field,_measurement,service_id,tenant_id
,,0,2026-06-26T00:00:00Z,2026-06-26T00:15:00Z,2026-06-26T00:05:00Z,110,value,latency_ms,payment-gw,tenant-a
"""

    rows = app._parse_influx_csv(csv_text)

    assert rows == [
        {
            "time": "2026-06-26T00:05:00Z",
            "service_id": "payment-gw",
            "tenant_id": "tenant-a",
            "metric_type": "latency_ms",
            "measure_name": "value",
            "value": "110",
        }
    ]


def test_build_imputed_metric_window_forward_fills_missing_bucket(set_env_vars):
    metrics_data = {
        "source": "timestream-influxdb",
        "bucket": "service-metrics",
        "org": "cdo-07",
        "window": "15m",
        "rows": [
            {
                "time": "2026-06-26T00:00:00Z",
                "service_id": "payment-gw",
                "tenant_id": "tenant-a",
                "metric_type": "latency_ms",
                "measure_name": "value",
                "value": "100.0",
            },
            {
                "time": "2026-06-26T00:05:00Z",
                "service_id": "payment-gw",
                "tenant_id": "tenant-a",
                "metric_type": "latency_ms",
                "measure_name": "value",
                "value": "110.0",
            },
            {
                "time": "2026-06-26T00:15:00Z",
                "service_id": "payment-gw",
                "tenant_id": "tenant-a",
                "metric_type": "latency_ms",
                "measure_name": "value",
                "value": "130.0",
            },
        ],
    }

    result = app.build_imputed_metric_window(metrics_data)

    assert result["imputation"]["status"] == "ok"
    assert [row["time"] for row in result["rows"]] == [
        "2026-06-26T00:05:00Z",
        "2026-06-26T00:10:00Z",
        "2026-06-26T00:15:00Z",
    ]
    assert result["rows"][1]["value"] == 110.0
    assert result["rows"][1]["imputed"] is True
    assert result["rows"][1]["imputation_method"] == "forward_fill"


def test_build_ai_predict_requests_matches_contract(set_env_vars, monkeypatch):
    monkeypatch.setattr(app.uuid, "uuid4", Mock(return_value="correlation-id"))
    metrics_data = {
        "window": "2h",
        "rows": [
            {
                "time": "2026-06-26T00:00:00Z",
                "tenant_id": "tenant-a",
                "service_id": "payment-gw",
                "metric_type": "latency_ms",
                "measure_name": "value",
                "value": 1200,
                "imputed": False,
                "imputation_method": "observed",
            },
            {
                "time": "2026-06-26T00:05:00Z",
                "tenant_id": "tenant-a",
                "service_id": "payment-gw",
                "metric_type": "latency_ms",
                "measure_name": "value",
                "value": 1800,
                "imputed": True,
                "imputation_method": "forward_fill",
            },
        ],
        "imputation": {
            "target_start": "2026-06-25T22:05:00Z",
            "target_end": "2026-06-26T00:05:00Z",
        },
    }

    result = app.build_ai_predict_requests(metrics_data)

    assert result == [
        {
            "tenant_id": "tenant-a",
            "correlation_id": "correlation-id",
            "payload": {
                "signal_window": [
                    {
                        "ts": "2026-06-26T00:00:00Z",
                        "tenant_id": "tenant-a",
                        "service_id": "payment-gw",
                        "metric_type": "latency_ms",
                        "value": 1200.0,
                        "labels": {
                            "measure_name": "value",
                            "imputed": False,
                            "imputation_method": "observed",
                        },
                    },
                    {
                        "ts": "2026-06-26T00:05:00Z",
                        "tenant_id": "tenant-a",
                        "service_id": "payment-gw",
                        "metric_type": "latency_ms",
                        "value": 1800.0,
                        "labels": {
                            "measure_name": "value",
                            "imputed": True,
                            "imputation_method": "forward_fill",
                        },
                    },
                ],
                "context": {
                    "deployment_version": "test-version",
                    "time_range": {
                        "start_ts": "2026-06-25T22:05:00Z",
                        "end_ts": "2026-06-26T00:05:00Z",
                    },
                },
            },
        }
    ]


def test_handler_happy_path_with_drift(mock_aws_services, set_env_vars, monkeypatch):
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true", Type="String")
    monkeypatch.setattr(app, "query_influxdb_metrics", Mock(return_value={
        "source": "timestream-influxdb",
        "window": "1h",
        "rows": [{
            "time": "2026-06-26T00:00:00Z",
            "tenant_id": "tenant-a",
            "service_id": "payment-gw",
            "metric_type": "latency_ms",
            "value": 123.4,
        }],
        "imputation": {
            "target_start": "2026-06-25T23:00:00Z",
            "target_end": "2026-06-26T00:00:00Z",
        },
    }))
    mock_response = Mock()
    mock_response.return_value = FakeHttpResponse({"anomaly": True, "severity": 0.7})
    monkeypatch.setattr(app.urllib.request, "urlopen", mock_response)

    response = app.handler({"window": "1h"}, None)

    assert response["statusCode"] == 200
    body = json.loads(response["body"])
    assert body["anomaly"] is True
    posted_request = app.urllib.request.urlopen.call_args.args[0]
    payload = json.loads(posted_request.data.decode("utf-8"))
    assert "signal_window" in payload
    assert "context" in payload
    assert payload["signal_window"][0]["ts"] == "2026-06-26T00:00:00Z"
    assert posted_request.get_header("X-tenant-id") == "tenant-a"
    assert posted_request.get_header("X-correlation-id")
    assert posted_request.get_header("Authorization") is None
    assert len(mock_aws_services["sns"].messages) == 1


def test_handler_inference_disabled(mock_aws_services, set_env_vars):
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="false", Type="String")

    response = app.handler({}, None)

    assert response["statusCode"] == 200
    assert response["body"] == "Inference disabled."


def test_handler_ai_engine_fails_publishes_fail_open_message(mock_aws_services, set_env_vars, monkeypatch):
    mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true", Type="String")
    monkeypatch.setattr(app, "query_influxdb_metrics", Mock(return_value={
        "source": "timestream-influxdb",
        "window": "1h",
        "rows": [{
            "time": "2026-06-26T00:00:00Z",
            "tenant_id": "tenant-a",
            "service_id": "payment-gw",
            "metric_type": "latency_ms",
            "value": 123.4,
        }],
        "imputation": {
            "target_start": "2026-06-25T23:00:00Z",
            "target_end": "2026-06-26T00:00:00Z",
        },
    }))
    http_error = urllib.error.HTTPError(
        url="http://test-ai-engine/v1/predict",
        code=500,
        msg="Server Error",
        hdrs={},
        fp=FakeHttpResponse({"error": "server error"}),
    )
    monkeypatch.setattr(app.urllib.request, "urlopen", Mock(side_effect=http_error))

    with pytest.raises(Exception) as excinfo:
        app.handler({}, None)

    assert "HTTP Error 500" in str(excinfo.value)
    assert len(mock_aws_services["sns"].messages) == 1
    message = json.loads(mock_aws_services["sns"].messages[0]["Message"])
    assert message["reason"] == "window_feeder_failed"
