import json
import os
import urllib.request


MAX_TEXT_LEN = 2800
MAX_HEADER_LEN = 150


def get_slack_webhook():
    """
    Retrieves the Slack Webhook URL.
    1. Check for standard SLACK_WEBHOOK_URL environment variable first.
    2. Check SLACK_WEBHOOK_PARAMETER_NAME to query SSM Parameter Store.
    """
    webhook_url = os.environ.get("SLACK_WEBHOOK_URL")
    if webhook_url:
        return webhook_url

    ssm_parameter_name = os.environ.get("SLACK_WEBHOOK_PARAMETER_NAME")
    if ssm_parameter_name:
        try:
            import boto3

            print(f"Fetching Slack Webhook URL from SSM Parameter Store: {ssm_parameter_name}")
            ssm = boto3.client("ssm")
            response = ssm.get_parameter(Name=ssm_parameter_name, WithDecryption=True)
            return response["Parameter"]["Value"]
        except Exception as exc:
            print(
                "CRITICAL: Failed to retrieve Slack Webhook from SSM Parameter Store "
                f"({ssm_parameter_name}): {exc}"
            )

    return None


def _truncate(value, max_len=MAX_TEXT_LEN):
    text = str(value)
    if len(text) <= max_len:
        return text
    return text[: max_len - 3] + "..."


def _pct(value):
    if value is None:
        return "N/A"
    try:
        return f"{float(value) * 100:.0f}%"
    except (TypeError, ValueError):
        return str(value)


def _plain_header(text):
    return _truncate(text, MAX_HEADER_LEN)


def _json_block(value):
    body = json.dumps(value, indent=2, default=str)
    return f"```json\n{_truncate(body, 2400)}\n```"


def _format_evidence_link(url):
    if not url:
        return "N/A"
    return f"<{url}|Open evidence>"


def _extract_drift_responses(details):
    if not isinstance(details, dict):
        return []
    if isinstance(details.get("responses"), list):
        return [item for item in details["responses"] if isinstance(item, dict)]
    return [details]


def _format_drift_alert(subject, parsed_msg, sns_timestamp):
    details = parsed_msg.get("details", {})
    responses = _extract_drift_responses(details)
    anomaly_count = sum(
        1 for item in responses
        if item.get("anomaly") or item.get("drift_detected")
    )
    max_severity = max([float(item.get("severity") or 0) for item in responses] or [0])

    blocks = [
        {
            "type": "header",
            "text": {
                "type": "plain_text",
                "text": _plain_header(f":rotating_light: {subject}"),
                "emoji": True,
            },
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Reason:*\n`{parsed_msg.get('reason', 'N/A')}`"},
                {"type": "mrkdwn", "text": f"*Source:*\n`{parsed_msg.get('source', 'N/A')}`"},
                {"type": "mrkdwn", "text": f"*Affected services:*\n`{anomaly_count}`"},
                {"type": "mrkdwn", "text": f"*Max severity:*\n`{_pct(max_severity)}`"},
            ],
        },
        {"type": "divider"},
    ]

    for index, item in enumerate(responses[:8], start=1):
        service_id = item.get("tenant_id") or item.get("service_id") or "unknown-service"
        recommendation = item.get("recommendation") or {}
        action = recommendation.get("action_verb", "N/A")
        target = recommendation.get("target", f"{service_id} Resource")
        change = recommendation.get("from_to", "N/A")
        confidence = _pct(recommendation.get("confidence"))
        evidence = _format_evidence_link(recommendation.get("evidence_link"))
        severity = _pct(item.get("severity"))
        reasoning = item.get("reasoning", "No reasoning provided.")
        audit_id = item.get("audit_id", "N/A")
        correlation_id = item.get("correlation_id", "N/A")

        blocks.append({
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": f"*{index}. {service_id}*\n> {_truncate(reasoning, 600)}",
            },
        })
        blocks.append({
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": f"*Severity:*\n`{severity}`"},
                {"type": "mrkdwn", "text": f"*Action:*\n`{action}`"},
                {"type": "mrkdwn", "text": f"*Target:*\n`{target}`"},
                {"type": "mrkdwn", "text": f"*Change:*\n`{change}`"},
                {"type": "mrkdwn", "text": f"*Confidence:*\n`{confidence}`"},
                {"type": "mrkdwn", "text": f"*Evidence:*\n{evidence}"},
            ],
        })
        blocks.append({
            "type": "context",
            "elements": [
                {
                    "type": "mrkdwn",
                    "text": f"*Audit:* `{audit_id}` | *Correlation:* `{correlation_id}`",
                }
            ],
        })

    if len(responses) > 8:
        blocks.append({
            "type": "context",
            "elements": [
                {"type": "mrkdwn", "text": f"_Showing first 8 of {len(responses)} service responses._"}
            ],
        })

    blocks.append({"type": "divider"})
    blocks.append({
        "type": "context",
        "elements": [
            {"type": "mrkdwn", "text": f"*Time:* {sns_timestamp} | *Source:* AWS SNS"}
        ],
    })

    return {
        "text": f":rotating_light: {subject} - {anomaly_count} service(s) affected",
        "attachments": [{"color": "#E01E5A", "blocks": blocks}],
    }


def _format_generic_json_message(subject, parsed_msg, sns_timestamp, color, emoji):
    fields_text = ""
    for key, val in parsed_msg.items():
        formatted_key = key.replace("_", " ").replace("-", " ").title()
        if isinstance(val, (dict, list)):
            formatted_val = f"\n{_json_block(val)}"
        else:
            formatted_val = f"`{val}`"
        fields_text += f"*{formatted_key}:* {formatted_val}\n"

    blocks = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": _plain_header(f"{emoji} {subject}"), "emoji": True},
        },
        {
            "type": "section",
            "text": {"type": "mrkdwn", "text": fields_text or "_Empty JSON properties_"},
        },
        {
            "type": "context",
            "elements": [{"type": "mrkdwn", "text": f"*Time:* {sns_timestamp} | *Source:* AWS SNS"}],
        },
    ]
    return {"text": f"{emoji} {subject}", "attachments": [{"color": color, "blocks": blocks}]}


def format_slack_message(subject, message, sns_timestamp):
    """
    Formats an SNS notification into Slack Block Kit.
    Drift alerts get a first-class, service-by-service layout.
    Other JSON alerts still render as readable fields.
    """
    color = "#36a64f"
    emoji = ":information_source:"
    subject_lower = subject.lower()

    if any(kwd in subject_lower for kwd in ["critical", "fail", "error", "drift-alert", "drift"]):
        color = "#E01E5A"
        emoji = ":rotating_light:"
    elif any(kwd in subject_lower for kwd in ["warning", "warn", "budget-alert", "budget"]):
        color = "#FF9900"
        emoji = ":warning:"
    elif any(kwd in subject_lower for kwd in ["resolve", "ok", "success", "recovered"]):
        color = "#2EB67D"
        emoji = ":white_check_mark:"

    parsed_msg = None
    try:
        parsed_msg = json.loads(message)
    except Exception:
        pass

    if parsed_msg and isinstance(parsed_msg, dict):
        if parsed_msg.get("reason") == "drift_detected" and isinstance(parsed_msg.get("details"), dict):
            return _format_drift_alert(subject, parsed_msg, sns_timestamp)
        return _format_generic_json_message(subject, parsed_msg, sns_timestamp, color, emoji)

    blocks = [
        {
            "type": "header",
            "text": {"type": "plain_text", "text": _plain_header(f"{emoji} {subject}"), "emoji": True},
        },
        {"type": "section", "text": {"type": "mrkdwn", "text": _truncate(message)}},
        {
            "type": "context",
            "elements": [{"type": "mrkdwn", "text": f"*Time:* {sns_timestamp} | *Source:* AWS SNS"}],
        },
    ]

    return {"text": f"{emoji} {subject}", "attachments": [{"color": color, "blocks": blocks}]}


def lambda_handler(event, context):
    print("Received event:", json.dumps(event))
    webhook_url = get_slack_webhook()

    if not webhook_url:
        print("CRITICAL ERROR: Slack Webhook URL is not configured. Verify env variables and SSM permissions.")
        return {"statusCode": 500, "body": "Configuration Error: Slack Webhook URL missing."}

    for record in event.get("Records", []):
        sns = record.get("Sns", {})
        subject = sns.get("Subject") or "AWS Alert Notification"
        message = sns.get("Message") or "No details provided."
        timestamp = sns.get("Timestamp") or "N/A"

        slack_payload = format_slack_message(subject, message, timestamp)

        req = urllib.request.Request(
            webhook_url,
            data=json.dumps(slack_payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )

        try:
            print(f"Sending payload to Slack Webhook for Subject: {subject}")
            with urllib.request.urlopen(req) as response:
                resp_body = response.read().decode("utf-8")
                print(f"Slack webhook endpoint response: {resp_body}")
        except Exception as exc:
            print(f"ERROR: Failed to deliver message to Slack: {exc}")
            return {"statusCode": 500, "body": f"Failed to forward message: {exc}"}

    return {"statusCode": 200, "body": "Events processed and forwarded successfully."}
