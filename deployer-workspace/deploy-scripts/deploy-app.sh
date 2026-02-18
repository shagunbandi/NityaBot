#!/bin/bash
set -euo pipefail

# deploy-app.sh - Build and deploy an app with Cloudflare DNS + Docker + Traefik
#
# Usage: bash deploy-app.sh <app-name> <internal-port> [basic_auth]
#
# Optional: 3rd argument "basic_auth" (or "secure") enables Traefik HTTP Basic Auth.
# Alternatively, if the app directory contains a file named .secure-deploy, basic auth
# is enabled automatically. Requires BASIC_AUTH_USER and BASIC_AUTH_PASS in config/.env.
#
# Requirements:
#   - Dockerfile must exist in $WORKSPACE_DIR/apps/<app-name>/
#   - $WORKSPACE_DIR/config/.env must be configured
#   - jq, curl, docker-compose must be available
#
# What this script does:
#   1. Creates a Cloudflare DNS CNAME record for <app-name>.<CF_BASE_DOMAIN>
#   2. Generates a docker-compose.yml with Traefik labels
#   3. Builds the Docker image
#   4. Starts the container on the Docker network
#   5. Verifies the container is running

# --- Helpers ---

die() { echo "FAILURE: $*" >&2; exit 1; }

# --- Paths ---

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
ENV_FILE="$WORKSPACE_DIR/config/.env"
APPS_DIR="$WORKSPACE_DIR/apps"
LOG_DIR="$WORKSPACE_DIR/shared/logs"

# --- Detect docker-compose ---

if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    die "Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
fi

# --- Validation ---

[ $# -ge 2 ] || die "Usage: deploy-app.sh <app-name> <port> [basic_auth]
  app-name: lowercase with hyphens (e.g., sip-calculator)
  port: internal port the app listens on (e.g., 80, 3000, 8080)
  basic_auth: optional, use 'basic_auth' or 'secure' to enable Traefik Basic Auth"

APP_NAME="$1"
APP_PORT="$2"
USE_BASIC_AUTH=false
if [ -n "${3:-}" ]; then
  case "$3" in
    basic_auth|secure) USE_BASIC_AUTH=true ;;
  esac
fi
# Also enable basic auth if app has .secure-deploy marker
[ -f "$APPS_DIR/$APP_NAME/.secure-deploy" ] && USE_BASIC_AUTH=true

echo "$APP_NAME" | grep -qE '^[a-z][a-z0-9-]*$' \
    || die "App name must be lowercase, start with a letter, use only letters/numbers/hyphens. Got: $APP_NAME"

echo "$APP_PORT" | grep -qE '^[0-9]+$' \
    || die "Port must be a number. Got: $APP_PORT"

APP_DIR="$APPS_DIR/$APP_NAME"

[ -d "$APP_DIR" ]              || die "App directory does not exist: $APP_DIR"
[ -f "$APP_DIR/Dockerfile" ]   || die "No Dockerfile found in $APP_DIR"
[ -f "$ENV_FILE" ]             || die "Environment file not found: $ENV_FILE"

# --- Load environment ---

# shellcheck source=/dev/null
source "$ENV_FILE"

[ -n "${CF_API_TOKEN:-}" ]    || die "CF_API_TOKEN is not set in $ENV_FILE"
[ -n "${CF_BASE_DOMAIN:-}" ]  || die "CF_BASE_DOMAIN is not set in $ENV_FILE"

if [ "$USE_BASIC_AUTH" = true ]; then
  if [ -n "${BASIC_AUTH_HASH:-}" ]; then
    # Pre-computed hash from deployer (Python bcrypt) — escape $ for docker-compose
    BASIC_AUTH_HASH=$(echo "$BASIC_AUTH_HASH" | sed 's/\$/\$\$/g')
    echo "Basic auth enabled for $APP_NAME (hash from deployer)"
  else
    [ -n "${BASIC_AUTH_USER:-}" ] || die "BASIC_AUTH_USER is not set in $ENV_FILE (required for basic_auth deploy)"
    [ -n "${BASIC_AUTH_PASS:-}" ] || die "BASIC_AUTH_PASS is not set in $ENV_FILE (required for basic_auth deploy)"
    if command -v htpasswd &>/dev/null; then
      BASIC_AUTH_HASH=$(htpasswd -nbB "$BASIC_AUTH_USER" "$BASIC_AUTH_PASS" | sed 's/\$/\$\$/g')
    else
      die "htpasswd not found and BASIC_AUTH_HASH not provided. Set BASIC_AUTH_USER and BASIC_AUTH_PASS in config/.env and use POST /deploy-secure (generates hash in deployer), or install apache2-utils in deployer image."
    fi
    echo "Basic auth enabled for $APP_NAME (user: $BASIC_AUTH_USER)"
  fi
fi

DOCKER_NETWORK="${DOCKER_NETWORK:-openclaw_network}"
TRAEFIK_CERTRESOLVER="${TRAEFIK_CERTRESOLVER:-letsencrypt}"
ALLOWED_ZONE_SUFFIX="${ALLOWED_ZONE_SUFFIX:-$CF_BASE_DOMAIN}"

# Shared DB connection (for injection into app containers on openclaw_network)
POSTGRES_HOST="${POSTGRES_HOST:-postgres}"
POSTGRES_PORT="${POSTGRES_PORT:-5432}"
POSTGRES_USER="${POSTGRES_USER:-openclaw}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-openclaw}"
POSTGRES_DB="${POSTGRES_DB:-openclaw}"
MONGODB_URI="${MONGODB_URI:-mongodb://mongodb:27017}"
GOOGLE_PLACES_API_KEY="${GOOGLE_PLACES_API_KEY:-}"

DOMAIN="${APP_NAME}.${CF_BASE_DOMAIN}"

# --- Validate domain suffix ---

case "$DOMAIN" in
    *".$ALLOWED_ZONE_SUFFIX") ;;
    *)  die "Domain $DOMAIN is not under allowed zone suffix .$ALLOWED_ZONE_SUFFIX" ;;
esac

# --- Logging ---

mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-${APP_NAME}-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Deploying $APP_NAME ==="
echo "Domain: $DOMAIN"
echo "Port: $APP_PORT"
echo "Time: $(date)"
echo ""

# --- Step 1: Create Cloudflare DNS record ---

echo "--- Step 1: Creating DNS record for $DOMAIN ---"

# Look up Zone ID
echo "Looking up Zone ID for $CF_BASE_DOMAIN..."
ZONE_RESPONSE=$(curl -sf -X GET \
    "https://api.cloudflare.com/client/v4/zones?name=${CF_BASE_DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json") \
    || die "Failed to query Cloudflare zones API"

CF_ZONE_ID=$(echo "$ZONE_RESPONSE" | jq -r '.result[0].id // empty') \
    || die "Failed to parse zone ID from Cloudflare response"

[ -n "$CF_ZONE_ID" ] || die "Could not find Cloudflare Zone ID for $CF_BASE_DOMAIN
  Make sure CF_API_TOKEN has Zone.Zone (Read) permission
  and CF_BASE_DOMAIN matches your Cloudflare domain exactly."

echo "Zone ID: $CF_ZONE_ID"

# Check if CNAME record already exists
EXISTING_RECORD=$(curl -sf -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=CNAME&name=${DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json") \
    || die "Failed to query existing DNS records"

RECORD_COUNT=$(echo "$EXISTING_RECORD" | jq -r '.result_info.count // 0')

if [ "$RECORD_COUNT" -gt 0 ]; then
    # Update existing record
    RECORD_ID=$(echo "$EXISTING_RECORD" | jq -r '.result[0].id')
    echo "CNAME record exists (ID: $RECORD_ID), updating..."

    DNS_RESULT=$(curl -sf -X PUT \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${APP_NAME}\",\"content\":\"${CF_BASE_DOMAIN}\",\"ttl\":1,\"proxied\":true}") \
        || die "Failed to update DNS record"
else
    # Create new record
    echo "Creating new CNAME record..."

    DNS_RESULT=$(curl -sf -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${APP_NAME}\",\"content\":\"${CF_BASE_DOMAIN}\",\"ttl\":1,\"proxied\":true}") \
        || die "Failed to create DNS record"
fi

DNS_SUCCESS=$(echo "$DNS_RESULT" | jq -r '.success')

if [ "$DNS_SUCCESS" != "true" ]; then
    echo "WARNING: DNS creation may have failed. Response:"
    echo "$DNS_RESULT" | jq . 2>/dev/null || echo "$DNS_RESULT"
    echo "Continuing with deployment anyway (DNS may already exist)..."
fi

echo "DNS: $DOMAIN -> CNAME -> $CF_BASE_DOMAIN (proxied via Cloudflare)"
echo ""

# --- Step 2: Generate docker-compose.yml ---

echo "--- Step 2: Generating docker-compose.yml ---"

# Build Traefik labels (optional basic auth middleware)
ROUTER_LABELS="
      - \"traefik.enable=true\"
      - \"traefik.http.routers.${APP_NAME}.rule=Host(\`${DOMAIN}\`)\"
      - \"traefik.http.routers.${APP_NAME}.entrypoints=websecure\"
      - \"traefik.http.routers.${APP_NAME}.tls=true\"
      - \"traefik.http.routers.${APP_NAME}.tls.certresolver=${TRAEFIK_CERTRESOLVER}\"
      - \"traefik.http.services.${APP_NAME}.loadbalancer.server.port=${APP_PORT}\"
      - \"openclaw.managed=true\"
      - \"openclaw.app=${APP_NAME}\"
      - \"openclaw.domain=${DOMAIN}\""
if [ "$USE_BASIC_AUTH" = true ]; then
  MIDDLEWARE_NAME="${APP_NAME}-basicauth"
  ROUTER_LABELS="$ROUTER_LABELS
      - \"traefik.http.middlewares.${MIDDLEWARE_NAME}.basicauth.users=${BASIC_AUTH_HASH}\"
      - \"traefik.http.routers.${APP_NAME}.middlewares=${MIDDLEWARE_NAME}@docker\""
fi

cat > "$APP_DIR/docker-compose.yml" << COMPOSE_EOF
services:
  ${APP_NAME}:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: openclaw-${APP_NAME}
    restart: unless-stopped
    environment:
      - "POSTGRES_HOST=${POSTGRES_HOST}"
      - "POSTGRES_PORT=${POSTGRES_PORT}"
      - "POSTGRES_USER=${POSTGRES_USER}"
      - "POSTGRES_PASSWORD=${POSTGRES_PASSWORD}"
      - "POSTGRES_DB=${POSTGRES_DB}"
      - "MONGODB_URI=${MONGODB_URI}"
      - "GOOGLE_PLACES_API_KEY=${GOOGLE_PLACES_API_KEY}"
    networks:
      - ${DOCKER_NETWORK}
    labels:${ROUTER_LABELS}

networks:
  ${DOCKER_NETWORK}:
    external: true
COMPOSE_EOF

echo "Generated docker-compose.yml"
echo ""

# --- Step 3: Build Docker image ---

echo "--- Step 3: Building Docker image ---"

cd "$APP_DIR"

$DC build --no-cache 2>&1 \
    || die "Docker build failed for $APP_NAME. Check the Dockerfile and source code in $APP_DIR"

echo "Docker image built successfully"
echo ""

# --- Step 4: Start container ---

echo "--- Step 4: Starting container ---"

# Stop existing container if running
$DC down 2>/dev/null || true

$DC up -d 2>&1 \
    || die "Failed to start container for $APP_NAME"

echo "Container started"
echo ""

# --- Step 5: Verify ---

echo "--- Step 5: Verifying deployment ---"

sleep 3

if $DC ps 2>/dev/null | grep "openclaw-${APP_NAME}" | grep -q "Up"; then
    echo ""
    echo "========================================="
    echo "SUCCESS: $APP_NAME deployed"
    echo "  URL: https://$DOMAIN"
    echo "  Container: openclaw-$APP_NAME"
    echo "  Port: $APP_PORT"
    [ "$USE_BASIC_AUTH" = true ] && echo "  Basic auth: enabled (Traefik)"
    echo "  Status: running"
    echo "========================================="
else
    echo ""
    echo "WARNING: Container may not be running properly"
    $DC logs --tail=20 2>/dev/null || true
    die "Container is not in 'running' state after deployment"
fi
