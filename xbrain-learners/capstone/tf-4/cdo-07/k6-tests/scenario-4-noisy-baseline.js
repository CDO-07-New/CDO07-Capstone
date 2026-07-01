/**
 * K6 Test Scenario 4: NOISY BASELINE
 * 
 * Simulates highly variable traffic with random spikes (hard to predict)
 * Mimics: Organic user behavior, bot traffic, retry storms, cascading failures
 * 
 * Expected AI Detection:
 * - AI must distinguish real anomalies from noise
 * - FP rate ≤12% (must not alert on normal variance)
 * - Should catch ≥80% of actual drift events buried in noise
 * - Recommendation: "Increase confidence threshold, widen prediction bands"
 * 
 * Load Pattern:
 * - Baseline: 80-120 RPS (random walk)
 * - Random spikes: 200-300 RPS (2-5 min duration)
 * - Spike frequency: Every 15-20 min
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
const spikeEvents = new Counter('spike_events');
const noiseLevel = new Trend('noise_level');
const paymentLatency = new Trend('payment_latency');
const ledgerLatency = new Trend('ledger_latency');
const fraudLatency = new Trend('fraud_latency');

const TRAFFIC_STAGES = [
  { duration: '5m', minutes: 5, target: 100 },
  { duration: '10m', minutes: 10, target: 85 },
  { duration: '10m', minutes: 10, target: 250 },
  { duration: '10m', minutes: 10, target: 90 },
  { duration: '10m', minutes: 10, target: 110 },
  { duration: '10m', minutes: 10, target: 280 },
  { duration: '10m', minutes: 10, target: 95 },
  { duration: '10m', minutes: 10, target: 115 },
  { duration: '10m', minutes: 10, target: 220 },
  { duration: '10m', minutes: 10, target: 80 },
  { duration: '10m', minutes: 10, target: 320 },
  { duration: '10m', minutes: 10, target: 105 },
  { duration: '10m', minutes: 10, target: 90 },
];

export const options = {
  // Highly variable stages to create noisy baseline
  scenarios: {
    noisy_baseline: {
      executor: 'ramping-arrival-rate',
      startRate: 80,
      timeUnit: '1s',
      preAllocatedVUs: 250,
      maxVUs: 1000,
      stages: TRAFFIC_STAGES.map(({ duration, target }) => ({ duration, target })),
    }
  },
  
  thresholds: {
    'http_req_duration': ['p(95)<800'],
    'http_req_failed': ['rate<0.08'],   // 8% error tolerance for noisy scenario
    'errors': ['rate<0.08']
  }
};

let lastSpikeTime = 0;

function currentTargetRps(elapsedMinutes) {
  let previousTarget = 80;
  let stageStart = 0;

  for (const stage of TRAFFIC_STAGES) {
    const stageEnd = stageStart + stage.minutes;
    if (elapsedMinutes <= stageEnd) {
      const progress = Math.max(0, (elapsedMinutes - stageStart) / stage.minutes);
      return previousTarget + ((stage.target - previousTarget) * progress);
    }
    previousTarget = stage.target;
    stageStart = stageEnd;
  }

  return TRAFFIC_STAGES[TRAFFIC_STAGES.length - 1].target;
}

export default function(data) {
  const currentTime = Date.now();
  const elapsedMinutes = (currentTime - data.START_TIME) / 60000;
  const targetRps = currentTargetRps(elapsedMinutes);
  const isSpike = targetRps > 150;
  
  if (isSpike && currentTime - lastSpikeTime > 5000) {
    spikeEvents.add(1);
    lastSpikeTime = currentTime;
  }
  
  // Calculate noise level (variance in request rate)
  const variance = Math.abs(targetRps - 100) / 100;
  noiseLevel.add(variance);
  
  // Randomly distribute load with bias during spikes
  const serviceChoice = Math.random();
  
  if (serviceChoice < 0.45) {
    testPaymentService(isSpike);
  } else if (serviceChoice < 0.75) {
    testLedgerService(isSpike);
  } else {
    testFraudService(isSpike);
  }
}

export function testPaymentService(isSpike) {
  // During noise spikes, introduce more variation
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`, payload: generatePaymentPayload() },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.CAPTURE}`, payload: JSON.stringify({ transaction_id: `txn_${Date.now()}` }) },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.REFUND}`, payload: JSON.stringify({ transaction_id: `txn_${Date.now()}`, amount: 50 }) },
    { url: `${BASE_URL}${ENDPOINTS.PAYMENT.STATUS}/txn_${Date.now()}`, method: 'GET' }
  ];
  
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  
  const res = endpoint.method === 'GET'
    ? http.get(endpoint.url, { headers: HEADERS, timeout: '10s' })
    : http.post(endpoint.url, endpoint.payload, { headers: HEADERS, timeout: '10s' });
  
  const success = check(res, {
    'payment status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'payment received': (r) => r.status !== 0
  });
  
  paymentLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testLedgerService(isSpike) {
  const endpoints = [
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`, payload: generateLedgerPayload() },
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.BALANCE}/acc_${Math.floor(Math.random() * 5000)}`, method: 'GET' },
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.HISTORY}/acc_${Math.floor(Math.random() * 5000)}`, method: 'GET' },
    { url: `${BASE_URL}${ENDPOINTS.LEDGER.RECONCILE}`, payload: JSON.stringify({ account_ids: [`acc_${Date.now()}`] }) }
  ];
  
  const endpoint = endpoints[Math.floor(Math.random() * endpoints.length)];
  
  const res = endpoint.method === 'GET'
    ? http.get(endpoint.url, { headers: HEADERS, timeout: '10s' })
    : http.post(endpoint.url, endpoint.payload, { headers: HEADERS, timeout: '10s' });
  
  const success = check(res, {
    'ledger status is 200 or 201': (r) => r.status === 200 || r.status === 201,
    'ledger received': (r) => r.status !== 0
  });
  
  ledgerLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function testFraudService(isSpike) {
  // Fraud service gets extra noisy during spikes (more checks, batch operations)
  const endpoints = isSpike ? [
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`, payload: generateFraudPayload(), weight: 0.6 },
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.BATCH}`, payload: JSON.stringify({ transactions: Array(10).fill({}) }), weight: 0.4 }
  ] : [
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`, payload: generateFraudPayload(), weight: 0.9 },
    { url: `${BASE_URL}${ENDPOINTS.FRAUD.REPORT}/txn_${Date.now()}`, method: 'GET', weight: 0.1 }
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
    'fraud status is 200': (r) => r.status === 200,
    'fraud received': (r) => r.status !== 0
  });
  
  fraudLatency.add(res.timings.duration);
  errorRate.add(!success);
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function setup() {
  return { START_TIME: Date.now() };
}

export function handleSummary(data) {
  return {
    'scenario-4-noisy-baseline-summary.json': JSON.stringify(data, null, 2),
    stdout: `
╔══════════════════════════════════════════════════════════════════╗
║       SCENARIO 4: NOISY BASELINE - TEST SUMMARY                 ║
╚══════════════════════════════════════════════════════════════════╝

Duration: 2 hours
Pattern: Random walk (80-320 RPS) with 4 unpredictable spikes

📊 RESULTS:
- Total Requests: ${data.metrics.http_reqs.values.count}
- Spike Events Detected: ${data.metrics.spike_events.values.count}
- Error Rate: ${(data.metrics.errors.values.rate * 100).toFixed(2)}%
- Avg RPS: ${data.metrics.http_reqs.values.rate.toFixed(2)}
- RPS Variance: ${(data.metrics.noise_level.values.avg * 100).toFixed(2)}%

⏱️  LATENCY DISTRIBUTION (P95):
- Payment: ${data.metrics.payment_latency.values['p(95)'].toFixed(2)}ms
- Ledger: ${data.metrics.ledger_latency.values['p(95)'].toFixed(2)}ms
- Fraud: ${data.metrics.fraud_latency.values['p(95)'].toFixed(2)}ms

🎯 AI ENGINE CHECK:
- False Positive Rate ≤12%? [MANUAL VERIFICATION]
- Caught ≥80% of real anomalies? [CHECK CONFUSION MATRIX]
- Filtered out noise successfully? [CHECK GRAFANA ANNOTATIONS]

Expected Behavior: AI should NOT alert on normal variance
Expected Detection: Only alert on true drift (hidden in spike #4?)
Expected Recommendation: "Widen prediction bands, increase confidence threshold"

🔊 NOISE CHARACTERISTICS:
- Spike 1: 15 min mark (250 RPS)
- Spike 2: 45 min mark (280 RPS)
- Spike 3: 75 min mark (220 RPS)
- Spike 4: 105 min mark (320 RPS) ← TRUE ANOMALY
- Baseline variance: ±20 RPS normal

⚠️  CRITICAL TEST:
This scenario tests AI's ability to distinguish signal from noise.
High variance is EXPECTED, not every spike should trigger alert.
`
  };
}
