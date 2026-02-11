#!/bin/bash
# check-prereqs.sh - Verify all required tools and config are present

echo "--- Checking prerequisites ---"
echo ""

MISSING=0

# Check Docker
if command -v docker &> /dev/null; then
    DOCKER_VERSION=$(docker --version 2>/dev/null || echo "unknown")
    echo "[OK] Docker: $DOCKER_VERSION"
else
    echo "[MISSING] Docker is not installed"
    echo "  Install: https://docs.docker.com/engine/install/"
    MISSING=1
fi

# Check docker compose (v2 or v1)
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    echo "[OK] Docker Compose v2: $COMPOSE_VERSION"
elif command -v docker-compose &> /dev/null; then
    COMPOSE_VERSION=$(docker-compose --version 2>/dev/null || echo "unknown")
    echo "[OK] Docker Compose v1: $COMPOSE_VERSION"
else
    echo "[MISSING] Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
    echo "  Install: sudo apt install docker-compose-plugin"
    MISSING=1
fi

# Check jq
if command -v jq &> /dev/null; then
    echo "[OK] jq: $(jq --version 2>/dev/null)"
else
    echo "[MISSING] jq is not installed"
    echo "  Install: sudo apt install jq"
    MISSING=1
fi

# Check git
if command -v git &> /dev/null; then
    echo "[OK] git: $(git --version 2>/dev/null)"
else
    echo "[MISSING] git is not installed"
    echo "  Install: sudo apt install git"
    MISSING=1
fi

echo ""

# Check if Traefik is running
TRAEFIK_RUNNING=$(docker ps --filter "name=traefik" --format "{{.Names}}" 2>/dev/null || echo "")
if [ -n "$TRAEFIK_RUNNING" ]; then
    echo "[OK] Traefik container is running: $TRAEFIK_RUNNING"
else
    echo "[WARNING] No Traefik container detected"
    echo "  Traefik must be running for HTTPS routing to work."
    echo "  If it's running with a different name, that's fine - continuing."
fi

echo ""

if [ "$MISSING" -eq 1 ]; then
    echo "Please install the missing prerequisites and re-run this script."
    exit 1
fi

# Check .env file
if [ ! -f "$SCRIPT_DIR/deployer-workspace/config/.env" ]; then
    echo "[MISSING] deployer-workspace/config/.env not found"
    echo ""
    echo "  Create it now:"
    echo "    cp deployer-workspace/config/.env.example deployer-workspace/config/.env"
    echo "    nano deployer-workspace/config/.env"
    echo ""
    echo "  Then re-run this script."
    exit 1
fi

echo "[OK] deployer-workspace/config/.env exists"
echo ""
