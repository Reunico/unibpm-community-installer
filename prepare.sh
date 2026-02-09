#!/usr/bin/env bash
set -euo pipefail

echo "▶ prepare.sh: configuration generation started"

# --------------------------------------------------
# Environment
# --------------------------------------------------
if [ ! -f .env ]; then
  echo "❌ .env not found. Run: cp .env.example .env"
  exit 1
fi

set -o allexport
# shellcheck disable=SC1091
source .env
set +o allexport

# --------------------------------------------------
# Helpers
# --------------------------------------------------
require_bin() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "❌ Required binary '$1' not found. Install it on the host."
    exit 1
  fi
}

require_var() {
  if [ -z "${!1:-}" ]; then
    echo "❌ Required variable $1 is not set"
    exit 1
  fi
}

wait_for_url() {
  local URL="$1"
  local NAME="$2"
  local ATTEMPTS=0

  echo "⏳ Waiting for ${NAME}..."

  until curl -sf "$URL" >/dev/null; do
    sleep 3
    ATTEMPTS=$((ATTEMPTS + 1))
    if [ "$ATTEMPTS" -ge 60 ]; then
      echo "❌ Timeout while waiting for ${NAME}"
      exit 1
    fi
  done

  echo "✔ ${NAME} is ready"
}

# --------------------------------------------------
# Preconditions
# --------------------------------------------------
require_bin curl
require_bin jq
require_bin envsubst

# --------------------------------------------------
# Defaults (out-of-the-box)
# --------------------------------------------------
DEPLOY_MODE=${DEPLOY_MODE:-local}
ENABLE_TLS=${ENABLE_TLS:-false}

# PUBLIC_SCHEME and KEYCLOAK_EXTERNAL_URL must be exported by install.sh

KEYCLOAK_HTTP_PORT=${KEYCLOAK_HTTP_PORT:-8080}
KEYCLOAK_PATH=${KEYCLOAK_PATH:-/keycloak}
KEYCLOAK_PUBLIC_PORT=${KEYCLOAK_PUBLIC_PORT:-8082}
KEYCLOAK_HOST=${KEYCLOAK_HOST:-localhost}

# Client IDs must match realm-unibpm.json
UNIBPM_CLIENT_ID=${UNIBPM_CLIENT_ID:-unibpm-app}
UNIBPM_FRONT_CLIENT_ID=${UNIBPM_FRONT_CLIENT_ID:-unibpm-front}
CAMUNDA_CLIENT_ID=${CAMUNDA_CLIENT_ID:-camunda-identity-service}

# Datasources
UNIBPM_DATASOURCE_URL=${UNIBPM_DATASOURCE_URL:-jdbc:postgresql://postgres:5432/unibpm}
UNIBPM_DATASOURCE_USERNAME=${UNIBPM_DATASOURCE_USERNAME:-unibpm}
UNIBPM_DATASOURCE_PASSWORD=${UNIBPM_DATASOURCE_PASSWORD:-unibpm}

CAMUNDA_DATASOURCE_URL=${CAMUNDA_DATASOURCE_URL:-jdbc:postgresql://postgres:5432/camunda}
CAMUNDA_DATASOURCE_USERNAME=${CAMUNDA_DATASOURCE_USERNAME:-camunda}
CAMUNDA_DATASOURCE_PASSWORD=${CAMUNDA_DATASOURCE_PASSWORD:-camunda}

# Kafka
KAFKA_BOOTSTRAP_SERVERS=${KAFKA_BOOTSTRAP_SERVERS:-kafka:29092}

# Camunda app
CAMUNDA_CONTEXT_PATH=${CAMUNDA_CONTEXT_PATH:-/camunda}
CAMUNDA_LOGIN=${CAMUNDA_LOGIN:-demo}
CAMUNDA_PASSWORD=${CAMUNDA_PASSWORD:-demo}
CAMUNDA_REST_API_URL=${CAMUNDA_REST_API_URL:-http://camunda-bpm-7:8080/engine-rest}

# Keycloak identity
KEYCLOAK_REALM=${KEYCLOAK_REALM:-unibpm}
KEYCLOAK_BASE_URL=${KEYCLOAK_BASE_URL:-http://keycloak:8080/keycloak}
KEYCLOAK_ADMIN=${KEYCLOAK_ADMIN:-admin}
KEYCLOAK_ADMIN_PASSWORD=${KEYCLOAK_ADMIN_PASSWORD:-admin}

export DEPLOY_MODE ENABLE_TLS KEYCLOAK_HTTP_PORT KEYCLOAK_PATH KEYCLOAK_PUBLIC_PORT KEYCLOAK_HOST
export UNIBPM_CLIENT_ID UNIBPM_FRONT_CLIENT_ID CAMUNDA_CLIENT_ID
export UNIBPM_DATASOURCE_URL UNIBPM_DATASOURCE_USERNAME UNIBPM_DATASOURCE_PASSWORD
export CAMUNDA_DATASOURCE_URL CAMUNDA_DATASOURCE_USERNAME CAMUNDA_DATASOURCE_PASSWORD
export KAFKA_BOOTSTRAP_SERVERS CAMUNDA_CONTEXT_PATH CAMUNDA_LOGIN CAMUNDA_PASSWORD CAMUNDA_REST_API_URL
export KEYCLOAK_REALM KEYCLOAK_BASE_URL KEYCLOAK_ADMIN KEYCLOAK_ADMIN_PASSWORD

# Keycloak external URL (browser) must be provided by install.sh
require_var KEYCLOAK_EXTERNAL_URL


# --------------------------------------------------
# Keycloak: wait for realm and fetch client secrets
# --------------------------------------------------
KEYCLOAK_HOST_URL="${KEYCLOAK_BASE_URL%/}"

wait_for_url "${KEYCLOAK_HOST_URL}/realms/${KEYCLOAK_REALM}" "Keycloak realm '${KEYCLOAK_REALM}'"

echo "▶ Obtaining Keycloak admin token"
TOKEN=$(curl -sf -X POST   "${KEYCLOAK_HOST_URL}/realms/master/protocol/openid-connect/token"   -d grant_type=password   -d client_id=admin-cli   -d username="${KEYCLOAK_ADMIN}"   -d password="${KEYCLOAK_ADMIN_PASSWORD}" | jq -r .access_token)

if [ -z "${TOKEN:-}" ] || [ "$TOKEN" = "null" ]; then
  echo "❌ Failed to obtain Keycloak admin token"
  exit 1
fi
echo "✔ Admin token obtained"

get_client_secret() {
  local CLIENT_ID_NAME="$1"

  CLIENT_JSON=$(curl -sf -H "Authorization: Bearer $TOKEN"     "${KEYCLOAK_HOST_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${CLIENT_ID_NAME}")

  CLIENT_UUID=$(echo "$CLIENT_JSON" | jq -r '.[0].id')
  if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" = "null" ]; then
    echo "❌ Client $CLIENT_ID_NAME not found in realm ${KEYCLOAK_REALM}"
    exit 1
  fi

  SECRET=$(curl -sf -H "Authorization: Bearer $TOKEN"     "${KEYCLOAK_HOST_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${CLIENT_UUID}/client-secret"     | jq -r .value)

  if [ -z "$SECRET" ] || [ "$SECRET" = "null" ]; then
    echo "❌ Failed to fetch secret for client $CLIENT_ID_NAME"
    exit 1
  fi

  echo "$SECRET"
}

EDGE_ROUTING_MODE=${EDGE_ROUTING_MODE:-subdomain}
UNIBPM_DOMAIN=${UNIBPM_DOMAIN:-unibpm.localhost}
KEYCLOAK_DOMAIN=${KEYCLOAK_DOMAIN:-auth.localhost}
CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-camunda.localhost}
CAMUNDA_PATH=${CAMUNDA_PATH:-/camunda}
KEYCLOAK_PATH=${KEYCLOAK_PATH:-/keycloak}

get_client_uuid() {
  local CLIENT_ID_NAME="$1"
  local CLIENT_JSON
  CLIENT_JSON=$(curl -sf -H "Authorization: Bearer $TOKEN" \
    "${KEYCLOAK_HOST_URL}/admin/realms/${KEYCLOAK_REALM}/clients?clientId=${CLIENT_ID_NAME}")
  echo "$CLIENT_JSON" | jq -r '.[0].id'
}

update_client_redirects() {
  local CLIENT_ID_NAME="$1"
  local REDIRECTS_JSON="$2"
  local ORIGINS_JSON="$3"

  local CLIENT_UUID
  CLIENT_UUID=$(get_client_uuid "$CLIENT_ID_NAME")
  if [ -z "$CLIENT_UUID" ] || [ "$CLIENT_UUID" = "null" ]; then
    echo "❌ Client $CLIENT_ID_NAME not found in realm ${KEYCLOAK_REALM}"
    exit 1
  fi

  local CLIENT_REP UPDATED
  CLIENT_REP=$(curl -sf -H "Authorization: Bearer $TOKEN" \
    "${KEYCLOAK_HOST_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${CLIENT_UUID}")

  UPDATED=$(echo "$CLIENT_REP" | jq \
    --argjson redirects "$REDIRECTS_JSON" \
    --argjson origins "$ORIGINS_JSON" \
    '.redirectUris=$redirects | .webOrigins=$origins')

  curl -sf -X PUT \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    "${KEYCLOAK_HOST_URL}/admin/realms/${KEYCLOAK_REALM}/clients/${CLIENT_UUID}" \
    -d "$UPDATED" >/dev/null

  echo "✔ Updated redirectUris/webOrigins for client: $CLIENT_ID_NAME"
}

if [ "${DEPLOY_MODE:-local}" = "edge" ]; then
  SCHEME="http"
  if [ "${ENABLE_TLS:-false}" = "true" ]; then SCHEME="https"; fi

  UI_BASE="${SCHEME}://${UNIBPM_DOMAIN}"

  REDIRECTS=$(jq -nc --arg ui "${UI_BASE}" \
    '[($ui + "/*"), "https://oauth.pstmn.io/v1/callback"]')
  ORIGINS=$(jq -nc --arg ui "${UI_BASE}" '[ $ui ]')

  echo "▶ EDGE: updating redirectUris for '${UNIBPM_FRONT_CLIENT_ID}' => ${UI_BASE}/*"
  update_client_redirects "${UNIBPM_FRONT_CLIENT_ID}" "$REDIRECTS" "$ORIGINS"

  if [ "${EDGE_ROUTING_MODE}" = "path" ] && [ "${EXPOSE_CAMUNDA:-false}" = "true" ]; then
    CAM_REDIRECTS=$(jq -nc --arg ui "${UI_BASE}" --arg p "${CAMUNDA_PATH}" \
      '[($ui + $p + "/*")]')
    CAM_ORIGINS=$(jq -nc --arg ui "${UI_BASE}" '[ $ui ]')
    echo "▶ EDGE(path): updating redirectUris for '${CAMUNDA_CLIENT_ID}' => ${UI_BASE}${CAMUNDA_PATH}/*"
    update_client_redirects "${CAMUNDA_CLIENT_ID}" "$CAM_REDIRECTS" "$CAM_ORIGINS"
  fi
else
  echo "▶ LOCAL: skipping redirectUris update (not needed)"
fi

echo "▶ Fetching client secrets from Keycloak"
UNIBPM_CLIENT_SECRET=$(get_client_secret "$UNIBPM_CLIENT_ID")
CAMUNDA_CLIENT_SECRET=$(get_client_secret "$CAMUNDA_CLIENT_ID")
export UNIBPM_CLIENT_SECRET CAMUNDA_CLIENT_SECRET
echo "✔ Client secrets obtained"

# --------------------------------------------------
# Generate application configs
# --------------------------------------------------
echo "▶ Generating application configuration files"

mkdir -p generated/unibpm generated/camunda
rm -f generated/unibpm/application.yaml generated/camunda/application.yml

envsubst < config-templates/uni.yaml > generated/unibpm/application.yaml
envsubst < config-templates/camunda.yaml > generated/camunda/application.yml

echo "✔ Configuration files generated"
echo "▶ prepare.sh finished successfully"
