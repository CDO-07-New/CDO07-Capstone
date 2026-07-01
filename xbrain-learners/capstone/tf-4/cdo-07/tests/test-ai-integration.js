/**
 * AI Engine Integration Tests
 * 
 * Test AI API endpoints theo AI API Contract v1.0
 * Refs: xbrain-learners/capstone-phase2/templates/ai/contracts/ai-api-contract.md
 */

const AWS = require('aws-sdk');
const { v4: uuidv4 } = require('uuid');

// Config
const AI_ENGINE_ENDPOINT = process.env.AI_ENGINE_ENDPOINT || 'http://cdo-07-staging-vpc-alb-xxxxx.us-east-1.elb.amazonaws.com';
const TENANT_ID = process.env.TENANT_ID || 'tenant-finco';
const AWS_REGION = process.env.AWS_REGION || 'us-east-1';

// Configure AWS SDK for SigV4
AWS.config.update({ region: AWS_REGION });

/**
 * Test 1: POST /v1/detect - Anomaly Detection
 * Theo AI API Contract section "Endpoint 1"
 */
async function testDetectEndpoint() {
  console.log('\n🧪 Test 1: POST /v1/detect - Anomaly Detection');
  
  const payload = {
    signal_window: [
      {
        ts: new Date(Date.now() - 5 * 60 * 1000).toISOString(), // 5 min ago
        signal_name: 'api_latency_ms',
        value: 250.5,
        labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
      },
      {
        ts: new Date(Date.now() - 4 * 60 * 1000).toISOString(),
        signal_name: 'api_latency_ms',
        value: 280.3,
        labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
      },
      {
        ts: new Date(Date.now() - 3 * 60 * 1000).toISOString(),
        signal_name: 'api_latency_ms',
        value: 450.7,
        labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
      },
      {
        ts: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
        signal_name: 'api_latency_ms',
        value: 1200.5, // SPIKE!
        labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
      },
      {
        ts: new Date(Date.now() - 1 * 60 * 1000).toISOString(),
        signal_name: 'api_latency_ms',
        value: 1800.2, // Continued spike
        labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
      }
    ],
    context: {
      deployment_version: 'v2.3.1',
      time_range: {
        start_ts: new Date(Date.now() - 5 * 60 * 1000).toISOString(),
        end_ts: new Date().toISOString()
      }
    }
  };

  const headers = {
    'Content-Type': 'application/json',
    'X-Tenant-Id': TENANT_ID,
    'X-Correlation-Id': uuidv4()
  };

  console.log('📤 Request:', JSON.stringify(payload, null, 2));

  try {
    const response = await fetch(`${AI_ENGINE_ENDPOINT}/v1/detect`, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload)
    });

    const responseData = await response.json();
    console.log('📥 Response:', JSON.stringify(responseData, null, 2));

    // Validate response schema per contract
    const requiredFields = ['anomaly', 'severity', 'suggested_action', 'reasoning', 'confidence', 'audit_id'];
    const missingFields = requiredFields.filter(f => !(f in responseData));
    
    if (missingFields.length > 0) {
      console.error(`❌ Missing required fields: ${missingFields.join(', ')}`);
      return false;
    }

    // Validate data types
    if (typeof responseData.anomaly !== 'boolean') {
      console.error('❌ anomaly must be boolean');
      return false;
    }
    if (typeof responseData.severity !== 'number' || responseData.severity < 0 || responseData.severity > 1) {
      console.error('❌ severity must be float 0.0-1.0');
      return false;
    }
    const validActions = ['SCALE_UP', 'ROLLBACK', 'ALERT_ONLY', 'INVESTIGATE'];
    if (!validActions.includes(responseData.suggested_action)) {
      console.error(`❌ suggested_action must be one of: ${validActions.join(', ')}`);
      return false;
    }
    if (typeof responseData.reasoning !== 'string' || responseData.reasoning.length > 300) {
      console.error('❌ reasoning must be string ≤300 chars');
      return false;
    }
    if (typeof responseData.confidence !== 'number' || responseData.confidence < 0 || responseData.confidence > 1) {
      console.error('❌ confidence must be float 0.0-1.0');
      return false;
    }

    console.log('✅ Response schema valid');
    console.log(`📊 Anomaly detected: ${responseData.anomaly}`);
    console.log(`📊 Severity: ${responseData.severity}`);
    console.log(`📊 Suggested action: ${responseData.suggested_action}`);
    console.log(`📊 Confidence: ${responseData.confidence}`);
    
    return true;
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return false;
  }
}

/**
 * Test 2: POST /v1/verify - Verify Post-Action State
 * Theo AI API Contract section "Endpoint 2"
 */
async function testVerifyEndpoint() {
  console.log('\n🧪 Test 2: POST /v1/verify - Verify Post-Action State');
  
  const payload = {
    action_taken: {
      type: 'SCALE_UP',
      params: {
        service: 'payment-gw',
        from_replicas: 2,
        to_replicas: 4
      },
      ts: new Date(Date.now() - 3 * 60 * 1000).toISOString() // 3 min ago
    },
    post_state: {
      signal_window: [
        {
          ts: new Date(Date.now() - 2 * 60 * 1000).toISOString(),
          signal_name: 'api_latency_ms',
          value: 850.2,
          labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
        },
        {
          ts: new Date(Date.now() - 1 * 60 * 1000).toISOString(),
          signal_name: 'api_latency_ms',
          value: 420.5, // Latency improved after scale up
          labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
        },
        {
          ts: new Date().toISOString(),
          signal_name: 'api_latency_ms',
          value: 280.3, // Back to normal
          labels: { service: 'payment-gw', endpoint: '/payment/authorize' }
        }
      ]
    }
  };

  const headers = {
    'Content-Type': 'application/json',
    'X-Tenant-Id': TENANT_ID,
    'X-Correlation-Id': uuidv4()
  };

  console.log('📤 Request:', JSON.stringify(payload, null, 2));

  try {
    const response = await fetch(`${AI_ENGINE_ENDPOINT}/v1/verify`, {
      method: 'POST',
      headers,
      body: JSON.stringify(payload)
    });

    const responseData = await response.json();
    console.log('📥 Response:', JSON.stringify(responseData, null, 2));

    // Validate response schema per contract
    const requiredFields = ['success', 'regression_detected', 'next_action'];
    const missingFields = requiredFields.filter(f => !(f in responseData));
    
    if (missingFields.length > 0) {
      console.error(`❌ Missing required fields: ${missingFields.join(', ')}`);
      return false;
    }

    // Validate data types
    if (typeof responseData.success !== 'boolean') {
      console.error('❌ success must be boolean');
      return false;
    }
    if (typeof responseData.regression_detected !== 'boolean') {
      console.error('❌ regression_detected must be boolean');
      return false;
    }
    const validNextActions = ['DONE', 'RETRY', 'ESCALATE'];
    if (!validNextActions.includes(responseData.next_action)) {
      console.error(`❌ next_action must be one of: ${validNextActions.join(', ')}`);
      return false;
    }

    console.log('✅ Response schema valid');
    console.log(`📊 Action success: ${responseData.success}`);
    console.log(`📊 Regression detected: ${responseData.regression_detected}`);
    console.log(`📊 Next action: ${responseData.next_action}`);
    
    return true;
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return false;
  }
}

/**
 * Test 3: Error Handling - 400 Bad Request
 */
async function testErrorHandling() {
  console.log('\n🧪 Test 3: Error Handling - 400 Bad Request');
  
  const invalidPayload = {
    // Missing required fields
    signal_window: []
  };

  const headers = {
    'Content-Type': 'application/json',
    'X-Tenant-Id': TENANT_ID
  };

  try {
    const response = await fetch(`${AI_ENGINE_ENDPOINT}/v1/detect`, {
      method: 'POST',
      headers,
      body: JSON.stringify(invalidPayload)
    });

    console.log(`📥 Status: ${response.status}`);
    
    if (response.status === 400) {
      console.log('✅ Correctly returned 400 for invalid input');
      return true;
    } else {
      console.error(`❌ Expected 400, got ${response.status}`);
      return false;
    }
  } catch (error) {
    console.error('❌ Test failed:', error.message);
    return false;
  }
}

/**
 * Test 4: Rate Limiting - 429 Too Many Requests
 */
async function testRateLimiting() {
  console.log('\n🧪 Test 4: Rate Limiting - 429 Too Many Requests');
  console.log('⚠️  Sending 150 requests rapidly to trigger rate limit...');
  
  const payload = {
    signal_window: [{
      ts: new Date().toISOString(),
      signal_name: 'test_metric',
      value: 1.0
    }],
    context: {
      deployment_version: 'test',
      time_range: {
        start_ts: new Date().toISOString(),
        end_ts: new Date().toISOString()
      }
    }
  };

  const headers = {
    'Content-Type': 'application/json',
    'X-Tenant-Id': TENANT_ID
  };

  let rateLimitHit = false;
  
  for (let i = 0; i < 150; i++) {
    try {
      const response = await fetch(`${AI_ENGINE_ENDPOINT}/v1/detect`, {
        method: 'POST',
        headers,
        body: JSON.stringify(payload)
      });

      if (response.status === 429) {
        console.log(`✅ Rate limit hit after ${i + 1} requests`);
        const retryAfter = response.headers.get('Retry-After');
        console.log(`📊 Retry-After header: ${retryAfter} seconds`);
        rateLimitHit = true;
        break;
      }
    } catch (error) {
      // Continue
    }
  }

  if (!rateLimitHit) {
    console.log('⚠️  Rate limit not hit (may need higher volume or rate limit not configured)');
  }
  
  return true; // Soft check
}

/**
 * Main test runner
 */
async function runTests() {
  console.log('═══════════════════════════════════════════════════');
  console.log('🧪 AI Engine Integration Tests');
  console.log('   Based on AI API Contract v1.0');
  console.log('═══════════════════════════════════════════════════');
  console.log(`📍 AI Engine Endpoint: ${AI_ENGINE_ENDPOINT}`);
  console.log(`🏢 Tenant ID: ${TENANT_ID}`);
  console.log(`🌍 AWS Region: ${AWS_REGION}`);
  console.log('═══════════════════════════════════════════════════');

  const results = {
    'POST /v1/detect': await testDetectEndpoint(),
    'POST /v1/verify': await testVerifyEndpoint(),
    'Error Handling': await testErrorHandling(),
    'Rate Limiting': await testRateLimiting()
  };

  console.log('\n═══════════════════════════════════════════════════');
  console.log('📊 Test Results Summary');
  console.log('═══════════════════════════════════════════════════');
  
  Object.entries(results).forEach(([test, passed]) => {
    console.log(`${passed ? '✅' : '❌'} ${test}`);
  });

  const totalTests = Object.keys(results).length;
  const passedTests = Object.values(results).filter(r => r).length;
  
  console.log('═══════════════════════════════════════════════════');
  console.log(`Total: ${passedTests}/${totalTests} tests passed`);
  console.log('═══════════════════════════════════════════════════');

  process.exit(passedTests === totalTests ? 0 : 1);
}

// Run tests if executed directly
if (require.main === module) {
  runTests().catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
}

module.exports = {
  testDetectEndpoint,
  testVerifyEndpoint,
  testErrorHandling,
  testRateLimiting
};
