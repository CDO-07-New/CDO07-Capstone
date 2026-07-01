/**
 * K6 Test Scenario 4: NOISY BASELINE (SHORT VERSION for DEMO/DEV)
 *
 * ⚠️ CHÚ Ý: Đây là bản RÚT NGẮN để test nhanh (~20 phút thay vì 2 giờ)
 *
 * Simulates highly variable traffic with random spikes (hard to predict).
 * Mimics: Organic user behavior, bot traffic, retry storms, cascading failures.
 *
 * Expected AI Detection:
 * - LOW anomaly rate (this is the FALSE POSITIVE test)
 * - EWMA should NOT fire for normal random variance
 * - Only fire when a TRUE anomaly spike is injected in phase 3
 * - FP rate validation scenario (target: FP ≤ 12%)
 *
 * Load Pattern (COMPRESSED):
 * - Random walk 80-120 RPS  (5 min)  — normal noise
 * - Random walk 80-120 RPS  (5 min)  — normal noise
 * - TRUE ANOMALY spike 250 RPS (5 min) — AI MUST detect this
 * - Recovery 80-120 RPS      (5 min)  — back to normal
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
const spikeEvents = new Counter('spike_events');
const paymentLatency = new Trend('payment_latency');
const ledgerLatency  = new Trend('ledger_latency');
const fraudLatency   = new Trend('fraud_latency');

// Tenants cycling through 3 tier-1 services (multi-tenant requirement)
const TENANTS = ['payment-gw', 'ledger-svc', 'fraud-detection'];

export const options = {
  scenarios: {
    noisy_baseline_short: {
      executor: 'ramping-arrival-rate',
      startRate: 80,
      timeUnit: '1s',
      preAllocatedVUs: 150,
      maxVUs: 500,
      stages: [
        { duration: '2m', target: 100 }, // Normal noise
        { duration: '2m', target: 85  }, // Normal noise dip
        { duration: '3m', target: 250 }, // TRUE ANOMALY spike — AI should detect
        { duration: '2m', target: 90  }, // Recovery
        { duration: '3m', target: 110 }, // Normal noise
        { duration: '2m', target: 80  }, // Normal noise dip
        { duration: '3m', target: 95  }, // Normal noise
        { duration: '3m', target: 100 }, // Cooldown
      ],
    },
  },

  thresholds: {
    // SHORT version: relaxed thresholds — noisy scenario has high variance by design
    'http_req_duration': ['p(95)<1500', 'p(99)<3000'],
    'http_req_failed':   ['rate<0.08'],
    'errors':            ['rate<0.08'],
  },

  tags: {
    scenario: 'noisy-baseline-SHORT',
    test_type: 'demo',
    duration: '20min',
  },
};

export default function (data) {
  const elapsedMin = (Date.now() - data.START_TIME) / 60000;
  // Phase 3 (min 9-14): TRUE ANOMALY — mark spike_events for AI correlation
  const isTrueAnomaly = elapsedMin >= 4 && elapsedMin < 7;
  if (isTrueAnomaly) spikeEvents.add(1);

  const tenant       = TENANTS[Math.floor(Math.random() * TENANTS.length)];
  const serviceChoice = Math.random();

  if (serviceChoice < 0.45) {
    testPaymentService(tenant);
  } else if (serviceChoice < 0.75) {
    testLedgerService(tenant);
  } else {
    testFraudService(tenant);
  }
}

function testPaymentService(tenant) {
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`, payload: generatePaymentPayload(tenant), weight: 0.5 },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.CAPTURE}`,   payload: JSON.stringify({ transaction_id: `txn_${Date.now()}`, tenant_id: tenant }), weight: 0.3 },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.STATUS}/txn_${Date.now()}`, method: 'GET', weight: 0.2 },
  ];

  const ep  = pickWeighted(endpoints);
  let namePay = ENDPOINTS.PAYMENT.AUTHORIZE;
  if (ep.url.includes('/status/'))  namePay = `${ENDPOINTS.PAYMENT.STATUS}/:id`;
  else if (ep.url.includes('/capture')) namePay = ENDPOINTS.PAYMENT.CAPTURE;
  const res = ep.method === 'GET'
    ? http.get(ep.url,  { headers: generateHeaders(tenant), timeout: '10s', tags: { tenant, endpoint: 'payment', name: namePay } })
    : http.post(ep.url, ep.payload, { headers: generateHeaders(tenant), timeout: '10s', tags: { tenant, endpoint: 'payment', name: namePay } });

  const ok = check(res, {
    'payment 200/201': (r) => r.status === 200 || r.status === 201,
    'payment received': (r) => r.status !== 0,
  });

  paymentLatency.add(res.timings.duration);
  errorRate.add(!ok);
}

function testLedgerService(tenant) {
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`,   payload: generateLedgerPayload(tenant), weight: 0.5 },
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.BALANCE}/acc_${Math.floor(Math.random() * 5000)}`, method: 'GET', weight: 0.3 },
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.HISTORY}/acc_${Math.floor(Math.random() * 5000)}`, method: 'GET', weight: 0.2 },
  ];

  const ep  = pickWeighted(endpoints);
  let nameLed = ENDPOINTS.LEDGER.ENTRY;
  if (ep.url.includes('/balance/'))  nameLed = `${ENDPOINTS.LEDGER.BALANCE}/:id`;
  else if (ep.url.includes('/history/')) nameLed = `${ENDPOINTS.LEDGER.HISTORY}/:id`;
  const res = ep.method === 'GET'
    ? http.get(ep.url,  { headers: generateHeaders(tenant), timeout: '10s', tags: { tenant, endpoint: 'ledger', name: nameLed } })
    : http.post(ep.url, ep.payload, { headers: generateHeaders(tenant), timeout: '10s', tags: { tenant, endpoint: 'ledger', name: nameLed } });

  const ok = check(res, {
    'ledger 200/201':  (r) => r.status === 200 || r.status === 201,
    'ledger received': (r) => r.status !== 0,
  });

  ledgerLatency.add(res.timings.duration);
  errorRate.add(!ok);
}

function testFraudService(tenant) {
  const res = http.post(
    `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`,
    generateFraudPayload(tenant),
    { headers: generateHeaders(tenant), timeout: '10s', tags: { tenant, endpoint: 'fraud' } }
  );

  const ok = check(res, {
    'fraud 200':      (r) => r.status === 200,
    'fraud received': (r) => r.status !== 0,
  });

  fraudLatency.add(res.timings.duration);
  errorRate.add(!ok);
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

export function setup() {
  return { START_TIME: Date.now() };
}

export function handleSummary(data) {
  return {
    stdout: JSON.stringify({
      scenario:         'noisy-baseline-SHORT',
      duration_minutes: 20,
      total_requests:   data.metrics.http_reqs.values.count,
      error_rate:       data.metrics.errors ? data.metrics.errors.values.rate : 0,
      p95_latency:      data.metrics.http_req_duration.values['p(95)'],
      p99_latency:      data.metrics.http_req_duration.values['p(99)'],
      note: 'COMPRESSED version (20 min instead of 2h). Use for dev/demo only.',
    }, null, 2),
  };
}
