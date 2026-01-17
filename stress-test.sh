#!/usr/bin/env bash
# Stress test for org-agenda-api
set -euo pipefail

BASE_URL="${BASE_URL:-https://colonelpanic-org-agenda.fly.dev}"
AUTH_USER="${AUTH_USER:-imalison}"
AUTH_PASSWORD="${AUTH_PASSWORD:-}"

# Check for auth password
if [[ -z "$AUTH_PASSWORD" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$SCRIPT_DIR/secrets/auth-password.age" ]]; then
    IDENTITY=""
    for key_type in ed25519 rsa; do
      if [[ -f "$HOME/.ssh/id_${key_type}" ]]; then
        IDENTITY="$HOME/.ssh/id_${key_type}"
        break
      fi
    done
    if [[ -n "$IDENTITY" ]]; then
      AUTH_PASSWORD=$(age -d -i "$IDENTITY" "$SCRIPT_DIR/secrets/auth-password.age")
    fi
  fi
fi

if [[ -z "$AUTH_PASSWORD" ]]; then
  echo "Error: AUTH_PASSWORD not set and could not decrypt from secrets"
  exit 1
fi

# Test configuration
NUM_REQUESTS=${NUM_REQUESTS:-10}
PARALLEL_REQUESTS=${PARALLEL_REQUESTS:-1}
DELAY_MS=${DELAY_MS:-100}

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=== Org Agenda API Stress Test ==="
echo "URL: $BASE_URL"
echo "Requests: $NUM_REQUESTS"
echo "Parallel: $PARALLEL_REQUESTS"
echo "Delay: ${DELAY_MS}ms"
echo ""

# Test helper functions
test_endpoint() {
  local endpoint=$1
  local method=${2:-GET}
  local data=${3:-}
  local description=${4:-}

  local start_time=$(date +%s%3N)
  local http_code
  local response

  if [[ "$method" == "GET" ]]; then
    response=$(curl -s -w "\n%{http_code}" \
      -u "$AUTH_USER:$AUTH_PASSWORD" \
      "$BASE_URL$endpoint" 2>&1)
  else
    response=$(curl -s -w "\n%{http_code}" \
      -X "$method" \
      -u "$AUTH_USER:$AUTH_PASSWORD" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$BASE_URL$endpoint" 2>&1)
  fi

  local end_time=$(date +%s%3N)
  local duration=$((end_time - start_time))

  http_code=$(echo "$response" | tail -n1)
  local body=$(echo "$response" | head -n -1)

  if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}[OK]${NC} $description - ${duration}ms"
    return 0
  else
    echo -e "${RED}[FAIL]${NC} $description - HTTP $http_code - ${duration}ms"
    echo "  Response: ${body:0:200}"
    return 1
  fi
}

# Test 1: Basic health check
echo "--- Test 1: Basic Health Check ---"
if test_endpoint "/get-all-todos" "GET" "" "GET /get-all-todos"; then
  echo "  Server is responding"
else
  echo "  WARNING: Server may be down or slow"
fi
echo ""

# Test 2: Get today's agenda
echo "--- Test 2: Get Today's Agenda ---"
test_endpoint "/get-todays-agenda" "GET" "" "GET /get-todays-agenda" || true
echo ""

# Test 3: Mixed endpoint stress test
echo "--- Test 3: Mixed Endpoint Stress Test ---"
echo "Pattern: create-todo -> get-all-todos -> create-todo -> health -> ..."
success_count=0
fail_count=0
total_duration=0
consecutive_fails=0

# Array of endpoints to cycle through
endpoints=("/create-todo:POST" "/get-all-todos:GET" "/create-todo:POST" "/health:GET" "/agenda:GET")

for i in $(seq 1 $NUM_REQUESTS); do
  # Cycle through endpoints
  endpoint_idx=$(( (i - 1) % ${#endpoints[@]} ))
  endpoint_spec="${endpoints[$endpoint_idx]}"
  endpoint="${endpoint_spec%%:*}"
  method="${endpoint_spec##*:}"

  timestamp=$(date +%s%N | tail -c 10)
  data=""
  if [[ "$endpoint" == "/create-todo" ]]; then
    title="Stress test todo $i - $timestamp"
    data="{\"title\": \"$title\"}"
  fi

  start_time=$(date +%s%3N)

  if [[ "$method" == "GET" ]]; then
    response=$(curl -s -w "\n%{http_code}" \
      -u "$AUTH_USER:$AUTH_PASSWORD" \
      "$BASE_URL$endpoint" 2>&1)
  else
    response=$(curl -s -w "\n%{http_code}" \
      -X POST \
      -u "$AUTH_USER:$AUTH_PASSWORD" \
      -H "Content-Type: application/json" \
      -d "$data" \
      "$BASE_URL$endpoint" 2>&1)
  fi

  end_time=$(date +%s%3N)
  duration=$((end_time - start_time))
  total_duration=$((total_duration + duration))

  http_code=$(echo "$response" | tail -n1)
  body=$(echo "$response" | head -n -1)

  if [[ "$http_code" == "200" ]]; then
    echo -e "${GREEN}[OK]${NC} Request $i ($method $endpoint) - ${duration}ms"
    ((success_count++)) || true
    consecutive_fails=0
  else
    echo -e "${RED}[FAIL]${NC} Request $i ($method $endpoint) - HTTP $http_code - ${duration}ms"
    echo "  Response: ${body:0:500}"
    ((fail_count++)) || true
    ((consecutive_fails++)) || true

    # If we get 3 consecutive failures, server might be stuck
    if [[ $consecutive_fails -ge 3 ]]; then
      echo -e "${YELLOW}WARNING: Multiple consecutive failures detected${NC}"
      echo "Server may be in a bad state. Waiting 5 seconds..."
      sleep 5
      consecutive_fails=0
    fi
  fi

  # Add delay between requests
  if [[ $i -lt $NUM_REQUESTS && $DELAY_MS -gt 0 ]]; then
    # Convert milliseconds to seconds (e.g., 100ms -> 0.1s)
    sleep "$(awk "BEGIN {printf \"%.3f\", $DELAY_MS/1000}")"
  fi
done

echo ""
echo "--- Results ---"
echo "Success: $success_count / $NUM_REQUESTS"
echo "Failed: $fail_count / $NUM_REQUESTS"
avg_duration=$((total_duration / NUM_REQUESTS))
echo "Average response time: ${avg_duration}ms"
echo ""

# Test 4: Parallel requests (if enabled)
if [[ $PARALLEL_REQUESTS -gt 1 ]]; then
  echo "--- Test 4: Parallel Create Todo ---"
  echo "Sending $PARALLEL_REQUESTS requests in parallel..."

  parallel_success=0
  parallel_fail=0

  # Create temp files for parallel results
  tmpdir=$(mktemp -d)
  trap "rm -rf $tmpdir" EXIT

  for i in $(seq 1 $PARALLEL_REQUESTS); do
    (
      timestamp=$(date +%s%N | tail -c 10)
      title="Parallel test $i - $timestamp"
      data="{\"title\": \"$title\"}"

      response=$(curl -s -w "\n%{http_code}" \
        -X POST \
        -u "$AUTH_USER:$AUTH_PASSWORD" \
        -H "Content-Type: application/json" \
        -d "$data" \
        "$BASE_URL/create-todo" 2>&1)

      http_code=$(echo "$response" | tail -n1)
      echo "$http_code" > "$tmpdir/result_$i"
    ) &
  done

  wait

  for i in $(seq 1 $PARALLEL_REQUESTS); do
    result=$(cat "$tmpdir/result_$i" 2>/dev/null || echo "000")
    if [[ "$result" == "200" ]]; then
      ((parallel_success++)) || true
    else
      ((parallel_fail++)) || true
    fi
  done

  echo "Parallel Success: $parallel_success / $PARALLEL_REQUESTS"
  echo "Parallel Failed: $parallel_fail / $PARALLEL_REQUESTS"
fi

echo ""
echo "=== Stress Test Complete ==="

# Exit with error if any tests failed
if [[ $fail_count -gt 0 ]]; then
  exit 1
fi
