/**
 * K6 Test Scenario 1: GRADUAL DRIFT
 * 
 * Simulates slow performance degradation over 2 hours
 * Mimics: Memory leak, connection pool exhaustion, cache pollution
 * 
 * Expected AI Detection: 
 * - Lead time ≥15 min before SLO breach
 * - Drift detection on memory_utilization upward trend
 * - Recommendation: "Scale memory from 512MB → 1024MB"
 * 
 * Load Pattern:
 * - Start: 50 RPS (normal load)
 * - Middle: 100 RPS (baseline)
 * - End: 150 RPS (gradual increase)
 * - Duration: 2 hours (7200s)
 */

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend } from 'k6/metrics';
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
const paymentLatency = new Trend('payment_latency');
const ledgerLatency = new Trend('ledger_latency');
const fraudLatency = new Trend('fraud_latency');

export const options = {
  thresholds: {
    'http_req_duration': ['p(95)<800'], // Allow higher latency for drift scenario
    'http_req_failed': ['rate<0.05'],   // 5% error tolerance as system degrades
    'errors': ['rate<0.05']
  },
  
  // Distributed across services
  scenarios: {
    payment_service: {
      executor: 'ramping-arrival-rate',
      startRate: 20,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { duration: '10m', target: 20 },
        { duration: '30m', target: 40 },
        { duration: '60m', target: 60 },
        { duration: '20m', target: 60 }
      ],
      exec: 'testPaymentService'
    },
    
    ledger_service: {
      executor: 'ramping-arrival-rate',
      startRate: 20,
      timeUnit: '1s',
      preAllocatedVUs: 50,
      maxVUs: 200,
      stages: [
        { duration: '10m', target: 20 },
        { duration: '30m', target: 40 },
        { duration: '60m', target: 60 },
        { duration: '20m', target: 60 }
      ],
      exec: 'testLedgerService'
    },
    
    fraud_service: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 30,
      maxVUs: 100,
      stages: [
        { duration: '10m', target: 10 },
        { duration: '30m', target: 20 },
        { duration: '60m', target: 30 },
        { duration: '20m', target: 30 }
      ],
      exec: 'testFraudService'
    }
  }
};

export function testPaymentService() {
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`, payload: generatePaymentPayload() },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.CAPTURE}`, payload: JSON.stringify({ transaction_id: `txn_${Date.now()}` }) },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.STATUS}/txn_${Date.now()}`, method: 'GET' }
  ];
  
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  
  const res = endpoint.method === 'GET'
    ? http.get(endpoint.url, { headers: HEADERS })
    : http.post(endpoint.url, endpoint.payload, { headers: HEADERS });
  
  const success = check(res, {
    'payment status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'payment latency < 500ms': (r) => r.timings.duration < 500
  });
  
  paymentLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testLedgerService() {
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`, payload: generateLedgerPayload() },
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.BALANCE}/acc_${Math.floor(Math.random() * 1000)}`, method: 'GET' },
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.HISTORY}/acc_${Math.floor(Math.random() * 1000)}`, method: 'GET' }
  ];
  
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  
  const res = endpoint.method === 'GET'
    ? http.get(endpoint.url, { headers: HEADERS })
    : http.post(endpoint.url, endpoint.payload, { headers: HEADERS });
  
  const success = check(res, {
    'ledger status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'ledger latency < 600ms': (r) => r.timings.duration < 600
  });
  
  ledgerLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testFraudService() {
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`, payload: generateFraudPayload() },
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.REPORT}/txn_${Date.now()}`, method: 'GET' }
  ];
  
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  
  const res = endpoint.method === 'GET'
    ? http.get(endpoint.url, { headers: HEADERS })
    : http.post(endpoint.url, endpoint.payload, { headers: HEADERS });
  
  const success = check(res, {
    'fraud status is 200': (r) => r.status === 200,
    'fraud latency < 700ms': (r) => r.timings.duration < 700
  });
  
  fraudLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function handleSummary(data) {
  return {
    'scenario-1-gradual-drift-summary.json': JSON.stringify(data, null, 2),
    stdout: `
╔══════════════════════════════════════════════════════════════════╗
║          SCENARIO 1: GRADUAL DRIFT - TEST SUMMARY              ║
╚══════════════════════════════════════════════════════════════════╝

Duration: 2 hours (120 minutes)
Pattern: 50 RPS → 100 RPS → 150 RPS (gradual increase)

📊 RESULTS:
- Total Requests: ${data.metrics.http_reqs.values.count}
- Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%
- Avg RPS: ${data.metrics.http_reqs.values.rate.toFixed(2)}

⏱️  LATENCY (P95):
- Payment: ${data.metrics.payment_latency.values['p(95)'].toFixed(2)}ms
- Ledger: ${data.metrics.ledger_latency.values['p(95)'].toFixed(2)}ms
- Fraud: ${data.metrics.fraud_latency.values['p(95)'].toFixed(2)}ms

🎯 AI ENGINE CHECK:
- Did AI detect drift before SLO breach? [MANUAL VERIFICATION]
- Lead time ≥15 minutes? [CHECK GRAFANA ANNOTATIONS]
- Capacity recommendation provided? [CHECK SLACK ALERTS]

Expected Detection: Memory utilization upward trend
Expected Recommendation: "Scale memory 512MB → 1024MB"
`
  };
}
