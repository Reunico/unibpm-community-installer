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
KEYCLOAK_HOST_URL="http://${KEYCLOAK_HOST}:${KEYCLOAK_PUBLIC_PORT}${KEYCLOAK_PATH}"

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
