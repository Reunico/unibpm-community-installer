#!/usr/bin/env bash
set -euo pipefail

echo "▶ UniBPM Community installer (simplified)"

[ -f .env ] || cp .env.example .env
set -o allexport
# shellcheck disable=SC1091
source .env
set +o allexport

DEPLOY_MODE=${DEPLOY_MODE:-local}   # local | edge
ENABLE_TLS=${ENABLE_TLS:-false}
EXPOSE_CAMUNDA=${EXPOSE_CAMUNDA:-false}

KEYCLOAK_PATH=${KEYCLOAK_PATH:-/keycloak}
KEYCLOAK_PUBLIC_PORT=${KEYCLOAK_PUBLIC_PORT:-8082}

UNIBPM_DOMAIN=${UNIBPM_DOMAIN:-unibpm.localhost}
KEYCLOAK_DOMAIN=${KEYCLOAK_DOMAIN:-auth.localhost}
CAMUNDA_DOMAIN=${CAMUNDA_DOMAIN:-camunda.localhost}

LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL:-}

PUBLIC_SCHEME="http"
if [ "$DEPLOY_MODE" = "edge" ] && [ "$ENABLE_TLS" = "true" ]; then
  PUBLIC_SCHEME="https"
fi
export PUBLIC_SCHEME

# Browser-visible Keycloak URL
if [ "$DEPLOY_MODE" = "local" ]; then
  KEYCLOAK_EXTERNAL_URL="http://localhost:${KEYCLOAK_PUBLIC_PORT}${KEYCLOAK_PATH}"
else
  KEYCLOAK_EXTERNAL_URL="${PUBLIC_SCHEME}://${KEYCLOAK_DOMAIN}${KEYCLOAK_PATH}"
fi
export KEYCLOAK_EXTERNAL_URL

# Nginx config
mkdir -p generated/nginx
CERT_PRIMARY_DOMAIN="${UNIBPM_DOMAIN}"
export CERT_PRIMARY_DOMAIN

if [ "$DEPLOY_MODE" = "edge" ]; then
  if [ "$ENABLE_TLS" = "true" ]; then
    if [ "$EXPOSE_CAMUNDA" = "true" ]; then
      NGINX_TPL="nginx/conf/nginx.edge.subdomain.tls.camunda.conf.tpl"
    else
      NGINX_TPL="nginx/conf/nginx.edge.subdomain.tls.conf.tpl"
    fi
  else
    if [ "$EXPOSE_CAMUNDA" = "true" ]; then
      NGINX_TPL="nginx/conf/nginx.edge.subdomain.http.camunda.conf.tpl"
    else
      NGINX_TPL="nginx/conf/nginx.edge.subdomain.http.conf.tpl"
    fi
  fi
else
  NGINX_TPL="nginx/conf/nginx.local.conf.tpl"
fi

envsubst '${UNIBPM_DOMAIN} ${KEYCLOAK_DOMAIN} ${CAMUNDA_DOMAIN} ${KEYCLOAK_HTTP_PORT} ${KEYCLOAK_PATH} ${CERT_PRIMARY_DOMAIN}' < "$NGINX_TPL" > generated/nginx/default.conf

echo "🐳 Starting infra (postgres, kafka, keycloak)"
docker compose up -d postgres kafka keycloak

echo "🧩 Running prepare.sh"
./prepare.sh

echo "🐳 Starting app (unibpm, camunda, frontend)"
docker compose up -d unibpm camunda-bpm-7 unibpm-frontend

# TLS issuance (edge only)
if [ "$DEPLOY_MODE" = "edge" ] && [ "$ENABLE_TLS" = "true" ]; then
  if [ -z "$LETSENCRYPT_EMAIL" ]; then
    echo "❌ ENABLE_TLS=true требует LETSENCRYPT_EMAIL"
    exit 1
  fi

  mkdir -p letsencrypt/www letsencrypt/conf

  CERT_DOMAINS=("${UNIBPM_DOMAIN}" "${KEYCLOAK_DOMAIN}")
  if [ "$EXPOSE_CAMUNDA" = "true" ]; then
    CERT_DOMAINS+=("${CAMUNDA_DOMAIN}")
  fi


  CERT_PRIMARY_DOMAIN="${CERT_DOMAINS[0]}"

  echo "🐳 Starting nginx for ACME challenge"
  docker compose up -d nginx

  if [ ! -f "letsencrypt/conf/live/${CERT_PRIMARY_DOMAIN}/fullchain.pem" ]; then
    echo "🔐 Issuing Let's Encrypt certificate for: ${CERT_DOMAINS[*]}"
    ARGS=(certonly --webroot -w /var/www/certbot --email "${LETSENCRYPT_EMAIL}" --agree-tos --no-eff-email)
    for d in "${CERT_DOMAINS[@]}"; do ARGS+=(-d "$d"); done
    docker compose run --rm certbot "${ARGS[@]}"
    docker compose restart nginx
  else
    echo "🔐 Certificate already exists, skipping issuance"
  fi
fi

if [ "$DEPLOY_MODE" = "edge" ]; then
  docker compose up -d nginx
fi

echo ""
echo "✅ Installed."
if [ "$DEPLOY_MODE" = "local" ]; then
  echo "UniBPM UI      : http://localhost:${FRONT_PUBLIC_PORT:-8080}/"
  echo "Keycloak       : http://localhost:${KEYCLOAK_PUBLIC_PORT:-8082}${KEYCLOAK_PATH}/"
  echo "Camunda        : http://localhost:${CAMUNDA_PUBLIC_PORT:-8081}/"
else
  echo "UniBPM         : ${PUBLIC_SCHEME}://${UNIBPM_DOMAIN}/"
  echo "Keycloak       : ${PUBLIC_SCHEME}://${KEYCLOAK_DOMAIN}${KEYCLOAK_PATH}/"
  if [ "$EXPOSE_CAMUNDA" = "true" ]; then
    echo "Camunda        : ${PUBLIC_SCHEME}://${CAMUNDA_DOMAIN}/"
  else
    echo "Camunda        : internal only"
  fi
fi
