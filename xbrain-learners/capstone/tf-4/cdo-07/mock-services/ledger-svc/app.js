/**
 * Ledger Service Mock
 * 
 * Emits telemetry metrics to Kinesis Data Streams
 * Simulates financial ledger operations with database-heavy workload patterns
 * 
 * Contract: Telemetry Contract §Schema
 * - service_id: "ledger-svc"
 * - metric_type: cpu_utilization, memory_utilization, request_latency, throughput
 * - tenant_id: mandatory
 */

const express = require('express');
const AWS = require('aws-sdk');

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_NAME = process.env.SERVICE_NAME || 'ledger-svc';
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

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: SERVICE_NAME });
});

// Ledger endpoints
app.post('/ledger/entry', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate database write (100-300ms - heavier than payment)
  const processingTime = 100 + Math.random() * 200;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('create_entry', latency, tenantId);
  
  res.status(201).json({
    entry_id: `ledger_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    account_id: req.body.account_id || 'acc_12345',
    amount: req.body.amount || 0,
    type: req.body.type || 'debit',
    status: 'recorded',
    latency_ms: latency
  });
});

app.get('/ledger/balance/:accountId', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate balance query (60-180ms)
  const processingTime = 60 + Math.random() * 120;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('balance_query', latency, tenantId);
  
  res.status(200).json({
    account_id: req.params.accountId,
    balance: (Math.random() * 10000).toFixed(2),
    currency: 'USD',
    latency_ms: latency
  });
});

app.get('/ledger/history/:accountId', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate history query (150-400ms - heavy query)
  const processingTime = 150 + Math.random() * 250;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('history_query', latency, tenantId);
  
  // Generate mock transaction history
  const history = Array.from({ length: 10 }, (_, i) => ({
    entry_id: `ledger_${Date.now() - i * 1000}`,
    type: Math.random() > 0.5 ? 'credit' : 'debit',
    amount: (Math.random() * 500).toFixed(2),
    timestamp: new Date(Date.now() - i * 86400000).toISOString()
  }));
  
  res.status(200).json({
    account_id: req.params.accountId,
    entries: history,
    latency_ms: latency
  });
});

app.post('/ledger/reconcile', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate reconciliation (200-500ms - very heavy)
  const processingTime = 200 + Math.random() * 300;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('reconciliation', latency, tenantId);
  
  res.status(200).json({
    reconciliation_id: `recon_${Date.now()}`,
    status: 'completed',
    discrepancies: Math.floor(Math.random() * 5),
    latency_ms: latency
  });
});

/**
 * Emit telemetry metrics to Kinesis
 * Ledger service typically has higher memory usage due to data processing
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
      // baseline (20 RPS total) -> cpu ~ 35-50%
      // spike (100+ RPS total) -> cpu ~ 80-100%
      value: Math.min(100, Math.max(15, 20 + (currentRps * 1.0) + Math.random() * 10)),
      labels: { operation }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'memory_usage_percent',
      // Memory increases under DB workload pressure
      value: Math.min(100, Math.max(15, 30 + (currentRps * 0.6) + Math.random() * 5)),
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
      // Ledger SQS queue depth - grows when request rate increases
      metric_type: 'queue_depth',
      value: Math.max(0, Math.floor((currentRps * 0.3) * (1 + Math.random() * 0.2))),
      labels: { operation, queue_name: 'ledger-events-sqs' }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      // DB connection pool % - grows under request rate (ledger-svc is DB-heavy)
      metric_type: 'db_connection_pool_pct',
      value: Math.min(100, Math.max(10, 30 + (currentRps * 0.5) + Math.random() * 5)),
      labels: { operation, db_type: 'mysql' }
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
