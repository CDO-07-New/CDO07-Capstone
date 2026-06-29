"""
Unit + Integration tests for lambda/window-feeder/app.py
CDO-07 · Task Force 4

Cập nhật để phù hợp với việc migration từ Timestream LiveAnalytics
sang Timestream InfluxDB (Flux HTTP API + Secrets Manager token).

Tất cả AWS calls được mock — không cần AWS credentials để chạy test.
"""

import json
import os
import sys
import urllib.error
import urllib.request
from unittest.mock import MagicMock, Mock, patch

import pytest
import requests

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), ".")))

import app

# ---------------------------------------------------------------------------
# Fake AWS clients
# ---------------------------------------------------------------------------

class FakeSsmClient:
    def __init__(self):
        self.parameters: dict = {}

    def put_parameter(self, Name, Value, Type="String"):
        self.parameters[Name] = {"Value": Value, "Type": Type}

    def get_parameter(self, Name, **_kwargs):
        if Name not in self.parameters:
            raise KeyError(f"SSM parameter not found: {Name}")
        return {"Parameter": self.parameters[Name]}


class FakeSecretsManagerClient:
    """Returns a hardcoded operator_token JSON for InfluxDB auth."""

    def get_secret_value(self, SecretId, **_kwargs):
        return {
            "SecretString": json.dumps({"operator_token": "test-influxdb-token", "password": "test-password"})
        }


class FakeS3Client:
    def __init__(self):
        self.buckets: dict = {}

    def create_bucket(self, Bucket):
        self.buckets[Bucket] = {}

    def put_object(self, Bucket, Key, Body, ContentType):
        self.buckets.setdefault(Bucket, {})[Key] = {"Body": Body, "ContentType": ContentType}

    def list_objects_v2(self, Bucket):
        contents = [{"Key": k} for k in self.buckets.get(Bucket, {})]
        return {"Contents": contents} if contents else {}


class FakeSnsClient:
    def __init__(self):
        self.published: list = []

    def create_topic(self, Name):
        return {"TopicArn": f"arn:aws:sns:us-east-1:123456789012:{Name}"}

    def publish(self, **kwargs):
        self.published.append(kwargs)
        return {"MessageId": "test-message-id"}


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def mock_aws_services(monkeypatch):
    """Patch all module-level AWS clients in app.py."""
    clients = {
        "ssm":            FakeSsmClient(),
        "secretsmanager": FakeSecretsManagerClient(),
        "s3":             FakeS3Client(),
        "sns":            FakeSnsClient(),
    }
    monkeypatch.setattr(app, "ssm_client",     clients["ssm"])
    monkeypatch.setattr(app, "secretsmanager", clients["secretsmanager"])
    monkeypatch.setattr(app, "s3_client",      clients["s3"])
    monkeypatch.setattr(app, "sns_client",     clients["sns"])

    # Reset cached token so each test gets a fresh fetch
    monkeypatch.setattr(app, "_influxdb_token", None)

    yield clients


@pytest.fixture()
def set_env_vars(monkeypatch):
    """Set all required Lambda environment variables."""
    monkeypatch.setenv("AWS_REGION",                        "us-east-1")
    monkeypatch.setenv("INFLUXDB_URL",                      "https://fake-influxdb.example.com:8086")
    monkeypatch.setenv("INFLUXDB_BUCKET",                   "service-metrics")
    monkeypatch.setenv("INFLUXDB_ORG",                      "cdo-07")
    monkeypatch.setenv("INFLUXDB_SECRET_ARN",               "arn:aws:secretsmanager:us-east-1:123:secret/influxdb")
    monkeypatch.setenv("INFLUXDB_QUERY_WINDOW",             "1h")
    monkeypatch.setenv("AI_ENGINE_PREDICT_URL",             "http://test-ai-engine/v1/predict")
    monkeypatch.setenv("AI_ENGINE_TIMEOUT_SECONDS",         "5")
    monkeypatch.setenv("AUDIT_S3_BUCKET",                   "test-audit-bucket")
    monkeypatch.setenv("AUDIT_S3_PREFIX",                   "test-prefix/")
    monkeypatch.setenv("INFERENCE_ENABLED_PARAMETER_NAME",  "/test/inference-enabled")
    monkeypatch.setenv("DRIFT_ALERT_SNS_TOPIC_ARN",         "arn:aws:sns:us-east-1:123456789012:test-drift-topic")
    monkeypatch.setenv("BASELINE_S3_BUCKET",                "test-baseline-bucket")


# Minimal Flux CSV response (annotated CSV format returned by InfluxDB v2)
FAKE_FLUX_CSV = """\
#group,false,false,true,true,false,false,true,true
#datatype,string,long,dateTime:RFC3339,dateTime:RFC3339,dateTime:RFC3339,double,string,string
#default,_result,,,,,,,
,result,table,_start,_stop,time,value,metric_type,service_id,tenant_id
,_result,0,2026-06-29T08:00:00Z,2026-06-29T10:00:00Z,2026-06-29T09:00:00Z,85.5,cpu_usage_percent,payment-gateway,tnt-test

"""


# ---------------------------------------------------------------------------
# Helper Tests — SSM gate
# ---------------------------------------------------------------------------

class TestIsInferenceEnabled:

    def test_enabled(self, mock_aws_services, set_env_vars):
        mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true")
        assert app.is_inference_enabled() is True

    def test_disabled(self, mock_aws_services, set_env_vars):
        mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="false")
        assert app.is_inference_enabled() is False

    def test_ssm_error_defaults_to_disabled(self, mock_aws_services, set_env_vars):
        # Parameter does not exist → KeyError → should return False (fail-safe)
        result = app.is_inference_enabled()
        assert result is False


# ---------------------------------------------------------------------------
# Helper Tests — InfluxDB token fetch
# ---------------------------------------------------------------------------

class TestGetInfluxDBToken:

    def test_fetches_operator_token(self, mock_aws_services, set_env_vars):
        token = app._get_influxdb_token()
        assert token == "test-influxdb-token"

    def test_caches_token(self, mock_aws_services, set_env_vars):
        """Second call must not call Secrets Manager again."""
        t1 = app._get_influxdb_token()
        # Replace secretsmanager with one that raises if called
        broken = Mock(side_effect=RuntimeError("should not be called"))
        import app as app_module
        app_module._influxdb_token = t1  # already cached
        # Should not raise
        t2 = app._get_influxdb_token()
        assert t1 == t2


# ---------------------------------------------------------------------------
# Helper Tests — Flux CSV parser
# ---------------------------------------------------------------------------

class TestParseFluxCsv:

    def test_parses_rows(self):
        rows = app._parse_flux_csv(FAKE_FLUX_CSV)
        assert len(rows) == 1
        row = rows[0]
        assert row["service_id"] == "payment-gateway"
        assert row["metric_type"] == "cpu_usage_percent"
        assert abs(row["value"] - 85.5) < 0.001
        assert row["tenant_id"] == "tnt-test"

    def test_empty_csv_returns_empty_list(self):
        rows = app._parse_flux_csv("")
        assert rows == []

    def test_annotation_only_returns_empty_list(self):
        rows = app._parse_flux_csv("#group,false\n#datatype,string\n")
        assert rows == []


# ---------------------------------------------------------------------------
# Helper Tests — InfluxDB query
# ---------------------------------------------------------------------------

class TestQueryInfluxdbMetrics:

    def test_returns_rows(self, mock_aws_services, set_env_vars, monkeypatch):
        # Patch urllib.request.urlopen to return fake CSV
        fake_resp = MagicMock()
        fake_resp.__enter__ = lambda s: s
        fake_resp.__exit__ = MagicMock(return_value=False)
        fake_resp.read.return_value = FAKE_FLUX_CSV.encode("utf-8")

        monkeypatch.setattr(urllib.request, "urlopen", lambda req, timeout=None: fake_resp)

        result = app.query_influxdb_metrics()

        assert result["source"] == "influxdb"
        assert len(result["rows"]) == 1
        assert result["rows"][0]["service_id"] == "payment-gateway"

    def test_raises_on_http_error(self, mock_aws_services, set_env_vars, monkeypatch):
        def raise_http_error(req, timeout=None):
            raise urllib.error.HTTPError(
                url="http://fake", code=401,
                msg="Unauthorized", hdrs=None, fp=None
            )
        monkeypatch.setattr(urllib.request, "urlopen", raise_http_error)

        with pytest.raises(urllib.error.HTTPError):
            app.query_influxdb_metrics()


# ---------------------------------------------------------------------------
# Helper Tests — Audit log
# ---------------------------------------------------------------------------

class TestWriteAuditLog:

    def test_writes_to_s3(self, mock_aws_services, set_env_vars):
        mock_aws_services["s3"].create_bucket(Bucket="test-audit-bucket")
        app.write_audit_log({"input": "data"}, {"output": "data"})

        objects = mock_aws_services["s3"].list_objects_v2(Bucket="test-audit-bucket")
        assert len(objects["Contents"]) == 1
        assert objects["Contents"][0]["Key"].startswith("test-prefix/")

    def test_does_not_raise_on_s3_error(self, mock_aws_services, set_env_vars, monkeypatch):
        """Audit failure is non-fatal."""
        def raise_exc(**_):
            raise RuntimeError("S3 unavailable")
        monkeypatch.setattr(mock_aws_services["s3"], "put_object", raise_exc)
        # Must NOT raise
        app.write_audit_log({}, {})


# ---------------------------------------------------------------------------
# Helper Tests — Drift alert
# ---------------------------------------------------------------------------

class TestPublishDriftAlert:

    def test_publishes_when_anomaly_true(self, mock_aws_services, set_env_vars):
        app.publish_drift_alert({"anomaly": True, "severity": 0.9,
                                 "recommendation": {"action_verb": "scale", "target": "ecs"},
                                 "reasoning": "CPU spike", "audit_id": "abc"})
        assert len(mock_aws_services["sns"].published) == 1

    def test_does_not_publish_when_anomaly_false(self, mock_aws_services, set_env_vars):
        app.publish_drift_alert({"anomaly": False})
        assert len(mock_aws_services["sns"].published) == 0

    def test_does_not_publish_when_anomaly_missing(self, mock_aws_services, set_env_vars):
        app.publish_drift_alert({})
        assert len(mock_aws_services["sns"].published) == 0


# ---------------------------------------------------------------------------
# Integration Tests — handler
# ---------------------------------------------------------------------------

SAMPLE_AI_RESPONSE_DRIFT = {
    "anomaly": True,
    "severity": 0.85,
    "recommendation": {"action_verb": "scale", "target": "payment-gateway"},
    "reasoning": "CPU > 85% sustained",
    "audit_id": "test-audit-123",
}

SAMPLE_AI_RESPONSE_NO_DRIFT = {
    "anomaly": False,
    "severity": 0.1,
    "recommendation": {},
    "reasoning": "Within normal bounds",
    "audit_id": "test-audit-456",
}


class TestHandler:

    def _patch_influxdb_query(self, monkeypatch, csv_response=FAKE_FLUX_CSV):
        """Patch urllib.request.urlopen to return given CSV for InfluxDB queries."""
        fake_resp = MagicMock()
        fake_resp.__enter__ = lambda s: s
        fake_resp.__exit__ = MagicMock(return_value=False)
        fake_resp.read.return_value = csv_response.encode("utf-8")
        monkeypatch.setattr(urllib.request, "urlopen", lambda req, timeout=None: fake_resp)

    def test_happy_path_with_drift(self, mock_aws_services, set_env_vars, monkeypatch):
        """Full flow: inference enabled → query → AI detects drift → audit + alert."""
        mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true")
        mock_aws_services["s3"].create_bucket(Bucket="test-audit-bucket")

        self._patch_influxdb_query(monkeypatch)

        mock_ai_resp = Mock()
        mock_ai_resp.status_code = 200
        mock_ai_resp.json.return_value = SAMPLE_AI_RESPONSE_DRIFT
        mock_ai_resp.raise_for_status.return_value = None
        monkeypatch.setattr(requests, "post", Mock(return_value=mock_ai_resp))

        response = app.handler({}, None)

        assert response["statusCode"] == 200
        body = json.loads(response["body"])
        assert body["anomaly"] is True

        # Audit was written
        objects = mock_aws_services["s3"].list_objects_v2(Bucket="test-audit-bucket")
        assert len(objects["Contents"]) == 1

        # SNS alert was published
        assert len(mock_aws_services["sns"].published) == 1

    def test_happy_path_no_drift(self, mock_aws_services, set_env_vars, monkeypatch):
        """Full flow: inference enabled → query → AI no drift → audit written, no SNS."""
        mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true")
        mock_aws_services["s3"].create_bucket(Bucket="test-audit-bucket")

        self._patch_influxdb_query(monkeypatch)

        mock_ai_resp = Mock()
        mock_ai_resp.status_code = 200
        mock_ai_resp.json.return_value = SAMPLE_AI_RESPONSE_NO_DRIFT
        mock_ai_resp.raise_for_status.return_value = None
        monkeypatch.setattr(requests, "post", Mock(return_value=mock_ai_resp))

        response = app.handler({}, None)

        assert response["statusCode"] == 200
        # No SNS published
        assert len(mock_aws_services["sns"].published) == 0

    def test_inference_disabled_exits_early(self, mock_aws_services, set_env_vars):
        """If SSM flag is false, handler exits immediately without querying InfluxDB."""
        mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="false")

        response = app.handler({}, None)

        assert response["statusCode"] == 200
        assert response["body"] == "Inference disabled."

    def test_no_metrics_exits_gracefully(self, mock_aws_services, set_env_vars, monkeypatch):
        """If InfluxDB returns no rows, handler exits without calling AI Engine."""
        mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true")

        # Return empty CSV
        self._patch_influxdb_query(monkeypatch, csv_response="")

        mock_post = Mock()
        monkeypatch.setattr(requests, "post", mock_post)

        response = app.handler({}, None)

        assert response["statusCode"] == 200
        assert "No metrics" in response["body"]
        mock_post.assert_not_called()

    def test_ai_engine_failure_raises(self, mock_aws_services, set_env_vars, monkeypatch):
        """AI Engine HTTP 500 should propagate so Lambda marks invocation failed."""
        mock_aws_services["ssm"].put_parameter(Name="/test/inference-enabled", Value="true")
        mock_aws_services["s3"].create_bucket(Bucket="test-audit-bucket")

        self._patch_influxdb_query(monkeypatch)

        mock_ai_resp = Mock()
        mock_ai_resp.raise_for_status.side_effect = requests.exceptions.HTTPError("500 Server Error")
        monkeypatch.setattr(requests, "post", Mock(return_value=mock_ai_resp))

        with pytest.raises(Exception) as exc_info:
            app.handler({}, None)

        assert "500 Server Error" in str(exc_info.value)
