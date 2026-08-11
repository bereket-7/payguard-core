#!/usr/bin/env bash
# =============================================================================
# migrate-users-to-keycloak.sh — One-time migration for legacy app_user rows
#
# Creates Keycloak users from existing Postgres records and sets a temporary
# password. Users must reset their password on first Keycloak login.
#
# Prerequisites:
#   - Keycloak running with payguard realm imported
#   - user-service DB reachable
#   - curl, psql, python3
#
# Usage:
#   export KEYCLOAK_URL=http://localhost:8180
#   export KEYCLOAK_ADMIN_CLIENT_SECRET=payguard-admin-secret-local-dev
#   export SPRING_DATASOURCE_URL=jdbc:postgresql://localhost:5433/payguard_users
#   ./scripts/migrate-users-to-keycloak.sh [--dry-run]
# =============================================================================
set -euo pipefail

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
fi

KEYCLOAK_URL="${KEYCLOAK_URL:-http://localhost:8180}"
KEYCLOAK_REALM="${KEYCLOAK_REALM:-payguard}"
ADMIN_CLIENT_ID="${KEYCLOAK_ADMIN_CLIENT_ID:-payguard-admin}"
ADMIN_CLIENT_SECRET="${KEYCLOAK_ADMIN_CLIENT_SECRET:-payguard-admin-secret-local-dev}"
DB_URL="${SPRING_DATASOURCE_URL:-jdbc:postgresql://localhost:5433/payguard_users}"
DB_USER="${SPRING_DATASOURCE_USERNAME:-payguard}"
DB_PASS="${SPRING_DATASOURCE_PASSWORD:-payguard_secret}"
TEMP_PASSWORD="${MIGRATION_TEMP_PASSWORD:-ChangeMeNow123!}"

log() { printf '[migrate] %s\n' "$*"; }

if [[ "$DB_URL" =~ jdbc:postgresql://([^:/]+):?([0-9]*)/([^?]+) ]]; then
  PGHOST="${BASH_REMATCH[1]}"
  PGPORT="${BASH_REMATCH[2]:-5432}"
  PGDATABASE="${BASH_REMATCH[3]}"
else
  echo "Could not parse SPRING_DATASOURCE_URL: $DB_URL" >&2
  exit 1
fi

export PGPASSWORD="$DB_PASS"

admin_token() {
  curl -sf -X POST "$KEYCLOAK_URL/realms/$KEYCLOAK_REALM/protocol/openid-connect/token" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    -d "grant_type=client_credentials" \
    -d "client_id=$ADMIN_CLIENT_ID" \
    -d "client_secret=$ADMIN_CLIENT_SECRET" \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])'
}

TOKEN="$(admin_token)"

while IFS='|' read -r user_id email merchant_id merchant_tier keycloak_user_id; do
  [[ -z "$user_id" ]] && continue
  if [[ -n "$keycloak_user_id" && "$keycloak_user_id" != "NULL" ]]; then
    log "skip $email (already linked)"
    continue
  fi

  roles=$(psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$PGDATABASE" -At \
    -c "SELECT role FROM app_user_roles WHERE user_id='$user_id' ORDER BY role")

  scope="payments:read"
  while IFS= read -r role; do
    case "$role" in
      MERCHANT_ADMIN) scope="$scope payments:write payment:review merchant:write" ;;
      MERCHANT_ANALYST) scope="$scope payment:review" ;;
      PLATFORM_ADMIN) scope="$scope payments:write payment:review merchant:write platform:admin" ;;
    esac
  done <<< "$roles"

  payload=$(python3 - <<PY
import json
print(json.dumps({
  "username": "$email",
  "email": "$email",
  "enabled": True,
  "emailVerified": True,
  "attributes": {
    "payguard_user_id": ["$user_id"],
    "merchant_id": ["$merchant_id"],
    "merchant_tier": ["$merchant_tier"],
    "scope": ["$scope"]
  },
  "credentials": [{"type": "password", "value": "$TEMP_PASSWORD", "temporary": True}]
}))
PY
)

  if $DRY_RUN; then
    log "would migrate $email"
    continue
  fi

  response=$(curl -si -X POST "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/users" \
    -H "Authorization: Bearer $TOKEN" \
    -H 'Content-Type: application/json' \
    -d "$payload")
  status=$(echo "$response" | head -1 | awk '{print $2}')
  kc_id=$(echo "$response" | awk -F/ '/^[Ll]ocation:/ {print $NF}' | tr -d '\r')

  if [[ "$status" != "201" || -z "$kc_id" ]]; then
    log "FAILED $email (HTTP $status)"
    continue
  fi

  for role in $roles; do
    curl -sf -X POST "$KEYCLOAK_URL/admin/realms/$KEYCLOAK_REALM/users/$kc_id/role-mappings/realm" \
      -H "Authorization: Bearer $TOKEN" \
      -H 'Content-Type: application/json' \
      -d "[{\"name\":\"$role\"}]" >/dev/null || true
  done

  psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$PGDATABASE" -q \
    -c "UPDATE app_user SET keycloak_user_id='$kc_id', password_hash=NULL WHERE id='$user_id'"

  log "migrated $email -> $kc_id (temporary password set)"
done < <(psql -h "$PGHOST" -p "$PGPORT" -U "$DB_USER" -d "$PGDATABASE" -At -F'|' -c \
  "SELECT u.id, u.email, u.merchant_id, m.tier, u.keycloak_user_id
   FROM app_user u JOIN merchant m ON m.id = u.merchant_id
   ORDER BY u.created_at")

log "done"
