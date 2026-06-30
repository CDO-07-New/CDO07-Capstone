#!/usr/bin/env bash
###############################################################################
# K6 Test Runner - All Scenarios
# Runs all 4 test scenarios sequentially with proper monitoring
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ALB_DNS="${ALB_DNS:-}"
RESULTS_DIR="results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

###############################################################################
# Helper Functions
###############################################################################

log_info() {
  echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
  echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
  echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
  log_info "Checking prerequisites..."
  
  # Check k6 installed
  if ! command -v k6 &> /dev/null; then
    log_error "k6 is not installed. Please install: https://k6.io/docs/getting-started/installation/"
    exit 1
  fi
  
  # Check ALB_DNS set
  if [ -z "$ALB_DNS" ]; then
    log_error "ALB_DNS environment variable not set"
    echo ""
    echo "Please set ALB_DNS:"
    echo "  export ALB_DNS=http://internal-cdo-07-sandbox-alb-xxxxx.us-east-1.elb.amazonaws.com"
    echo ""
    echo "Or get it from Terraform:"
    echo "  cd ../infra/environments/sandbox"
    echo "  terraform output alb_dns_name"
    exit 1
  fi
  
  log_success "Prerequisites check passed"
}

test_connectivity() {
  log_info "Testing connectivity to ALB..."
  
  if curl -s -f -m 5 "${ALB_DNS}/health" > /dev/null 2>&1; then
    log_success "ALB is reachable"
  else
    log_warning "Cannot reach ALB at ${ALB_DNS}/health"
    log_warning "This might be OK if ALB is internal (requires VPC access)"
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  fi
}

create_results_dir() {
  mkdir -p "$RESULTS_DIR"
  log_info "Results will be saved to: $RESULTS_DIR/"
}

run_scenario() {
  local scenario_num=$1
  local scenario_file=$2
  local scenario_name=$3
  local duration=$4
  
  log_info "=================================================="
  log_info "SCENARIO $scenario_num: $scenario_name"
  log_info "Duration: $duration"
  log_info "=================================================="
  
  local output_file="${RESULTS_DIR}/scenario-${scenario_num}-${TIMESTAMP}.json"
  
  log_info "Starting test..."
  log_warning "This will take $duration. Monitor in Grafana:"
  log_info "  - CPU/Memory metrics per service"
  log_info "  - AI prediction annotations"
  log_info "  - Slack alerts"
  
  if k6 run \
    -e ALB_DNS="$ALB_DNS" \
    --out json="$output_file" \
    "$scenario_file"; then
    
    log_success "Scenario $scenario_num completed successfully"
    log_info "Results saved to: $output_file"
    
    # Generate summary
    if [ -f "${RESULTS_DIR}/scenario-${scenario_num}-${scenario_name,,}-summary.json" ]; then
      log_info "Summary report generated"
    fi
    
  else
    log_error "Scenario $scenario_num failed"
    return 1
  fi
  
  echo ""
  read -p "Press Enter to continue to next scenario (or Ctrl+C to stop)..."
  echo ""
}

generate_final_report() {
  log_info "=================================================="
  log_info "ALL SCENARIOS COMPLETED"
  log_info "=================================================="
  
  echo ""
  echo "📊 Test Results Location: $RESULTS_DIR/"
  echo ""
  echo "🎯 Manual Verification Checklist:"
  echo "  [ ] Scenario 1: Lead time ≥15 min verified in Grafana"
  echo "  [ ] Scenario 2: Spike detected within 2 minutes"
  echo "  [ ] Scenario 3: Memory leak recommendation received"
  echo "  [ ] Scenario 4: FP rate ≤12% calculated"
  echo "  [ ] Overall catch rate ≥80% across all scenarios"
  echo "  [ ] All 5-part recommendations validated"
  echo "  [ ] Audit logs encrypted and retained"
  echo ""
  echo "📈 Next Steps:"
  echo "  1. Review Grafana annotations for AI predictions"
  echo "  2. Check Slack for drift alerts"
  echo "  3. Calculate confusion matrix (TP, FP, FN, TN)"
  echo "  4. Generate evaluation report"
  echo "  5. Document findings in curveball-responses.md"
  echo ""
}

###############################################################################
# Main Execution
###############################################################################

main() {
  echo ""
  log_info "╔══════════════════════════════════════════════════════════════╗"
  log_info "║     K6 Load Test Suite - Foresight Lens TF4 CDO-07         ║"
  log_info "╚══════════════════════════════════════════════════════════════╝"
  echo ""
  
  check_prerequisites
  test_connectivity
  create_results_dir
  
  echo ""
  log_warning "⚠️  IMPORTANT:"
  log_warning "  - Total test time: ~8.5 hours (sequential)"
  log_warning "  - Ensure AWS budget won't exceed $200"
  log_warning "  - Monitor cost circuit breaker"
  log_warning "  - Keep Grafana dashboard open"
  echo ""
  
  read -p "Ready to start? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Aborted by user"
    exit 0
  fi
  
  echo ""
  
  # Run all scenarios
  run_scenario 1 "scenario-1-gradual-drift.js" "Gradual Drift" "2 hours" || true
  run_scenario 2 "scenario-2-sudden-spike.js" "Sudden Spike" "2 hours" || true
  run_scenario 3 "scenario-3-slow-leak.js" "Slow Leak" "2.5 hours" || true
  run_scenario 4 "scenario-4-noisy-baseline.js" "Noisy Baseline" "2 hours" || true
  
  generate_final_report
}

# Run only if executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
