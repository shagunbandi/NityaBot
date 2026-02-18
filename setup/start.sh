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

# Ensure variables are set (in case script is run standalone)
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$SCRIPT_DIR/.openclaw}"

cd "$SCRIPT_DIR"
$DC up -d openclaw-gateway deployer postgres mongodb 2>&1

# shellcheck source=/dev/null
source "$SCRIPT_DIR/deployer-workspace/config/.env"
DOCKER_NETWORK="${DOCKER_NETWORK:-openclaw_network}"
OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"

echo ""
echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  Containers are running:"
echo "    - openclaw-gateway (Opus + Haiku models)"
echo "    - openclaw-deployer (Flask API with Docker access)"
echo "    - openclaw-postgres (shared PostgreSQL database)"
echo "    - openclaw-mongodb (shared MongoDB database)"
echo ""
echo "  Architecture:"
echo "    - OpenClaw writes code to apps/"
echo "    - Deployer handles Docker operations via HTTP API"
echo "    - No direct Docker access in OpenClaw container"
echo ""
echo "  Onboarding is complete. One last step:"
echo ""
echo "  Send a WhatsApp message to your bot to get a pairing code,"
echo "  then approve it with:"
echo "    $DC run --rm openclaw-cli pairing approve whatsapp <CODE>"
echo ""
echo "  If you need to redo onboarding at any time:"
echo "    $DC run --rm openclaw-cli onboard --no-install-daemon"
echo ""
echo "  Useful commands:"
echo "    $DC logs -f openclaw-gateway   # View logs"
echo "    $DC logs -f deployer           # Deployer logs"
echo "    $DC restart openclaw-gateway    # Restart"
echo "    $DC down                        # Stop all"
echo ""
echo "============================================"
