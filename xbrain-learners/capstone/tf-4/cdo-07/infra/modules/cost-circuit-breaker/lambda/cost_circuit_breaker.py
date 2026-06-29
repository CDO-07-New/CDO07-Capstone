import json
import logging
import os

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")
sns = boto3.client("sns")


def handler(event, context):
    parameter_name = os.environ["SSM_PARAMETER_NAME"]
    disabled_value = os.environ.get("DISABLED_VALUE", "false")
    alert_topic_arn = os.environ.get("ALERT_SNS_TOPIC_ARN", "")
    reason = os.environ.get("CIRCUIT_BREAKER_REASON", "cost_guardrail_breach")

    response = ssm.put_parameter(
        Name=parameter_name,
        Type="SecureString",
        Value=disabled_value,
        Overwrite=True,
    )

    logger.info(
        "cost circuit breaker disabled inference: parameter=%s version=%s request_id=%s reason=%s",
        parameter_name,
        response.get("Version"),
        getattr(context, "aws_request_id", None),
        reason,
    )

    if alert_topic_arn:
        message = {
            "source": "cost-circuit-breaker",
            "reason": reason,
            "parameter_name": parameter_name,
            "inference_enabled": disabled_value,
            "request_id": getattr(context, "aws_request_id", None),
            "event": event,
        }
        sns.publish(
            TopicArn=alert_topic_arn,
            Subject=f"[CDO-07] Cost circuit breaker tripped ({reason})",
            Message=json.dumps(message, default=str),
        )

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "parameter_name": parameter_name,
                "value": disabled_value,
                "version": response.get("Version"),
                "reason": reason,
            }
        ),
    }
