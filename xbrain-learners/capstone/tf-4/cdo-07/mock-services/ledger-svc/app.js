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
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_NAME = process.env.SERVICE_NAME || 'ledger-svc';
const KINESIS_STREAM_NAME = process.env.KINESIS_STREAM_NAME;
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';

// Initialize Kinesis client
const kinesis = new AWS.Kinesis({ region: AWS_REGION });

// Middleware
app.use(express.json());

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
  
  // Emit telemetry
  await emitMetrics('create_entry', latency);
  
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
  
  // Emit telemetry
  await emitMetrics('balance_query', latency);
  
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
  
  // Emit telemetry
  await emitMetrics('history_query', latency);
  
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
  
  // Emit telemetry
  await emitMetrics('reconciliation', latency);
  
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
async function emitMetrics(operation, latency) {
  if (!KINESIS_STREAM_NAME) {
    console.log('[WARN] KINESIS_STREAM_NAME not set, skipping telemetry');
    return;
  }

  const timestamp = new Date().toISOString();
  const cpuUsage = os.loadavg()[0] * 10;
  const memUsage = (1 - os.freemem() / os.totalmem()) * 100;
  
  // Ledger service tends to use more memory (add 10-20% baseline)
  const ledgerMemAdjustment = 15 + Math.random() * 5;
  
  const metrics = [
    {
      ts: timestamp,
      tenant_id: 'tier-1',
      service_id: SERVICE_NAME,
      metric_type: 'cpu_usage_percent',
      value: Math.min(100, cpuUsage + Math.random() * 15), // Slightly higher CPU
      labels: { operation }
    },
    {
      ts: timestamp,
      tenant_id: 'tier-1',
      service_id: SERVICE_NAME,
      metric_type: 'memory_usage_percent',
      value: Math.min(100, memUsage + ledgerMemAdjustment),
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
