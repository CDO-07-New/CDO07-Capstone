# Window Feeder Lambda

Python Lambda source for the Layer 4 EventBridge Window Feeder.

## Runtime contract

- Handler: `app.handler`
- Runtime: `python3.12`
- Package path expected by Terraform: `build/window-feeder.zip`

## Flow

1. Read `INFERENCE_ENABLED_PARAMETER_NAME` from SSM.
2. Query Amazon Timestream over `TIMESTREAM_QUERY_WINDOW` plus a short lookback.
3. Build a regular metric grid and forward-fill missing buckets before posting to AI Engine `/v1/predict`.
4. Write audit JSON to S3.
5. Publish SNS alert when drift is detected or the feeder fails.

## Build

From the infra directory:

```powershell
Compress-Archive -Path lambda/window-feeder/* -DestinationPath build/window-feeder.zip -Force
```
