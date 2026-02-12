#!/bin/bash
# start.sh - Start OpenClaw gateway + deployer and print completion summary

echo "--- Starting OpenClaw gateway + deployer ---"
echo ""

# Detect docker-compose
if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    echo "ERROR: Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
    exit 1
fi

cd "$SCRIPT_DIR"
$DC up -d openclaw-gateway deployer 2>&1

# shellcheck source=/dev/null
source "$SCRIPT_DIR/deployer-workspace/config/.env"
DOCKER_NETWORK="${DOCKER_NETWORK:-openclaw_network}"
OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  OpenClaw is running in Docker."
echo "  Deployer sidecar is running alongside it."
echo ""
echo "  Architecture:"
echo "    - OpenClaw (no Docker access) writes code to apps/"
echo "    - Deployer sidecar (Docker access) handles deployments"
echo "    - OpenClaw calls deployer via HTTP on the internal network"
echo ""
echo "  Config:"
echo "    - Opus (claude-opus-4-6) as primary model"
echo "    - Haiku (claude-haiku-3-5) for sub-agents"
echo "    - Workspace mounted from: $SCRIPT_DIR"
echo "    - Docker network: $DOCKER_NETWORK"
echo ""
echo "  Next steps:"
echo ""
echo "  1. Send a WhatsApp message to your number to get a pairing code"
echo ""
echo "  2. Approve the pairing with:"
echo "     $DC run --rm openclaw-cli pairing approve whatsapp <CODE>"
echo ""
echo "  3. Add the Docker network to Traefik (if not already done):"
echo "     Edit your Traefik docker-compose.yml"
echo "     Add '$DOCKER_NETWORK' as an external network"
echo "     Restart Traefik"
echo ""
echo "  4. Test it! Send a WhatsApp message:"
echo "     'Hello! What can you help me build?'"
echo ""
echo "  Commands:"
echo "    $DC logs -f openclaw-gateway   # View OpenClaw logs"
echo "    $DC logs -f deployer           # View deployer logs"
echo "    $DC restart openclaw-gateway    # Restart OpenClaw"
echo "    $DC down                        # Stop everything"
echo "    $DC run --rm openclaw-cli pairing list  # List pairings"
echo ""
echo "============================================"
