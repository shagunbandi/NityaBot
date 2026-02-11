#!/bin/bash
set -euo pipefail

# deploy-app.sh - Build and deploy an app with Cloudflare DNS + Docker + Traefik
#
# Usage: bash deploy-app.sh <app-name> <internal-port>
#
# Requirements:
#   - Dockerfile must exist in ~/clawbot/apps/<app-name>/
#   - ~/clawbot/config/.env must be configured
#
# What this script does:
#   1. Creates a Cloudflare DNS A record for <app-name>.<CF_BASE_DOMAIN>
#   2. Generates a docker-compose.yml with Traefik labels
#   3. Builds the Docker image
#   4. Starts the container on the openclaw_network
#   5. Verifies the container is running

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOT_DIR="$(dirname "$SCRIPT_DIR")"
ENV_FILE="$CLAWBOT_DIR/config/.env"
LOG_DIR="$CLAWBOT_DIR/shared/logs"

# --- Validation ---

if [ $# -lt 2 ]; then
    echo "FAILURE: Usage: deploy-app.sh <app-name> <port>"
    echo "  app-name: lowercase with hyphens (e.g., sip-calculator)"
    echo "  port: internal port the app listens on (e.g., 80, 3000, 8080)"
    exit 1
fi

APP_NAME="$1"
APP_PORT="$2"

# Validate app name (lowercase, hyphens, numbers only)
if ! echo "$APP_NAME" | grep -qE '^[a-z][a-z0-9-]*$'; then
    echo "FAILURE: App name must be lowercase, start with a letter, and use only letters, numbers, and hyphens"
    echo "  Got: $APP_NAME"
    echo "  Example: sip-calculator, my-blog, analytics"
    exit 1
fi

# Validate port is a number
if ! echo "$APP_PORT" | grep -qE '^[0-9]+$'; then
    echo "FAILURE: Port must be a number. Got: $APP_PORT"
    exit 1
fi

APP_DIR="$CLAWBOT_DIR/apps/$APP_NAME"

if [ ! -d "$APP_DIR" ]; then
    echo "FAILURE: App directory does not exist: $APP_DIR"
    echo "  Create the app source code first, then run this script."
    exit 1
fi

if [ ! -f "$APP_DIR/Dockerfile" ]; then
    echo "FAILURE: No Dockerfile found in $APP_DIR"
    echo "  Create a Dockerfile in the app directory first."
    exit 1
fi

if [ ! -f "$ENV_FILE" ]; then
    echo "FAILURE: Environment file not found: $ENV_FILE"
    echo "  Copy config/.env.example to config/.env and fill in your values."
    exit 1
fi

# --- Load environment ---

source "$ENV_FILE"

for var in CF_API_TOKEN CF_ZONE_ID CF_BASE_DOMAIN; do
    if [ -z "${!var:-}" ]; then
        echo "FAILURE: Required env var $var is not set in $ENV_FILE"
        exit 1
    fi
done

DOCKER_NETWORK="${DOCKER_NETWORK:-openclaw_network}"
TRAEFIK_CERT_RESOLVER="${TRAEFIK_CERT_RESOLVER:-letsencrypt}"
DOMAIN="${APP_NAME}.${CF_BASE_DOMAIN}"

# Ensure log directory exists
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy-${APP_NAME}-$(date +%Y%m%d-%H%M%S).log"

# Log everything
exec > >(tee -a "$LOG_FILE") 2>&1

echo "=== Deploying $APP_NAME ==="
echo "Domain: $DOMAIN"
echo "Port: $APP_PORT"
echo "Time: $(date)"
echo ""

# --- Step 1: Create Cloudflare DNS record ---

echo "--- Step 1: Creating DNS record for $DOMAIN ---"

# Check if a CNAME record already exists
EXISTING_RECORD=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records?type=CNAME&name=${DOMAIN}" \
    -H "Authorization: Bearer ${CF_API_TOKEN}" \
    -H "Content-Type: application/json")

RECORD_COUNT=$(echo "$EXISTING_RECORD" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result_info',{}).get('count',0))" 2>/dev/null || echo "0")

if [ "$RECORD_COUNT" -gt 0 ]; then
    # Update existing record
    RECORD_ID=$(echo "$EXISTING_RECORD" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'][0]['id'])" 2>/dev/null)
    echo "CNAME record exists (ID: $RECORD_ID), updating..."

    DNS_RESULT=$(curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records/${RECORD_ID}" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${APP_NAME}\",\"content\":\"${CF_BASE_DOMAIN}\",\"ttl\":1,\"proxied\":true}")
else
    # Create new record
    echo "Creating new CNAME record..."

    DNS_RESULT=$(curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/${CF_ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_API_TOKEN}" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${APP_NAME}\",\"content\":\"${CF_BASE_DOMAIN}\",\"ttl\":1,\"proxied\":true}")
fi

DNS_SUCCESS=$(echo "$DNS_RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('success', False))" 2>/dev/null || echo "False")

if [ "$DNS_SUCCESS" != "True" ]; then
    echo "WARNING: DNS creation may have failed. Response:"
    echo "$DNS_RESULT" | python3 -m json.tool 2>/dev/null || echo "$DNS_RESULT"
    echo "Continuing with deployment anyway (DNS may already exist)..."
fi

echo "DNS: $DOMAIN → CNAME → $CF_BASE_DOMAIN (proxied via Cloudflare)"
echo ""

# --- Step 2: Generate docker-compose.yml ---

echo "--- Step 2: Generating docker-compose.yml ---"

cat > "$APP_DIR/docker-compose.yml" << COMPOSE_EOF
services:
  ${APP_NAME}:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: openclaw-${APP_NAME}
    restart: unless-stopped
    networks:
      - ${DOCKER_NETWORK}
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.${APP_NAME}.rule=Host(\`${DOMAIN}\`)"
      - "traefik.http.routers.${APP_NAME}.entrypoints=websecure"
      - "traefik.http.routers.${APP_NAME}.tls=true"
      - "traefik.http.routers.${APP_NAME}.tls.certresolver=${TRAEFIK_CERT_RESOLVER}"
      - "traefik.http.services.${APP_NAME}.loadbalancer.server.port=${APP_PORT}"
      - "openclaw.managed=true"
      - "openclaw.app=${APP_NAME}"
      - "openclaw.domain=${DOMAIN}"

networks:
  ${DOCKER_NETWORK}:
    external: true
COMPOSE_EOF

echo "Generated docker-compose.yml"
echo ""

# --- Step 3: Build Docker image ---

echo "--- Step 3: Building Docker image ---"

cd "$APP_DIR"

if ! docker compose build --no-cache 2>&1; then
    echo ""
    echo "FAILURE: Docker build failed for $APP_NAME"
    echo "Check the Dockerfile and source code in $APP_DIR"
    exit 1
fi

echo "Docker image built successfully"
echo ""

# --- Step 4: Start container ---

echo "--- Step 4: Starting container ---"

# Stop existing container if running
docker compose down 2>/dev/null || true

if ! docker compose up -d 2>&1; then
    echo ""
    echo "FAILURE: Failed to start container for $APP_NAME"
    exit 1
fi

echo "Container started"
echo ""

# --- Step 5: Verify ---

echo "--- Step 5: Verifying deployment ---"

sleep 3

CONTAINER_STATUS=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        data = data[0] if data else {}
    print(data.get('State', data.get('state', 'unknown')))
except:
    print('unknown')
" 2>/dev/null || echo "unknown")

if [ "$CONTAINER_STATUS" = "running" ]; then
    echo ""
    echo "========================================="
    echo "SUCCESS: $APP_NAME deployed"
    echo "  URL: https://$DOMAIN"
    echo "  Container: openclaw-$APP_NAME"
    echo "  Port: $APP_PORT"
    echo "  Status: running"
    echo "========================================="
else
    echo ""
    echo "WARNING: Container may not be running properly"
    echo "  Status: $CONTAINER_STATUS"
    echo "  Check logs: bash ~/clawbot/deploy-scripts/logs-app.sh $APP_NAME"
    echo ""
    docker compose logs --tail=20 2>/dev/null || true
    echo ""
    echo "FAILURE: Container is not in 'running' state after deployment"
    exit 1
fi
