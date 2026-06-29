# upload-slack-webhooks.ps1
# Upload Slack webhook URLs lên AWS SSM Parameter Store cho cả 3 environments
# Chạy: .\upload-slack-webhooks.ps1
# Yêu cầu: AWS CLI đã cấu hình đúng credentials + region us-east-1

$ErrorActionPreference = "Stop"
$Region = "us-east-1"
$KmsKeyId = "alias/tf4-cdo07-bootstrap-bootstrap"

$Webhooks = @(
    @{
        Env  = "sandbox"
        Name = "/tf4-cdo07/sandbox/slack-webhook-url"
        URL  = $env:SLACK_WEBHOOK_SANDBOX   # Set env var before running, e.g.: $env:SLACK_WEBHOOK_SANDBOX = "https://hooks.slack.com/services/..."
    },
    @{
        Env  = "staging"
        Name = "/tf4-cdo07/staging/slack-webhook-url"
        URL  = $env:SLACK_WEBHOOK_STAGING   # Set env var before running, e.g.: $env:SLACK_WEBHOOK_STAGING = "https://hooks.slack.com/services/..."
    },
    @{
        Env  = "prod"
        Name = "/tf4-cdo07/prod/slack-webhook-url"
        URL  = $env:SLACK_WEBHOOK_PROD      # Set env var before running, e.g.: $env:SLACK_WEBHOOK_PROD = "https://hooks.slack.com/services/..."
    }
)

Write-Host "`n=== Uploading Slack Webhook URLs to SSM ===" -ForegroundColor Cyan
Write-Host "Region  : $Region"
Write-Host "KMS Key : $KmsKeyId`n"

foreach ($item in $Webhooks) {
    Write-Host "[$($item.Env)] Uploading $($item.Name) ..." -ForegroundColor Yellow
    try {
        aws ssm put-parameter `
            --region $Region `
            --name $item.Name `
            --type SecureString `
            --value $item.URL `
            --key-id $KmsKeyId `
            --overwrite `
            --output json | Out-Null

        Write-Host "  ✅ Done" -ForegroundColor Green
    }
    catch {
        Write-Host "  ❌ FAILED: $_" -ForegroundColor Red
    }
}

Write-Host "`n=== Verifying parameters (checking Name only, not decrypting) ===" -ForegroundColor Cyan
foreach ($item in $Webhooks) {
    $result = aws ssm get-parameter `
        --region $Region `
        --name $item.Name `
        --query "Parameter.{Name:Name,Version:Version,LastModifiedDate:LastModifiedDate}" `
        --output table 2>&1
    Write-Host $result
}

Write-Host "`n✅ All done. Run smoke test next." -ForegroundColor Green
