# Window Feeder Lambda

Python Lambda source for the Layer 4 EventBridge Window Feeder.

## Runtime contract

- Handler: `app.handler`
- Runtime: `python3.12`
- Package path expected by Terraform: `build/window-feeder.zip`

## Flow

1. Read `INFERENCE_ENABLED_PARAMETER_NAME` from SSM.
2. Query Amazon Timestream for InfluxDB over `INFLUXDB_QUERY_WINDOW` plus a short lookback.
3. Build a regular metric grid and forward-fill missing buckets before posting to AI Engine `/v1/predict`.
4. Publish SNS alert when drift is detected or the feeder fails.

## Build

The Terraform environments expect this deployment package:

```text
lambda/window-feeder/build/window-feeder.zip
```

The `build/` directory is gitignored, so every developer must recreate the zip locally after pulling the repo or changing `app.py`.

From the `infra` directory:

```powershell
New-Item -ItemType Directory -Force -Path lambda\window-feeder\build
Compress-Archive -Path lambda\window-feeder\app.py -DestinationPath lambda\window-feeder\build\window-feeder.zip -Force
```

No third-party runtime dependencies are required. The Lambda uses Python standard-library HTTP clients plus the AWS SDK modules available in the Lambda runtime.

Before running Terraform, verify the package exists:

```powershell
Test-Path lambda\window-feeder\build\window-feeder.zip
```
