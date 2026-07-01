/**
 * K6 Test Scenario 2: SUDDEN SPIKE
 * 
 * Simulates sudden traffic surge (Black Friday scenario)
 * Mimics: Flash sale, DDoS, viral campaign, payment rush
 * 
 * Expected AI Detection:
 * - Immediate anomaly detection on throughput spike
 * - CPU/Memory spike correlation
 * - Recommendation: "Enable auto-scaling, increase max_instances 2 → 8"
 * 
 * Load Pattern:
 * - Baseline: 100 RPS (30 min)
 * - Spike: 0 → 500 RPS in 2 minutes (sudden jump)
 * - Sustained: 500 RPS (20 min)
 * - Recovery: 500 → 100 RPS (10 min)
 * - Duration: 2 hours
 */

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
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
const spikeRequests = new Counter('spike_requests');
const paymentLatency = new Trend('payment_latency');
const ledgerLatency = new Trend('ledger_latency');
const fraudLatency = new Trend('fraud_latency');

export const options = {
  scenarios: {
    sudden_spike: {
      executor: 'ramping-arrival-rate',
      startRate: 100,
      timeUnit: '1s',
      preAllocatedVUs: 300,
      maxVUs: 1000,
      stages: [
    // Phase 1: Normal baseline (30 min)
    { duration: '30m', target: 100 },
    
    // Phase 2: SUDDEN SPIKE (2 min) - 100 → 500 RPS
    { duration: '2m', target: 500 },
    
    // Phase 3: Sustained spike (20 min)
    { duration: '20m', target: 500 },
    
    // Phase 4: Gradual recovery (10 min)
    { duration: '10m', target: 200 },
    
    // Phase 5: Back to baseline (58 min)
    { duration: '58m', target: 100 }
      ],
    }
  },
  
  thresholds: {
    'http_req_duration': ['p(95)<1000'], // Relaxed during spike
    'http_req_failed': ['rate<0.10'],    // 10% error tolerance during spike
    'errors': ['rate<0.10']
  }
};

export default function() {
  // Randomly distribute load across 3 services
  const serviceChoice = Math.random();
  
  if (serviceChoice < 0.5) {
    // 50% payment (highest during flash sales)
    testPaymentService();
  } else if (serviceChoice < 0.8) {
    // 30% fraud (spike in checks during high traffic)
    testFraudService();
  } else {
    // 20% ledger
    testLedgerService();
  }
}

export function testPaymentService() {
  // During spike, authorize requests dominate
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`, payload: generatePaymentPayload(), weight: 0.7 },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.STATUS}/txn_${Date.now()}`, method: 'GET', weight: 0.3 }
  ];
  
  const rand = Math.random();
  let cumulative = 0;
  let selectedEndpoint = endpoints[0];
  
  for (const endpoint of endpoints) {
    cumulative += endpoint.weight;
    if (rand < cumulative) {
      selectedEndpoint = endpoint;
      break;
    }
  }
  
  const res = selectedEndpoint.method === 'GET'
    ? http.get(selectedEndpoint.url, { headers: HEADERS, timeout: '10s' })
    : http.post(selectedEndpoint.url, selectedEndpoint.payload, { headers: HEADERS, timeout: '10s' });
  
  const success = check(res, {
    'payment status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'payment response received': (r) => r.status !== 0
  });
  
  paymentLatency.add(res.timings.duration);
  errorRate.add(!success);
  spikeRequests.add(1);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testLedgerService() {
  const res = http.post(
    `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`,
    generateLedgerPayload(),
    { headers: HEADERS, timeout: '10s' }
  );
  
  const success = check(res, {
    'ledger status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'ledger response received': (r) => r.status !== 0
  });
  
  ledgerLatency.add(res.timings.duration);
  errorRate.add(!success);
  spikeRequests.add(1);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testFraudService() {
  // Fraud checks spike during high payment volume
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`, payload: generateFraudPayload(), weight: 0.8 },
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.BATCH}`, payload: JSON.stringify({ transactions: Array(5).fill({}) }), weight: 0.2 }
  ];
  
  const endpoint = Math.random() < 0.8 ? endpoints[0] : endpoints[1];
  
  const res = http.post(endpoint.url, endpoint.payload, { headers: HEADERS, timeout: '10s' });
  
  const success = check(res, {
    'fraud status is 200': (r) => r.status === 200,
    'fraud response received': (r) => r.status !== 0
  });
  
  fraudLatency.add(res.timings.duration);
  errorRate.add(!success);
  spikeRequests.add(1);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function handleSummary(data) {
  const spikePhaseStart = 30 * 60; // 30 minutes in seconds
  const spikePhaseEnd = 52 * 60;   // 52 minutes in seconds
  
  return {
    'scenario-2-sudden-spike-summary.json': JSON.stringify(data, null, 2),
    stdout: `
╔══════════════════════════════════════════════════════════════════╗
║          SCENARIO 2: SUDDEN SPIKE - TEST SUMMARY               ║
╚══════════════════════════════════════════════════════════════════╝

Duration: 2 hours
Pattern: 100 RPS → 500 RPS (2 min spike) → sustained → recovery

📊 RESULTS:
- Total Requests: ${data.metrics.http_reqs.values.count}
- Spike Requests: ${data.metrics.spike_requests.values.count}
- Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%
- Peak RPS: ${data.metrics.http_reqs.values.rate.toFixed(2)}

⏱️  LATENCY DURING SPIKE (P95):
- Payment: ${data.metrics.payment_latency.values['p(95)'].toFixed(2)}ms
- Ledger: ${data.metrics.ledger_latency.values['p(95)'].toFixed(2)}ms
- Fraud: ${data.metrics.fraud_latency.values['p(95)'].toFixed(2)}ms

🎯 AI ENGINE CHECK:
- Did AI detect spike within 2 minutes? [MANUAL VERIFICATION]
- CPU/Memory correlation detected? [CHECK TIMESTREAM QUERIES]
- Auto-scaling recommendation provided? [CHECK SLACK ALERTS]

Expected Detection: Sudden throughput anomaly + CPU spike
Expected Recommendation: "Enable auto-scaling, max_instances 2 → 8"

⚠️  CRITICAL WINDOWS:
- Spike start: 30:00 mark
- Spike peak: 32:00-52:00 window
- Recovery: 52:00-62:00 window
`
  };
}
