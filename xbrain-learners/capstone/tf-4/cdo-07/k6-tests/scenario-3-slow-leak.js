/**
 * K6 Test Scenario 3: SLOW LEAK
 * 
 * Simulates resource leak (memory leak, connection leak, file descriptor leak)
 * Mimics: Unclosed DB connections, memory not GC'd, cache growing unbounded
 * 
 * Expected AI Detection:
 * - Lead time ≥15 min before capacity exhaustion
 * - Steady upward trend in memory_utilization
 * - Connection pool usage climbing
 * - Recommendation: "Investigate memory leak, restart service, add memory limit"
 * 
 * Load Pattern:
 * - Constant: 100 RPS throughout
 * - But: Progressively heavier payloads (simulate growing memory footprint)
 * - Duration: 2.5 hours to observe slow degradation
 */

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend, Gauge } from 'k6/metrics';
import {
  BASE_URL,
  ENDPOINTS,
  HEADERS,
  generatePaymentPayload,
  generateLedgerPayload,
  generateFraudPayload
} from './config.js';

// Custom metrics
const errorRate = new Rate('errors');
const payloadSize = new Gauge('payload_size_bytes');
const memoryPressure = new Gauge('simulated_memory_pressure');
const paymentLatency = new Trend('payment_latency');
const ledgerLatency = new Trend('ledger_latency');
const fraudLatency = new Trend('fraud_latency');

export const options = {
  scenarios: {
    slow_leak: {
      executor: 'constant-arrival-rate',
      rate: 100,
      timeUnit: '1s',
      duration: '150m',
      preAllocatedVUs: 200,
      maxVUs: 800,
    }
  },
  
  thresholds: {
    'http_req_duration': ['p(95)<2000'], // Allow degradation over time
    'http_req_failed': ['rate<0.15'],    // Expect failures as leak progresses
    'errors': ['rate<0.15']
  }
};

// Track test progress to simulate growing memory leak
let iterationCount = 0;

export default function(data) {
  iterationCount++;
  
  // Simulate memory leak: payload size grows over time
  const testProgress = (Date.now() - data.START_TIME) / (2.5 * 60 * 60 * 1000); // 0.0 to 1.0
  const leakFactor = 1 + (testProgress * 3); // 1x to 4x memory pressure
  
  memoryPressure.add(leakFactor);
  
  // Distribute load across services
  const serviceChoice = Math.random();
  
  if (serviceChoice < 0.4) {
    testPaymentService(leakFactor);
  } else if (serviceChoice < 0.7) {
    testLedgerService(leakFactor); // Ledger most affected by memory leaks
  } else {
    testFraudService(leakFactor);
  }
}

export function testPaymentService(leakFactor) {
  // Generate payload with increasing size (simulate cached data accumulation)
  const basePayload = JSON.parse(generatePaymentPayload());
  
  // Add artificial padding to simulate memory bloat
  basePayload.metadata = {
    iteration: iterationCount,
    cached_data: 'x'.repeat(Math.floor(100 * leakFactor)), // Growing metadata
    timestamp: Date.now()
  };
  
  const payload = JSON.stringify(basePayload);
  payloadSize.add(payload.length);
  
  const res = http.post(
    `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`,
    payload,
    { headers: HEADERS, timeout: '15s' }
  );
  
  const success = check(res, {
    'payment status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'payment latency degrading': (r) => r.timings.duration < 1500 || leakFactor < 2
  });
  
  paymentLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testLedgerService(leakFactor) {
  const basePayload = JSON.parse(generateLedgerPayload());
  
  // Ledger service accumulates transaction history (memory leak simulation)
  basePayload.transaction_history = Array.from(
    { length: Math.floor(5 * leakFactor) },
    (_, i) => ({
      id: `hist_${i}`,
      amount: Math.random() * 100,
      timestamp: Date.now() - i * 1000
    })
  );
  
  const payload = JSON.stringify(basePayload);
  payloadSize.add(payload.length);
  
  const res = http.post(
    `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`,
    payload,
    { headers: HEADERS, timeout: '15s' }
  );
  
  const success = check(res, {
    'ledger status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'ledger responding': (r) => r.status !== 0
  });
  
  ledgerLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testFraudService(leakFactor) {
  const basePayload = JSON.parse(generateFraudPayload());
  
  // Fraud detection accumulates feature vectors (memory intensive)
  basePayload.feature_vector = Array.from(
    { length: Math.floor(20 * leakFactor) },
    () => Math.random()
  );
  
  const payload = JSON.stringify(basePayload);
  payloadSize.add(payload.length);
  
  const res = http.post(
    `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`,
    payload,
    { headers: HEADERS, timeout: '15s' }
  );
  
  const success = check(res, {
    'fraud status is 200': (r) => r.status === 200,
    'fraud ml processing': (r) => r.status !== 0
  });
  
  fraudLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function setup() {
  // Record test start time for leak factor calculation
  return { START_TIME: Date.now() };
}

export function handleSummary(data) {
  return {
    'scenario-3-slow-leak-summary.json': JSON.stringify(data, null, 2),
    stdout: `
╔══════════════════════════════════════════════════════════════════╗
║         SCENARIO 3: SLOW LEAK - TEST SUMMARY                    ║
╚══════════════════════════════════════════════════════════════════╝

Duration: 2.5 hours (150 minutes)
Pattern: Constant 100 RPS, but growing memory footprint

📊 RESULTS:
- Total Requests: ${data.metrics.http_reqs.values.count}
- Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%
- Avg RPS: ${data.metrics.http_reqs.values.rate.toFixed(2)}

📈 RESOURCE PRESSURE:
- Avg Payload Size: ${data.metrics.payload_size_bytes.values.avg.toFixed(0)} bytes
- Max Memory Pressure: ${data.metrics.simulated_memory_pressure.values.max.toFixed(2)}x
- Final Payload Size: ${data.metrics.payload_size_bytes.values.max.toFixed(0)} bytes

⏱️  LATENCY DEGRADATION (P95):
- Payment: ${data.metrics.payment_latency.values['p(95)'].toFixed(2)}ms
- Ledger: ${data.metrics.ledger_latency.values['p(95)'].toFixed(2)}ms
- Fraud: ${data.metrics.fraud_latency.values['p(95)'].toFixed(2)}ms

🎯 AI ENGINE CHECK:
- Did AI detect upward memory trend? [MANUAL VERIFICATION]
- Lead time ≥15 min before exhaustion? [CHECK GRAFANA]
- Memory leak recommendation provided? [CHECK SLACK]

Expected Detection: Steady memory_utilization upward trend
Expected Recommendation: "Memory leak detected, restart service, set memory limit"

📉 DEGRADATION TIMELINE:
- 0-30 min: Normal operation
- 30-60 min: Slight degradation (1.5x memory)
- 60-90 min: Moderate degradation (2x memory)
- 90-120 min: Significant degradation (3x memory)
- 120-150 min: Critical state (4x memory)
`
  };
}
