/**
 * K6 Test Scenario 3: SLOW LEAK (SHORT VERSION for DEMO/DEV)
 *
 * ⚠️ CHÚ Ý: Đây là bản RÚT NGẮN để test nhanh (~20 phút thay vì 2.5 giờ)
 *
 * Simulates resource leak (memory leak, connection leak, file descriptor leak).
 * Mimics: Unclosed DB connections, unbounded caches, memory not GC'd.
 *
 * Expected AI Detection:
 * - Steady upward trend in memory_usage_percent
 * - db_connection_pool_pct climbing over time
 * - queue_depth growing under constant load
 * - Recommendation: ROLLBACK latest deploy (memory leak suspect)
 *
 * Load Pattern (COMPRESSED):
 * - Constant 100 RPS throughout 20 minutes
 * - Progressively heavier payloads (simulating memory pressure build-up)
 */

import http from 'k6/http';
import { check } from 'k6';
import { Rate, Trend, Gauge } from 'k6/metrics';
import {
  BASE_URL,
  ENDPOINTS,
  generateHeaders,
  generatePaymentPayload,
  generateLedgerPayload,
  generateFraudPayload
} from './config.js';

// Custom metrics
const errorRate      = new Rate('errors');
const payloadSize    = new Gauge('payload_size_bytes');
const memoryPressure = new Gauge('simulated_memory_pressure');
const paymentLatency = new Trend('payment_latency');
const ledgerLatency  = new Trend('ledger_latency');
const fraudLatency   = new Trend('fraud_latency');

// Tenants cycling through 3 tier-1 services (multi-tenant requirement)
const TENANTS = ['payment-gw', 'ledger-svc', 'fraud-detection'];

// Iteration counter for leak simulation
let iterationCount = 0;

export const options = {
  scenarios: {
    slow_leak_short: {
      executor: 'constant-arrival-rate',
      rate: 100,
      timeUnit: '1s',
      duration: '20m',
      preAllocatedVUs: 150,
      maxVUs: 400,
    },
  },

  thresholds: {
    // SHORT version: latency will degrade intentionally as "leak" progresses
    'http_req_duration': ['p(95)<3000', 'p(99)<6000'],
    'http_req_failed':   ['rate<0.08'],
    'errors':            ['rate<0.08'],
  },

  tags: {
    scenario: 'slow-leak-SHORT',
    test_type: 'demo',
    duration: '20min',
  },
};

export default function (data) {
  iterationCount++;

  // testProgress: 0 at start → 1 at end of 20-min window
  const testProgress = Math.min(1.0, (Date.now() - data.START_TIME) / (20 * 60 * 1000));
  // leakFactor grows from 1× to 4× over the test window
  const leakFactor = 1 + testProgress * 3;

  memoryPressure.add(leakFactor);

  const tenant       = TENANTS[Math.floor(Math.random() * TENANTS.length)];
  const serviceChoice = Math.random();

  if (serviceChoice < 0.40) {
    testPaymentService(tenant, leakFactor);
  } else if (serviceChoice < 0.70) {
    testLedgerService(tenant, leakFactor); // Ledger most affected by connection leaks
  } else {
    testFraudService(tenant, leakFactor);
  }
}

function testPaymentService(tenant, leakFactor) {
  const base = JSON.parse(generatePaymentPayload(tenant));
  // Simulate growing metadata (uncached data accumulation)
  base.metadata = {
    iteration:   iterationCount,
    cached_data: 'x'.repeat(Math.floor(100 * leakFactor)),
    timestamp:   Date.now(),
  };

  const payload = JSON.stringify(base);
  payloadSize.add(payload.length);

  const res = http.post(
    `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`,
    payload,
    { headers: generateHeaders(tenant), timeout: '15s', tags: { tenant, endpoint: 'payment' } }
  );

  const ok = check(res, {
    'payment 200/201':         (r) => r.status === 200 || r.status === 201,
    'payment latency tolerable': (r) => r.timings.duration < 1500 || leakFactor < 2,
  });

  paymentLatency.add(res.timings.duration);
  errorRate.add(!ok);
}

function testLedgerService(tenant, leakFactor) {
  const base = JSON.parse(generateLedgerPayload(tenant));
  // Simulate growing transaction history (connection pool / memory leak)
  base.transaction_history = Array.from(
    { length: Math.floor(5 * leakFactor) },
    (_, i) => ({ id: `hist_${i}`, amount: Math.random() * 100, timestamp: Date.now() - i * 1000 })
  );

  const payload = JSON.stringify(base);
  payloadSize.add(payload.length);

  const res = http.post(
    `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`,
    payload,
    { headers: generateHeaders(tenant), timeout: '15s', tags: { tenant, endpoint: 'ledger' } }
  );

  const ok = check(res, {
    'ledger 200/201':  (r) => r.status === 200 || r.status === 201,
    'ledger received': (r) => r.status !== 0,
  });

  ledgerLatency.add(res.timings.duration);
  errorRate.add(!ok);
}

function testFraudService(tenant, leakFactor) {
  const base = JSON.parse(generateFraudPayload(tenant));
  // Simulate growing feature vector (ML model cache/memory pressure)
  base.feature_vector = Array.from({ length: Math.floor(20 * leakFactor) }, () => Math.random());

  const payload = JSON.stringify(base);
  payloadSize.add(payload.length);

  const res = http.post(
    `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`,
    payload,
    { headers: generateHeaders(tenant), timeout: '15s', tags: { tenant, endpoint: 'fraud' } }
  );

  const ok = check(res, {
    'fraud 200':       (r) => r.status === 200,
    'fraud received':  (r) => r.status !== 0,
  });

  fraudLatency.add(res.timings.duration);
  errorRate.add(!ok);
}

export function setup() {
  return { START_TIME: Date.now() };
}

export function handleSummary(data) {
  return {
    stdout: JSON.stringify({
      scenario:         'slow-leak-SHORT',
      duration_minutes: 20,
      total_requests:   data.metrics.http_reqs.values.count,
      error_rate:       data.metrics.errors ? data.metrics.errors.values.rate : 0,
      p95_latency:      data.metrics.http_req_duration.values['p(95)'],
      p99_latency:      data.metrics.http_req_duration.values['p(99)'],
      note: 'COMPRESSED version (20 min instead of 2.5h). Use for dev/demo only.',
    }, null, 2),
  };
}
