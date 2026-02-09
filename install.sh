#!/usr/bin/env bash
set -euo pipefail

echo "▶ UniBPM Community installer (simplified)"

# Load .env
[ -f .env ] || cp .env.example .env
set -o allexport
# shellcheck disable=SC1091
source .env
set +o allexport

# Modes
DEPLOY_MODE=${DEPLOY_MODE:-local}                 # local | edge
EDGE_ROUTING_MODE=${EDGE_ROUTING_MODE:-subdomain} # subdomain | path
ENABLE_TLS=${ENABLE_TLS:-false}
EXPOSE_CAMUNDA=${EXPOSE_CAMUNDA:-false}

# Paths / ports
KEYCLOAK_PATH=${KEYCLOAK_PATH:-/keycloak}
KEYCLOAK_PUBLIC_PORT=${KEYCLOAK_PUBLIC_PORT:-8082}
KEYCLOAK_HTTP_PORT=${KEYCLOAK_HTTP_PORT:-8080}

CAMUNDA_PATH=${CAMUNDA_PATH:-/camunda}

# Domains
UNIBPM_DOMAIN=${UNIBPM_DOMAIN:-unibpm.localhost}
KEYCLOAK_DOMAIN=${KEYCLOAK_DOMAIN:-auth.localhost}
CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-camunda.localhost}

LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}

# Public scheme (browser)
PUBLIC_SCHEME="http"
if [ "$DEPLOY_MODE" = "edge" ] && [ "$ENABLE_TLS" = "true" ]; then
  PUBLIC_SCHEME="https"
fi
export PUBLIC_SCHEME

# Browser-visible Keycloak URL
if [ "$DEPLOY_MODE" = "local" ]; then
  KEYCLOAK_EXTERNAL_URL="http://localhost:${KEYCLOAK_PUBLIC_PORT}${KEYCLOAK_PATH}"
else
  if [ "$EDGE_ROUTING_MODE" = "path" ]; then
    # Single domain, Keycloak under path
    KEYCLOAK_EXTERNAL_URL="${PUBLIC_SCHEME}://${UNIBPM_DOMAIN}${KEYCLOAK_PATH}"
  else
    # Separate domain, Keycloak under path (default)
    KEYCLOAK_EXTERNAL_URL="${PUBLIC_SCHEME}://${KEYCLOAK_DOMAIN}${KEYCLOAK_PATH}"
  fi
fi
export KEYCLOAK_EXTERNAL_URL

# Prepare nginx templates selection
mkdir -p generated/nginx

NGINX_TPL_HTTP=""
NGINX_TPL_TLS=""

if [ "$DEPLOY_MODE" = "local" ]; then
  NGINX_TPL_HTTP="nginx/conf/nginx.local.conf.tpl"
else
  if [ "$EDGE_ROUTING_MODE" = "path" ]; then
    NGINX_TPL_HTTP="nginx/conf/nginx.edge.path.http.conf.tpl"
    NGINX_TPL_TLS="nginx/conf/nginx.edge.path.tls.conf.tpl"
  else
    if [ "$EXPOSE_CAMUNDA" = "true" ]; then
      NGINX_TPL_HTTP="nginx/conf/nginx.edge.subdomain.http.camunda.conf.tpl"
      NGINX_TPL_TLS="nginx/conf/nginx.edge.subdomain.tls.camunda.conf.tpl"
    else
      NGINX_TPL_HTTP="nginx/conf/nginx.edge.subdomain.http.conf.tpl"
      NGINX_TPL_TLS="nginx/conf/nginx.edge.subdomain.tls.conf.tpl"
    fi
  fi
fi

# Compute cert domains (edge only)
CERT_DOMAINS=()
if [ "$DEPLOY_MODE" = "edge" ]; then
  if [ "$EDGE_ROUTING_MODE" = "path" ]; then
    CERT_DOMAINS=("${UNIBPM_DOMAIN}")
  else
    CERT_DOMAINS=("${UNIBPM_DOMAIN}" "${KEYCLOAK_DOMAIN}")
    if [ "$EXPOSE_CAMUNDA" = "true" ]; then
      CERT_DOMAINS+=("${CAMUNDA_DOMAIN}")
    fi
  fi
fi

CERT_PRIMARY_DOMAIN="${UNIBPM_DOMAIN}"
if [ "${#CERT_DOMAINS[@]}" -gt 0 ]; then
  CERT_PRIMARY_DOMAIN="${CERT_DOMAINS[0]}"
fi
export CERT_PRIMARY_DOMAIN

# Export vars used by templates
export UNIBPM_DOMAIN KEYCLOAK_DOMAIN CAMUNDA_DOMAIN
export KEYCLOAK_PATH KEYCLOAK_HTTP_PORT
export CAMUNDA_PATH

render_nginx() {
  local tpl="$1"
  envsubst '${UNIBPM_DOMAIN} ${KEYCLOAK_DOMAIN} ${CAMUNDA_DOMAIN} ${KEYCLOAK_HTTP_PORT} ${KEYCLOAK_PATH} ${CAMUNDA_PATH} ${CERT_PRIMARY_DOMAIN}' \
    < "$tpl" > generated/nginx/default.conf
}

echo "🐳 Starting infra (postgres, kafka, keycloak)"
docker compose up -d postgres kafka keycloak

echo "🧩 Running prepare.sh"
./prepare.sh

echo "🐳 Starting app (unibpm, camunda, frontend)"
docker compose up -d unibpm camunda-bpm-7 unibpm-frontend

# Edge: start nginx (2-phase if TLS enabled)
if [ "$DEPLOY_MODE" = "edge" ]; then
  # Phase 1: HTTP config (always, to allow ACME http-01)
  echo "🌐 Rendering nginx HTTP config"
  render_nginx "$NGINX_TPL_HTTP"

  echo "🐳 Starting nginx (HTTP)"
  docker compose up -d nginx

  # Phase 2: TLS issuance + switch to TLS config
  if [ "$ENABLE_TLS" = "true" ]; then
    if [ -z "$LETSENCRYPT_EMAIL" ]; then
      echo "❌ ENABLE_TLS=true требует LETSENCRYPT_EMAIL"
      exit 1
    fi

    mkdir -p letsencrypt/www letsencrypt/conf

    if [ ! -f "letsencrypt/conf/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem" ]; then
      echo "🔐 Issuing Let's Encrypt certificate for: ${CERT_DOMAINS[*]}"
      ARGS=(certonly --webroot -w /var/www/certbot --email "${LETSENCRYPT_EMAIL}" --agree-tos --no-eff-email)
      for d in "${CERT_DOMAINS[@]}"; do ARGS+=(-d "$d"); done
      docker compose run --rm certbot "${ARGS[@]}"
    else
      echo "🔐 Certificate already exists, skipping issuance"
    fi

    echo "🔒 Rendering nginx TLS config"
    render_nginx "$NGINX_TPL_TLS"

    echo "🐳 Restarting nginx (TLS)"
    docker compose restart nginx
  fi
fi

echo ""
echo "✅ Installed."
if [ "$DEPLOY_MODE" = "local" ]; then
  echo "UniBPM UI      : http://localhost:${FRONT_PUBLIC_PORT:-8080}/"
  echo "Keycloak       : http://localhost:${KEYCLOAK_PUBLIC_PORT:-8082}${KEYCLOAK_PATH}/"
  echo "Camunda        : http://localhost:${CAMUNDA_PUBLIC_PORT:-8081}/"
else
  if [ "$EDGE_ROUTING_MODE" = "path" ]; then
    echo "UniBPM         : ${PUBLIC_SCHEME}://${UNIBPM_DOMAIN}/"
    echo "Keycloak       : ${PUBLIC_SCHEME}://${UNIBPM_DOMAIN}${KEYCLOAK_PATH}/"
    if [ "$EXPOSE_CAMUNDA" = "true" ]; then
      echo "Camunda        : ${PUBLIC_SCHEME}://${UNIBPM_DOMAIN}${CAMUNDA_PATH}/"
    else
      echo "Camunda        : internal only"
    fi
  else
    echo "UniBPM         : ${PUBLIC_SCHEME}://${UNIBPM_DOMAIN}/"
    echo "Keycloak       : ${PUBLIC_SCHEME}://${KEYCLOAK_DOMAIN}${KEYCLOAK_PATH}/"
    if [ "$EXPOSE_CAMUNDA" = "true" ]; then
      echo "Camunda        : ${PUBLIC_SCHEME}://${CAMUNDA_DOMAIN}/"
    else
      echo "Camunda        : internal only"
    fi
  fi
fi
