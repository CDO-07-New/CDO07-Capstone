/**
 * Payment Gateway Mock Service
 * 
 * Emits telemetry metrics to Kinesis Data Streams
 * Simulates realistic payment processing workload with CPU/memory patterns
 * 
 * Contract: Telemetry Contract §Schema
 * - service_id: "payment-gw"
 * - metric_type: cpu_utilization, memory_utilization, request_latency, throughput
 * - tenant_id: mandatory
 */

const express = require('express');
const AWS = require('aws-sdk');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_NAME = process.env.SERVICE_NAME || 'payment-gw';
const KINESIS_STREAM_NAME = process.env.KINESIS_STREAM_NAME;
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';

// Initialize Kinesis client
const kinesis = new AWS.Kinesis({ region: AWS_REGION });

// Middleware
app.use(express.json());

// Health check endpoint (required by ALB target group)
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: SERVICE_NAME });
});

// Payment endpoints
app.post('/payment/authorize', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate payment processing (50-200ms)
  const processingTime = 50 + Math.random() * 150;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  
  // Emit telemetry
  await emitMetrics('authorize', latency);
  
  res.status(200).json({
    transaction_id: `txn_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    status: 'authorized',
    amount: req.body.amount || 100.00,
    latency_ms: latency
  });
});

app.post('/payment/capture', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate capture processing (30-120ms)
  const processingTime = 30 + Math.random() * 90;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  
  // Emit telemetry
  await emitMetrics('capture', latency);
  
  res.status(200).json({
    transaction_id: req.body.transaction_id || `txn_${Date.now()}`,
    status: 'captured',
    latency_ms: latency
  });
});

app.post('/payment/refund', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate refund processing (80-250ms)
  const processingTime = 80 + Math.random() * 170;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  
  // Emit telemetry
  await emitMetrics('refund', latency);
  
  res.status(200).json({
    refund_id: `ref_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    status: 'refunded',
    latency_ms: latency
  });
});

app.get('/payment/status/:txnId', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate status check (10-50ms)
  const processingTime = 10 + Math.random() * 40;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  
  // Emit telemetry
  await emitMetrics('status_check', latency);
  
  res.status(200).json({
    transaction_id: req.params.txnId,
    status: 'completed',
    latency_ms: latency
  });
});

/**
 * Emit telemetry metrics to Kinesis
 * Format matches Telemetry Contract §Schema requirements
 */
async function emitMetrics(operation, latency) {
  if (!KINESIS_STREAM_NAME) {
    console.log('[WARN] KINESIS_STREAM_NAME not set, skipping telemetry');
    return;
  }

  const timestamp = new Date().toISOString();
  const cpuUsage = os.loadavg()[0] * 10; // Normalize to percentage
  const memUsage = (1 - os.freemem() / os.totalmem()) * 100;
  
  const metrics = [
    {
      ts: timestamp,
      tenant_id: 'tier-1',
      service_id: SERVICE_NAME,
      metric_type: 'cpu_usage_percent',
      value: Math.min(100, cpuUsage + Math.random() * 10),
      labels: { operation }
    },
    {
      ts: timestamp,
      tenant_id: 'tier-1',
      service_id: SERVICE_NAME,
      metric_type: 'memory_usage_percent',
      value: Math.min(100, memUsage + Math.random() * 5),
      labels: { operation }
    },
    {
      ts: timestamp,
      tenant_id: 'tier-1',
      service_id: SERVICE_NAME,
      metric_type: 'api_latency_ms',
      value: latency,
      labels: { operation }
    }
  ];

  try {
    const records = metrics.map(metric => ({
      Data: JSON.stringify(metric),
      PartitionKey: 'tier-1' // Use tenant_id for proper multi-tenant isolation
    }));

    await kinesis.putRecords({
      Records: records,
      StreamName: KINESIS_STREAM_NAME
    }).promise();

    console.log(`[TELEMETRY] Sent ${records.length} metrics for ${operation}`);
  } catch (error) {
    console.error('[ERROR] Failed to send telemetry:', error.message);
  }
}

// Periodic heartbeat metrics (every 30 seconds)
setInterval(async () => {
  await emitMetrics('heartbeat', 0);
}, 30000);

app.listen(PORT, () => {
  console.log(`[${SERVICE_NAME}] Running on port ${PORT}`);
  console.log(`[${SERVICE_NAME}] Kinesis stream: ${KINESIS_STREAM_NAME}`);
  console.log(`[${SERVICE_NAME}] AWS Region: ${AWS_REGION}`);
});
