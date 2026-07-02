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

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_NAME = process.env.SERVICE_NAME || 'payment-gw';
const KINESIS_STREAM_NAME = process.env.KINESIS_STREAM_NAME;
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';

// Initialize Kinesis client
const kinesis = new AWS.Kinesis({ region: AWS_REGION });

// Request rate counter for dynamic metric simulation
let requestCounter = 0;
let currentRps = 0;
setInterval(() => {
  currentRps = requestCounter;
  requestCounter = 0;
}, 1000);

// Middleware
app.use(express.json());
app.use((req, res, next) => {
  if (req.path !== '/health') {
    requestCounter++;
  }
  next();
});

// Helper to extract tenant_id from request
function getTenantId(req) {
  return req.headers['x-tenant-id'] || req.body?.tenant_id || 'tier-1';
}

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
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('authorize', latency, tenantId);
  
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
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('capture', latency, tenantId);
  
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
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('refund', latency, tenantId);
  
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
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('status_check', latency, tenantId);
  
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
async function emitMetrics(operation, latency, tenantId = 'tier-1') {
  if (!KINESIS_STREAM_NAME) {
    console.log('[WARN] KINESIS_STREAM_NAME not set, skipping telemetry');
    return;
  }

  const timestamp = new Date().toISOString();
  
  const metrics = [
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'cpu_usage_percent',
      // Simulate CPU load based on request throughput (RPS):
      // baseline (80 RPS total) -> cpu ~ 25-45%
      // spike (300+ RPS total) -> cpu ~ 80-100%
      value: Math.min(100, Math.max(10, 15 + (currentRps * 0.3) + Math.random() * 10)),
      labels: { operation }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'memory_usage_percent',
      // Memory slightly increases under workload pressure
      value: Math.min(100, Math.max(15, 25 + (currentRps * 0.15) + Math.random() * 5)),
      labels: { operation }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'api_latency_ms',
      value: latency,
      labels: { operation }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      // Simulate payment processing queue depth proportional to RPS
      metric_type: 'queue_depth',
      value: Math.max(0, Math.floor((currentRps * 0.15) * (1 + Math.random() * 0.2))),
      labels: { operation, queue_name: 'payment-processing-queue' }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      // Active connections simulated from request rate
      metric_type: 'active_connections',
      value: Math.max(1, Math.floor(currentRps * 0.4 + Math.random() * 10)),
      labels: { operation }
    }
  ];

  try {
    const records = metrics.map(metric => ({
      Data: JSON.stringify(metric),
      PartitionKey: tenantId // Use tenant_id for proper multi-tenant isolation
    }));

    await kinesis.putRecords({
      Records: records,
      StreamName: KINESIS_STREAM_NAME
    }).promise();

    console.log(`[TELEMETRY] Sent ${records.length} metrics for ${operation} (tenant: ${tenantId})`);
  } catch (error) {
    console.error('[ERROR] Failed to send telemetry:', error.message);
  }
}

// Periodic heartbeat metrics disabled to reduce Kinesis costs in mock environment
// setInterval(async () => {
//   await emitMetrics('heartbeat', 0, SERVICE_NAME);
// }, 30000);

app.listen(PORT, () => {
  console.log(`[${SERVICE_NAME}] Running on port ${PORT}`);
  console.log(`[${SERVICE_NAME}] Kinesis stream: ${KINESIS_STREAM_NAME}`);
  console.log(`[${SERVICE_NAME}] AWS Region: ${AWS_REGION}`);
  console.log(`[${SERVICE_NAME}] Heartbeat metrics: DISABLED (cost savings)`);
});
