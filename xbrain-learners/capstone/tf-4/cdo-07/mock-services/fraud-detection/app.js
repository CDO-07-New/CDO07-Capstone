/**
 * Fraud Detection Service Mock
 * 
 * Emits telemetry metrics to Kinesis Data Streams
 * Simulates ML inference workload with high CPU and variable latency patterns
 * 
 * Contract: Telemetry Contract §Schema
 * - service_id: "fraud-detection"
 * - metric_type: cpu_utilization, memory_utilization, request_latency, throughput
 * - tenant_id: mandatory
 */

const express = require('express');
const AWS = require('aws-sdk');
const os = require('os');

const app = express();
const PORT = process.env.PORT || 3000;
const SERVICE_NAME = process.env.SERVICE_NAME || 'fraud-detection';
const KINESIS_STREAM_NAME = process.env.KINESIS_STREAM_NAME;
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';

// Initialize Kinesis client
const kinesis = new AWS.Kinesis({ region: AWS_REGION });

// Middleware
app.use(express.json());

// Helper to extract tenant_id from request
function getTenantId(req) {
  return req.headers['x-tenant-id'] || req.body?.tenant_id || 'tier-1';
}

// Health check endpoint
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'healthy', service: SERVICE_NAME });
});

// Fraud detection endpoints
app.post('/fraud/check', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate ML inference (80-300ms - variable CPU load)
  const processingTime = 80 + Math.random() * 220;
  await burnCPU(processingTime * 0.7); // Simulate CPU-intensive ML inference
  await new Promise(resolve => setTimeout(resolve, processingTime * 0.3));
  
  const latency = Date.now() - startTime;
  const riskScore = Math.random() * 100;
  const isFraudulent = riskScore > 75;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('fraud_check', latency, riskScore, null, tenantId);
  
  res.status(200).json({
    transaction_id: req.body.transaction_id || `txn_${Date.now()}`,
    risk_score: riskScore.toFixed(2),
    is_fraudulent: isFraudulent,
    confidence: (0.7 + Math.random() * 0.3).toFixed(3),
    latency_ms: latency,
    factors: isFraudulent ? ['unusual_location', 'high_amount', 'velocity_check'] : []
  });
});

app.post('/fraud/batch-check', async (req, res) => {
  const startTime = Date.now();
  const batchSize = req.body.transactions?.length || 10;
  
  // Simulate batch inference (200-600ms - heavy CPU)
  const processingTime = 200 + Math.random() * 400;
  await burnCPU(processingTime * 0.8);
  await new Promise(resolve => setTimeout(resolve, processingTime * 0.2));
  
  const latency = Date.now() - startTime;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('batch_fraud_check', latency, null, batchSize, tenantId);
  
  const results = Array.from({ length: batchSize }, (_, i) => {
    const riskScore = Math.random() * 100;
    return {
      transaction_id: `txn_${Date.now()}_${i}`,
      risk_score: riskScore.toFixed(2),
      is_fraudulent: riskScore > 75
    };
  });
  
  res.status(200).json({
    batch_id: `batch_${Date.now()}`,
    processed: batchSize,
    results: results,
    latency_ms: latency
  });
});

app.get('/fraud/report/:txnId', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate report generation (50-150ms)
  const processingTime = 50 + Math.random() * 100;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('fraud_report', latency, null, null, tenantId);
  
  res.status(200).json({
    transaction_id: req.params.txnId,
    detailed_analysis: {
      device_fingerprint: 'matched',
      geolocation: 'normal',
      behavioral_patterns: 'consistent',
      account_age: '2_years'
    },
    latency_ms: latency
  });
});

app.post('/fraud/feedback', async (req, res) => {
  const startTime = Date.now();
  
  // Simulate model feedback loop (30-100ms)
  const processingTime = 30 + Math.random() * 70;
  await new Promise(resolve => setTimeout(resolve, processingTime));
  
  const latency = Date.now() - startTime;
  const tenantId = getTenantId(req);
  
  // Emit telemetry
  await emitMetrics('feedback_ingestion', latency, null, null, tenantId);
  
  res.status(200).json({
    feedback_id: `fb_${Date.now()}`,
    status: 'recorded',
    latency_ms: latency
  });
});

/**
 * CPU-intensive simulation for ML inference (asynchronous/non-blocking)
 * Mimics processing duration without locking Node.js single thread
 */
function burnCPU(durationMs) {
  return new Promise(resolve => setTimeout(resolve, durationMs));
}

/**
 * Emit telemetry metrics to Kinesis
 * Fraud detection typically has high CPU due to ML inference
 */
async function emitMetrics(operation, latency, riskScore = null, batchSize = null, tenantId = 'tier-1') {
  if (!KINESIS_STREAM_NAME) {
    console.log('[WARN] KINESIS_STREAM_NAME not set, skipping telemetry');
    return;
  }

  const timestamp = new Date().toISOString();
  const cpuUsage = os.loadavg()[0] * 10;
  const memUsage = (1 - os.freemem() / os.totalmem()) * 100;
  
  // Fraud detection has higher CPU usage during inference (add 20-30% baseline)
  const fraudCPUAdjustment = 20 + Math.random() * 10;
  
  const metrics = [
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'cpu_usage_percent',
      // Simulate CPU load based on request latency:
      // latency <= 100ms -> cpu ~ 30-45% (normal ML baseline)
      // latency >= 400ms -> cpu ~ 85-100% (overloaded ML serving)
      value: Math.min(100, Math.max(15, 20 + (latency / 5) + Math.random() * 10)),
      labels: { operation, batch_size: batchSize }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'memory_usage_percent',
      value: Math.min(100, memUsage + Math.random() * 10),
      labels: { operation, batch_size: batchSize }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'api_latency_ms',
      value: latency,
      labels: { operation, batch_size: batchSize }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      // Redis cache hit rate for ML model lookups - drops under memory pressure
      // Telemetry contract Signal 6: cache_hit_rate_pct
      metric_type: 'cache_hit_rate_pct',
      value: Math.max(0, Math.min(100, 85 - (cpuUsage * 0.3) - Math.random() * 10)),
      labels: { operation, cache_type: 'redis' }
    },
    {
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      // Active connections to fraud inference workers
      metric_type: 'active_connections',
      value: Math.max(1, Math.floor(cpuUsage * 0.4 + (batchSize || 0) * 0.5 + Math.random() * 15)),
      labels: { operation }
    }
  ];

  // Add risk_score as custom fraud metric (NOTE: not in telemetry contract - infra metric only)
  // Kept for service-specific observability but AI engine ignores unknown metric_types gracefully
  if (riskScore !== null) {
    metrics.push({
      ts: timestamp,
      tenant_id: tenantId,
      service_id: SERVICE_NAME,
      metric_type: 'risk_score',
      value: riskScore,
      labels: { operation }
    });
  }

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

// Periodic heartbeat metrics (every 30 seconds)
setInterval(async () => {
  await emitMetrics('heartbeat', 0);
}, 30000);

app.listen(PORT, () => {
  console.log(`[${SERVICE_NAME}] Running on port ${PORT}`);
  console.log(`[${SERVICE_NAME}] Kinesis stream: ${KINESIS_STREAM_NAME}`);
  console.log(`[${SERVICE_NAME}] AWS Region: ${AWS_REGION}`);
});
