# Mock Services - Foresight Lens TF4

Mock microservices cho testing Foresight Lens predictive monitoring system.

## 📋 Services Overview

| Service | Path Prefix | Container Port | Workload Pattern |
|---------|-------------|----------------|------------------|
| **Payment Gateway** | `/payment/*` | 3000 | Light compute, fast response (50-200ms) |
| **Ledger Service** | `/ledger/*` | 3000 | Memory-heavy, moderate latency (100-300ms) |
| **Fraud Detection** | `/fraud/*` | 3000 | CPU-intensive ML inference (80-300ms) |

## 🎯 Telemetry Schema

Tất cả services emit metrics theo **Telemetry Contract §Schema**:

```json
{
  "service_id": "payment-gw | ledger-svc | fraud-detection",
  "tenant_id": "tier-1",
  "metric_type": "cpu_utilization | memory_utilization | request_latency | throughput",
  "value": 75.5,
  "unit": "percent | milliseconds | count",
  "timestamp": "2024-01-15T10:30:00.000Z",
  "dimensions": {
    "operation": "authorize",
    "batch_size": 10
  }
}
```

### Metrics Emitted:
- **cpu_utilization** - CPU usage percentage (0-100%)
- **memory_utilization** - Memory usage percentage (0-100%)
- **request_latency** - Request processing time (milliseconds)
- **throughput** - Requests processed (count)
- **risk_score** - (Fraud Detection only) Risk assessment score (0-100)

## 🚀 Build & Deploy

### Local Development

```bash
# Payment Gateway
cd payment-gw
npm install
export KINESIS_STREAM_NAME=cdo-07-sandbox-ingest-stream
export AWS_REGION=us-east-1
npm start

# Ledger Service
cd ledger-svc
npm install
export KINESIS_STREAM_NAME=cdo-07-sandbox-ingest-stream
export AWS_REGION=us-east-1
npm start

# Fraud Detection
cd fraud-detection
npm install
export KINESIS_STREAM_NAME=cdo-07-sandbox-ingest-stream
export AWS_REGION=us-east-1
npm start
```

### Docker Build

```bash
# Build individual service
docker build -t payment-gw:latest ./payment-gw
docker build -t ledger-svc:latest ./ledger-svc
docker build -t fraud-detection:latest ./fraud-detection

# Build all services
docker build -t payment-gw:latest ./payment-gw &
docker build -t ledger-svc:latest ./ledger-svc &
docker build -t fraud-detection:latest ./fraud-detection &
wait
```

### Push to ECR

```bash
# Authenticate
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Tag and push
docker tag payment-gw:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cdo-07-payment-gw:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cdo-07-payment-gw:latest

docker tag ledger-svc:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cdo-07-ledger-svc:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cdo-07-ledger-svc:latest

docker tag fraud-detection:latest <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cdo-07-fraud-detection:latest
docker push <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com/cdo-07-fraud-detection:latest
```

## 🧪 API Endpoints

### Payment Gateway (`/payment/*`)

```bash
# Health check
curl http://ALB_DNS/health

# Authorize payment
curl -X POST http://ALB_DNS/payment/authorize \
  -H "Content-Type: application/json" \
  -d '{"amount": 100.00, "currency": "USD"}'

# Capture payment
curl -X POST http://ALB_DNS/payment/capture \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "txn_12345"}'

# Refund
curl -X POST http://ALB_DNS/payment/refund \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "txn_12345", "amount": 50.00}'

# Status check
curl http://ALB_DNS/payment/status/txn_12345
```

### Ledger Service (`/ledger/*`)

```bash
# Create ledger entry
curl -X POST http://ALB_DNS/ledger/entry \
  -H "Content-Type: application/json" \
  -d '{"account_id": "acc_12345", "amount": 100.00, "type": "debit"}'

# Get balance
curl http://ALB_DNS/ledger/balance/acc_12345

# Get transaction history
curl http://ALB_DNS/ledger/history/acc_12345

# Reconcile
curl -X POST http://ALB_DNS/ledger/reconcile \
  -H "Content-Type: application/json" \
  -d '{"account_ids": ["acc_12345", "acc_67890"]}'
```

### Fraud Detection (`/fraud/*`)

```bash
# Single fraud check
curl -X POST http://ALB_DNS/fraud/check \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "txn_12345", "amount": 5000.00}'

# Batch fraud check
curl -X POST http://ALB_DNS/fraud/batch-check \
  -H "Content-Type: application/json" \
  -d '{"transactions": [{"id": "txn_1"}, {"id": "txn_2"}]}'

# Fraud report
curl http://ALB_DNS/fraud/report/txn_12345

# Submit feedback
curl -X POST http://ALB_DNS/fraud/feedback \
  -H "Content-Type: application/json" \
  -d '{"transaction_id": "txn_12345", "is_fraud": true}'
```

## 📊 Workload Characteristics

### Payment Gateway
- **Pattern**: Bursty, short-lived requests
- **CPU**: Low-moderate (20-40%)
- **Memory**: Low (30-50%)
- **Latency**: Fast (50-200ms)
- **Use case**: High-frequency transaction processing

### Ledger Service
- **Pattern**: Steady, database-heavy operations
- **CPU**: Moderate (30-50%)
- **Memory**: High (50-80%) - caching, data processing
- **Latency**: Moderate (100-300ms)
- **Use case**: Financial record keeping, reconciliation

### Fraud Detection
- **Pattern**: Variable, ML inference spikes
- **CPU**: High (60-90%) - ML model inference
- **Memory**: Moderate (40-60%)
- **Latency**: Variable (80-300ms)
- **Use case**: Real-time risk assessment

## 🔍 Telemetry Flow

```
Mock Service → Kinesis Data Streams → Lambda Transformer → Timestream for InfluxDB
                  ↓
            (Partition by service_id)
                  ↓
         AI Engine reads 2h window
                  ↓
    Predicts drift + capacity recommendation
```

## 🏗️ Architecture Integration

Services deployed as ECS Fargate tasks behind Internal ALB:
- **VPC**: Private subnets only (no IGW/NAT)
- **ALB**: Path-based routing (`/payment/*`, `/ledger/*`, `/fraud/*`)
- **Health checks**: `GET /health` every 30s
- **Auto-scaling**: CPU > 70% triggers scale-out
- **Kinesis**: Metrics sent via PutRecords (partition key = service_id)

## 🔐 IAM Permissions

Services require:
- `kinesis:PutRecord`
- `kinesis:PutRecords`
- `kms:GenerateDataKey` (for encrypted Kinesis streams)
- `cloudwatch:PutMetricData`

Provided by task role: `${environment}-mock-svc-task-role`

## 📈 Monitoring

### CloudWatch Logs
- Log group: `/aws/ecs/${environment}-mock-services`
- Retention: 7 days
- Log streams per service: `{service_name}/{task_id}`

### Heartbeat Metrics
Services emit heartbeat metrics every 30 seconds to confirm liveness.
