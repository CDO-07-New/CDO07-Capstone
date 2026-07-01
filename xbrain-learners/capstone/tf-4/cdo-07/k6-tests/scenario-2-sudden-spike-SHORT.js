/**
 * K6 Test Scenario 2: SUDDEN SPIKE (SHORT VERSION for DEMO/DEV)
 *
 * ⚠️ CHÚ Ý: Đây là bản RÚT NGẮN để test nhanh (~20 phút thay vì 2 giờ)
 *
 * Simulates sudden traffic surge (Black Friday scenario) in compressed timeline.
 * Mimics: Flash sale, DDoS, viral campaign, payment rush.
 *
 * Expected AI Detection:
 * - Immediate anomaly detection on throughput spike
 * - CPU/Memory spike correlation
 * - Recommendation: SCALE_UP ECS service
 *
 * Load Pattern (COMPRESSED):
 * - Baseline:  100 RPS  (5 min)
 * - Spike:     100→500  (1 min)
 * - Sustained: 500 RPS  (4 min)
 * - Recovery:  500→100  (2 min)
 * - Cooldown:  100 RPS  (8 min)
 * Total: 20 minutes
 */

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend, Counter } from 'k6/metrics';
import {
  BASE_URL,
  ENDPOINTS,
  generateHeaders,
  generatePaymentPayload,
  generateLedgerPayload,
  generateFraudPayload
} from './config.js';

// Custom metrics
const errorRate   = new Rate('errors');
const spikeRequests = new Counter('spike_requests');
const paymentLatency = new Trend('payment_latency');
const ledgerLatency  = new Trend('ledger_latency');
const fraudLatency   = new Trend('fraud_latency');

// Tenants cycling through 3 tier-1 services (multi-tenant requirement)
const TENANTS = ['payment-gw', 'ledger-svc', 'fraud-detection'];

export const options = {
  scenarios: {
    sudden_spike_short: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 150,
      maxVUs: 600,
      stages: [
        { duration: '5m',  target: 100 }, // Baseline
        { duration: '1m',  target: 500 }, // SUDDEN SPIKE
        { duration: '4m',  target: 500 }, // Sustained spike
        { duration: '2m',  target: 100 }, // Recovery
        { duration: '8m',  target: 100 }, // Cooldown
      ],
    },
  },

  thresholds: {
    // SHORT version: relaxed thresholds — spike scenario intentionally causes latency spikes
    'http_req_duration': ['p(95)<2000', 'p(99)<5000'],
    'http_req_failed':   ['rate<0.10'],
    'errors':            ['rate<0.10'],
  },

  tags: {
    scenario: 'sudden-spike-SHORT',
    test_type: 'demo',
    duration: '20min',
  },
};

export default function () {
  const tenant = TENANTS[Math.floor(Math.random() * TENANTS.length)];
  const rand   = Math.random();

  if (rand < 0.60) {
    testPaymentService(tenant);
  } else if (rand < 0.80) {
    testLedgerService(tenant);
  } else {
    testFraudService(tenant);
  }
}

function testPaymentService(tenant) {
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`,      payload: generatePaymentPayload(tenant), method: 'POST', weight: 0.7 },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.STATUS}/txn_${Date.now()}`, method: 'GET',  weight: 0.3 },
  ];

  const endpoint = pickWeighted(endpoints);
  const headers  = generateHeaders(tenant);

  const res = endpoint.method === 'GET'
    ? http.get(endpoint.url,  { headers, timeout: '10s', tags: { tenant, endpoint: 'payment', name: `${ENDPOINTS.PAYMENT.STATUS}/:id` } })
    : http.post(endpoint.url, endpoint.payload, { headers, timeout: '10s', tags: { tenant, endpoint: 'payment', name: ENDPOINTS.PAYMENT.AUTHORIZE } });

  const ok = check(res, {
    'payment 200/201': (r) => r.status === 200 || r.status === 201,
    'payment received': (r) => r.status !== 0,
  });

  paymentLatency.add(res.timings.duration);
  errorRate.add(!ok);
  spikeRequests.add(1);
}

function testLedgerService(tenant) {
  const headers = generateHeaders(tenant);
  const res = http.post(
    `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`,
    generateLedgerPayload(tenant),
    { headers, timeout: '10s', tags: { tenant, endpoint: 'ledger' } }
  );

  const ok = check(res, {
    'ledger 200/201':  (r) => r.status === 200 || r.status === 201,
    'ledger received': (r) => r.status !== 0,
  });

  ledgerLatency.add(res.timings.duration);
  errorRate.add(!ok);
  spikeRequests.add(1);
}

function testFraudService(tenant) {
  const headers = generateHeaders(tenant);
  const res = http.post(
    `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`,
    generateFraudPayload(tenant),
    { headers, timeout: '10s', tags: { tenant, endpoint: 'fraud' } }
  );

  const ok = check(res, {
    'fraud 200':      (r) => r.status === 200,
    'fraud received': (r) => r.status !== 0,
  });

  fraudLatency.add(res.timings.duration);
  errorRate.add(!ok);
  spikeRequests.add(1);
}

function pickWeighted(items) {
  const rand = Math.random();
  let cumulative = 0;
  for (const item of items) {
    cumulative += item.weight || (1 / items.length);
    if (rand < cumulative) return item;
  }
  return items[items.length - 1];
}

export function handleSummary(data) {
  return {
    stdout: JSON.stringify({
      scenario:         'sudden-spike-SHORT',
      duration_minutes: 20,
      total_requests:   data.metrics.http_reqs.values.count,
      error_rate:       data.metrics.errors ? data.metrics.errors.values.rate : 0,
      p95_latency:      data.metrics.http_req_duration.values['p(95)'],
      p99_latency:      data.metrics.http_req_duration.values['p(99)'],
      note: 'COMPRESSED version (20 min instead of 2h). Use for dev/demo only.',
    }, null, 2),
  };
}
