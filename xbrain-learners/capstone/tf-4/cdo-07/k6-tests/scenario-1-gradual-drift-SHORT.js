/**
 * K6 Test Scenario 1: GRADUAL DRIFT (SHORT VERSION for DEMO/DEV)
 * 
 * ⚠️ CHÚ Ý: Đây là bản RÚT NGẮN để test nhanh (~20 phút thay vì 2 giờ)
 * 
 * Simulates slow performance degradation in COMPRESSED timeline
 * Mimics: Memory leak, connection pool exhaustion, cache pollution
 * 
 * Expected AI Detection: 
 * - Lead time ≥2 min before SLO breach (scaled down từ 15 min)
 * - Drift detection on memory_utilization upward trend
 * - Recommendation: "Scale memory from 512MB → 1024MB"
 * 
 * Load Pattern (COMPRESSED 6x):
 * - Start: 50 RPS (normal load)
 * - Middle: 100 RPS (baseline)
 * - End: 150 RPS (gradual increase)
 * - Duration: 20 minutes (1200s) - THAY VÌ 2 giờ
 * 
 * Use Case:
 * - Development testing
 * - Quick smoke test
 * - CI/CD pipeline
 * - Demo preparation
 * 
 * ⚠️ LƯU Ý: 
 * - Window Feeder vẫn query 2h window từ InfluxDB
 * - AI Engine sẽ thấy ÍT DATA HƠN (chỉ 20 phút thay vì 2 giờ)
 * - Có thể drift detection KÉM CHÍNH XÁC HƠN
 * 
 * Để chạy FULL TEST 2 giờ: dùng scenario-1-gradual-drift.js
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
  // COMPRESSED: 2 hours → 20 minutes (6x faster)
  scenarios: {
    gradual_drift_short: {
      executor: 'ramping-arrival-rate',
      startRate: 10,
      timeUnit: '1s',
      preAllocatedVUs: 150,
      maxVUs: 500,
      stages: [
    // Phase 1: Warm-up (2 min) - 50 RPS
    { duration: '2m', target: 50 },
    
    // Phase 2: Baseline (5 min) - 100 RPS
    { duration: '5m', target: 100 },
    
    // Phase 3: Gradual increase (10 min) - 100→150 RPS
    { duration: '10m', target: 150 },
    
    // Phase 4: Sustained high load (3 min) - 150 RPS
    { duration: '3m', target: 150 }
      ],
    }
  },
  
  thresholds: {
    // Thresholds giữ nguyên như original
    'http_req_duration': ['p(95)<500', 'p(99)<1000'],
    'http_req_failed': ['rate<0.05'],
    'errors': ['rate<0.05'],
  },
  
  // Tags để phân biệt với full test
  tags: {
    scenario: 'gradual-drift-SHORT',
    test_type: 'demo',
    duration: '20min'
  }
};

// Tenant distribution (same as original)
const tenants = ['tenant-finco', 'tenant-bankx', 'tenant-paytech'];

export default function () {
  const tenant = tenants[Math.floor(Math.random() * tenants.length)];
  
  // Multi-service load pattern (80% payment, 15% ledger, 5% fraud)
  const rand = Math.random();
  
  if (rand < 0.80) {
    // Payment Gateway
    const paymentRes = http.post(
      `${BASE_URL}${ENDPOINTS.PAYMENT.AUTHORIZE}`,
      generatePaymentPayload(tenant),
      { headers: HEADERS, tags: { endpoint: 'payment-authorize', tenant } }
    );
    
    paymentLatency.add(paymentRes.timings.duration);
    
    const success = check(paymentRes, {
      'payment status 200': (r) => r.status === 200,
      'payment has transaction_id': (r) => {
        if (r.status !== 200) return false;
        try {
          const body = JSON.parse(r.body);
          return body.transaction_id !== undefined;
        } catch (e) {
          console.error(`Payment response parsing failed: ${r.status} ${r.body.substring(0, 200)}`);
          return false;
        }
      }
    });
    
    errorRate.add(!success);
    
  } else if (rand < 0.95) {
    // Ledger Service
    const ledgerRes = http.post(
      `${BASE_URL}${ENDPOINTS.LEDGER.ENTRY}`,
      generateLedgerPayload(tenant),
      { headers: HEADERS, tags: { endpoint: 'ledger-entry', tenant } }
    );
    
    ledgerLatency.add(ledgerRes.timings.duration);
    
    const success = check(ledgerRes, {
      'ledger status 200 or 201': (r) => r.status === 200 || r.status === 201,
      'ledger has entry_id': (r) => {
        if (r.status !== 200 && r.status !== 201) return false;
        try {
          const body = JSON.parse(r.body);
          return body.entry_id !== undefined;
        } catch (e) {
          console.error(`Ledger response parsing failed: ${r.status} ${r.body.substring(0, 200)}`);
          return false;
        }
      }
    });
    
    errorRate.add(!success);
    
  } else {
    // Fraud Detection
    const fraudRes = http.post(
      `${BASE_URL}${ENDPOINTS.FRAUD.CHECK}`,
      generateFraudPayload(tenant),
      { headers: HEADERS, tags: { endpoint: 'fraud-check', tenant } }
    );
    
    fraudLatency.add(fraudRes.timings.duration);
    
    const success = check(fraudRes, {
      'fraud status 200': (r) => r.status === 200,
      'fraud has score': (r) => {
        if (r.status !== 200) return false;
        try {
          const body = JSON.parse(r.body);
          return body.risk_score !== undefined || body.fraud_score !== undefined;
        } catch (e) {
          console.error(`Fraud response parsing failed: ${r.status} ${r.body.substring(0, 200)}`);
          return false;
        }
      }
    });
    
    errorRate.add(!success);
  }
  
  // Arrival-rate executor controls pacing; no sleep is needed here.
}

export function handleSummary(data) {
  return {
    'stdout': JSON.stringify({
      scenario: 'gradual-drift-SHORT',
      duration_minutes: 20,
      total_requests: data.metrics.http_reqs.values.count,
      error_rate: data.metrics.errors ? data.metrics.errors.values.rate : 0,
      p95_latency: data.metrics.http_req_duration.values['p(95)'],
      p99_latency: data.metrics.http_req_duration.values['p(99)'],
      note: 'This is COMPRESSED version (20 min instead of 2 hours). Use for dev/demo only.'
    }, null, 2)
  };
}

/**
 * 🎯 DEMO EXECUTION GUIDE
 * 
 * Chạy short version này để:
 * 1. ✅ Test infrastructure hoạt động (ALB, ECS, Kinesis, Lambda)
 * 2. ✅ Verify telemetry flow (metrics → InfluxDB)
 * 3. ✅ Quick smoke test trước khi chạy full 2h test
 * 4. ✅ Demo nhanh cho stakeholders (20 phút thay vì 2 giờ)
 * 
 * Command:
 * k6 run -e ALB_DNS=http://<alb-dns> scenario-1-gradual-drift-SHORT.js
 * 
 * Expected Cost: ~$0.50 (20 phút ECS + Lambda + Kinesis)
 * 
 * ⚠️ CHO PRODUCTION EVALUATION: Phải chạy full 2h version
 * k6 run -e ALB_DNS=http://<alb-dns> scenario-1-gradual-drift.js
 * 
 * Cost Full Test: ~$6 (2 giờ × 3 services × 0.25 vCPU × $0.04)
 * 
 * 🎯 AI ENGINE CHECK:
 * - Did AI detect drift in 20 min window? [MANUAL VERIFICATION]
 * - Check CloudWatch Logs: /aws/lambda/tf4-cdo07-sandbox-window-feeder
 * - Check S3 Audit: s3://<audit-bucket>/window-feeder/
 * - Check Slack alerts
 */
