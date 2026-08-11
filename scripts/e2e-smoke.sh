#!/usr/bin/env bash
# =============================================================================
# PayGuard — End-to-end smoke test (local stack)
#
# Exercises the golden path: register → Keycloak token → create payment.
# Requires the local infrastructure stack and running Java services.
#
# Usage:
#   ./scripts/local-dev.sh up
#   # start user-service, payment-service, fraud-engine, api-gateway
#   ./scripts/e2e-smoke.sh
# =============================================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATEWAY="${PAYGUARD_GATEWAY_URL:-http://localhost:8090}"
USER_SERVICE="${PAYGUARD_USER_SERVICE_URL:-http://localhost:8086}"
PAYMENT_SERVICE="${PAYGUARD_PAYMENT_SERVICE_URL:-http://localhost:8082}"
FRAUD_ENGINE="${PAYGUARD_FRAUD_ENGINE_URL:-http://localhost:8083}"
KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8180}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-payguard}"
KEYCLOAK_CLIENT_ID="${KEYCLOAK_PUBLIC_CLIENT_ID:-payguard-public}"

EMAIL="e2e-$(date +%s)@smoke.test"
PASSWORD="SmokeTestPassw0rd!"
MERCHANT="E2E Merchant $(date +%s)"

log() { printf '[e2e] %s\n' "$*"; }
fail() { printf '[e2e] FAIL: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

wait_for() {
  local url="$1"
  local name="$2"
  local attempts="${3:-30}"
  for ((i = 1; i <= attempts; i++)); do
    if curl -sf "$url" >/dev/null 2>&1; then
      log "$name is up"
      return 0
    fi
    sleep 2
  done
  fail "$name not reachable at $url"
}

require_cmd curl
require_cmd python3

log "Waiting for infrastructure health endpoints..."
wait_for "$KEYCLOAK_URL/health/ready" "keycloak" 45
wait_for "$USER_SERVICE/actuator/health" "user-service"
wait_for "$FRAUD_ENGINE/actuator/health" "fraud-engine"
wait_for "$PAYMENT_SERVICE/actuator/health" "payment-service"

log "Registering merchant via user-service..."
REGISTER_STATUS=$(curl -s -o /tmp/payguard-e2e-register.json -w '%{http_code}' \
  -X POST "$USER_SERVICE/v1/merchants/register" \
  -H 'Content-Type: application/json' \
  -d "{\"merchantName\":\"$MERCHANT\",\"email\":\"$EMAIL\",\"password\":\"$PASSWORD\"}")
[[ "$REGISTER_STATUS" == "201" ]] || fail "register returned $REGISTER_STATUS: $(cat /tmp/payguard-e2e-register.json)"

log "Obtaining access token from Keycloak..."
TOKEN_BODY=$(curl -sf -X POST "$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token" \
  -H 'Content-Type: application/x-www-form-urlencoded' \
  -d "grant_type=password" \
  -d "client_id=$KEYCLOAK_CLIENT_ID" \
  -d "username=$EMAIL" \
  -d "password=$PASSWORD")
ACCESS_TOKEN=$(python3 - <<'PY' "$TOKEN_BODY"
import json, sys
print(json.loads(sys.argv[1])["access_token"])
PY
)
[[ -n "$ACCESS_TOKEN" ]] || fail "Keycloak did not return access_token"

MERCHANT_ID=$(python3 - <<'PY' "$ACCESS_TOKEN"
import base64, json, sys
payload = sys.argv[1].split(".")[1]
payload += "=" * (-len(payload) % 4)
claims = json.loads(base64.urlsafe_b64decode(payload))
print(claims.get("merchant_id", ""))
PY
)
[[ -n "$MERCHANT_ID" ]] || fail "could not extract merchant_id from JWT"

log "Creating payment (merchant=$MERCHANT_ID)..."
PAYMENT_STATUS=$(curl -s -o /tmp/payguard-e2e-payment.json -w '%{http_code}' \
  -X POST "$PAYMENT_SERVICE/v1/payments" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"amount_minor\":2500,\"currency\":\"USD\"}")
[[ "$PAYMENT_STATUS" == "201" || "$PAYMENT_STATUS" == "200" ]] \
  || fail "payment returned $PAYMENT_STATUS: $(cat /tmp/payguard-e2e-payment.json)"

FRAUD_DECISION=$(python3 - <<'PY' /tmp/payguard-e2e-payment.json
import json, sys
body = json.load(open(sys.argv[1]))
print(body.get("fraud_decision") or body.get("fraudDecision") or body.get("status", ""))
PY
)
[[ -n "$FRAUD_DECISION" ]] || fail "payment response missing fraud decision / status"

log "Payment created with decision/status: $FRAUD_DECISION"
log "E2E smoke passed"
