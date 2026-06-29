import json
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.dirname(__file__))

import cost_circuit_breaker


class CostCircuitBreakerHandlerTest(unittest.TestCase):
    @patch.dict(
        os.environ,
        {
            "SSM_PARAMETER_NAME": "/tf4-cdo07/smoke/inference_enabled",
            "DISABLED_VALUE": "false",
            "ALERT_SNS_TOPIC_ARN": "arn:aws:sns:us-east-1:123456789012:alerts",
            "CIRCUIT_BREAKER_REASON": "cost_guardrail_breach",
        },
    )
    @patch.object(cost_circuit_breaker.sns, "publish")
    @patch.object(cost_circuit_breaker.ssm, "put_parameter")
    def test_handler_sets_inference_enabled_false_and_publishes_alert(
        self,
        mock_put_parameter,
        mock_sns_publish,
    ):
        mock_put_parameter.return_value = {"Version": 3}
        context = MagicMock(aws_request_id="req-123")

        result = cost_circuit_breaker.handler({"Records": []}, context)

        mock_put_parameter.assert_called_once_with(
            Name="/tf4-cdo07/smoke/inference_enabled",
            Type="SecureString",
            Value="false",
            Overwrite=True,
        )
        mock_sns_publish.assert_called_once()
        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertEqual(body["parameter_name"], "/tf4-cdo07/smoke/inference_enabled")
        self.assertEqual(body["value"], "false")
        self.assertEqual(body["version"], 3)
        self.assertEqual(body["reason"], "cost_guardrail_breach")


if __name__ == "__main__":
    unittest.main()
