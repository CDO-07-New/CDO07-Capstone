/**
 * K6 Test Configuration
 * Shared config for all test scenarios
 */

// ALB endpoint - set via environment variable or use default
export const BASE_URL = __ENV.ALB_DNS || 'http://internal-cdo-07-sandbox-alb-xxxxx.us-east-1.elb.amazonaws.com';

// Test duration settings
export const TEST_DURATION = {
  SHORT: '5m',      // Quick smoke test
  MEDIUM: '30m',    // Standard test
  LONG: '2h',       // Full test window (requirement: ≥2h)
  EXTENDED: '4h'    // Extended drift observation
};

// RPS (Requests Per Second) targets
export const RPS_TARGETS = {
  LOW: 10,
  BASELINE: 100,    // Requirement: 100 RPS sustained
  SPIKE: 500,
  EXTREME: 1000
};

// Service endpoints
export const ENDPOINTS = {
  PAYMENT: {
    HEALTH: '/health',
    AUTHORIZE: '/payment/authorize',
    CAPTURE: '/payment/capture',
    REFUND: '/payment/refund',
    STATUS: '/payment/status'
  },
  LEDGER: {
    HEALTH: '/health',
    ENTRY: '/ledger/entry',
    BALANCE: '/ledger/balance',
    HISTORY: '/ledger/history',
    RECONCILE: '/ledger/reconcile'
  },
  FRAUD: {
    HEALTH: '/health',
    CHECK: '/fraud/check',
    BATCH: '/fraud/batch-check',
    REPORT: '/fraud/report',
    FEEDBACK: '/fraud/feedback'
  }
};

// Realistic payload generators
export function generatePaymentPayload(tenantId = 'tier-1') {
  return JSON.stringify({
    amount: Math.floor(Math.random() * 10000) / 100,
    currency: 'USD',
    customer_id: `cust_${Math.random().toString(36).substr(2, 9)}`,
    payment_method: ['card', 'bank', 'wallet'][Math.floor(Math.random() * 3)],
    tenant_id: tenantId
  });
}

export function generateLedgerPayload(tenantId = 'tier-1') {
  return JSON.stringify({
    account_id: `acc_${Math.floor(Math.random() * 10000)}`,
    amount: Math.floor(Math.random() * 100000) / 100,
    type: Math.random() > 0.5 ? 'debit' : 'credit',
    description: `Transaction ${Date.now()}`,
    tenant_id: tenantId
  });
}

export function generateFraudPayload(tenantId = 'tier-1') {
  return JSON.stringify({
    transaction_id: `txn_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
    amount: Math.floor(Math.random() * 50000) / 100,
    location: ['US', 'UK', 'SG', 'JP'][Math.floor(Math.random() * 4)],
    device_fingerprint: Math.random().toString(36).substr(2, 16),
    tenant_id: tenantId
  });
}

// Thresholds matching SLO requirements
export const THRESHOLDS = {
  // P95 latency must stay under 500ms for healthy service
  http_req_duration: ['p(95)<500'],
  
  // Error rate must be below 1%
  http_req_failed: ['rate<0.01'],
  
  // Minimum throughput (90% of target RPS)
  http_reqs: ['rate>90']
};

// Common HTTP headers
export const HEADERS = {
  'Content-Type': 'application/json',
  'User-Agent': 'k6-foresight-lens-load-test/1.0'
};

// Generate headers with tenant ID for proper multi-tenant telemetry routing
export function generateHeaders(tenantId = 'tier-1') {
  return {
    'Content-Type': 'application/json',
    'User-Agent': 'k6-foresight-lens-load-test/1.0',
    'X-Tenant-Id': tenantId
  };
}

export default {
  BASE_URL,
  TEST_DURATION,
  RPS_TARGETS,
  ENDPOINTS,
  THRESHOLDS,
  HEADERS
};
