#!/bin/bash
set -euo pipefail

# setup.sh - One-command setup for OpenClaw Pi Builder
#
# This script:
#   1. Checks prerequisites (Docker, Node.js >= 22, Traefik)
#   2. Installs OpenClaw globally
#   3. Pauses for you to run openclaw onboard (WhatsApp QR + Anthropic token)
#   4. Copies the Opus+Haiku config into ~/.openclaw/openclaw.json
#   5. Creates the Docker network for Traefik integration
#   6. Creates required directories
#   7. Makes deploy scripts executable

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OPENCLAW_CONFIG_DIR="$HOME/.openclaw"
OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"

echo "============================================"
echo "  OpenClaw Pi Builder - Setup"
echo "============================================"
echo ""

# --- Step 1: Check prerequisites ---

echo "--- Step 1: Checking prerequisites ---"
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

# Check docker compose (v2)
if docker compose version &> /dev/null; then
    COMPOSE_VERSION=$(docker compose version --short 2>/dev/null || echo "unknown")
    echo "[OK] Docker Compose: $COMPOSE_VERSION"
else
    echo "[MISSING] Docker Compose v2 is not available"
    echo "  It should come with Docker. Try: sudo apt install docker-compose-plugin"
    MISSING=1
fi

# Check Node.js >= 22
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version 2>/dev/null || echo "v0")
    NODE_MAJOR=$(echo "$NODE_VERSION" | sed 's/v//' | cut -d. -f1)
    if [ "$NODE_MAJOR" -ge 22 ]; then
        echo "[OK] Node.js: $NODE_VERSION"
    else
        echo "[WRONG VERSION] Node.js: $NODE_VERSION (need >= 22)"
        echo "  Install: https://nodejs.org/ or use nvm"
        MISSING=1
    fi
else
    echo "[MISSING] Node.js is not installed"
    echo "  Install: curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && sudo apt install -y nodejs"
    MISSING=1
fi

# Check curl (needed for Cloudflare API)
if command -v curl &> /dev/null; then
    echo "[OK] curl: $(curl --version | head -1)"
else
    echo "[MISSING] curl is not installed"
    echo "  Install: sudo apt install curl"
    MISSING=1
fi

# Check python3 (needed for JSON parsing in scripts)
if command -v python3 &> /dev/null; then
    echo "[OK] python3: $(python3 --version 2>/dev/null)"
else
    echo "[MISSING] python3 is not installed"
    echo "  Install: sudo apt install python3"
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
if [ ! -f "$SCRIPT_DIR/config/.env" ]; then
    echo "[MISSING] config/.env not found"
    echo ""
    echo "  Create it now:"
    echo "    cp config/.env.example config/.env"
    echo "    nano config/.env"
    echo ""
    echo "  Then re-run this script."
    exit 1
fi

echo "[OK] config/.env exists"
echo ""

# --- Step 2: Install OpenClaw ---

echo "--- Step 2: Installing OpenClaw ---"
echo ""

if command -v openclaw &> /dev/null; then
    CURRENT_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
    echo "OpenClaw is already installed: $CURRENT_VERSION"
    echo "Updating to latest..."
    npm install -g openclaw@latest 2>&1 || {
        echo "Update failed. Continuing with existing version."
    }
else
    echo "Installing OpenClaw..."
    npm install -g openclaw@latest 2>&1 || {
        echo ""
        echo "FAILURE: Could not install OpenClaw."
        echo "  Try with sudo: sudo npm install -g openclaw@latest"
        exit 1
    }
fi

NEW_VERSION=$(openclaw --version 2>/dev/null || echo "unknown")
echo "OpenClaw version: $NEW_VERSION"
echo ""

# --- Step 3: OpenClaw Onboarding ---

echo "--- Step 3: OpenClaw Onboarding ---"
echo ""
echo "============================================"
echo "  MANUAL STEP REQUIRED"
echo "============================================"
echo ""
echo "  Run the following command in a NEW terminal:"
echo ""
echo "    openclaw onboard --install-daemon"
echo ""
echo "  The wizard will guide you through:"
echo ""
echo "    1. Choose provider: Anthropic"
echo "    2. Authenticate: claude setup-token"
echo "       (paste your Claude Code token)"
echo "    3. Choose channel: WhatsApp"
echo "    4. Scan the QR code with your phone"
echo ""
echo "  Complete the onboarding, then come back here"
echo "  and press ENTER to continue."
echo ""
echo "============================================"
echo ""
read -p "Press ENTER after completing 'openclaw onboard'... "

# Verify OpenClaw is set up
if [ ! -d "$OPENCLAW_CONFIG_DIR" ]; then
    echo ""
    echo "WARNING: ~/.openclaw/ directory not found."
    echo "  Did you complete 'openclaw onboard'?"
    echo "  Continuing anyway, but things may not work."
    echo ""
fi

# --- Step 4: Configure Opus + Haiku ---

echo ""
echo "--- Step 4: Configuring Opus + Haiku model routing ---"
echo ""

mkdir -p "$OPENCLAW_CONFIG_DIR"

if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
    # Backup existing config
    BACKUP="$OPENCLAW_CONFIG_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$OPENCLAW_CONFIG_FILE" "$BACKUP"
    echo "Backed up existing config to: $BACKUP"
fi

# Copy our config
cp "$SCRIPT_DIR/config/openclaw.json" "$OPENCLAW_CONFIG_FILE"

# Update workspace path to absolute path
WORKSPACE_PATH="$HOME/clawbot"

# If this repo is not at ~/clawbot, use the actual path
if [ "$SCRIPT_DIR" != "$WORKSPACE_PATH" ]; then
    WORKSPACE_PATH="$SCRIPT_DIR"
    echo "Note: Repo is at $SCRIPT_DIR (not ~/clawbot)"
    echo "  Setting workspace to: $WORKSPACE_PATH"
fi

# Replace workspace path in config using python3 (handles JSON5 safely)
python3 -c "
import re
with open('$OPENCLAW_CONFIG_FILE', 'r') as f:
    content = f.read()
content = content.replace('~/clawbot', '$WORKSPACE_PATH')
with open('$OPENCLAW_CONFIG_FILE', 'w') as f:
    f.write(content)
print('Updated workspace path in config')
"

echo "Copied Opus+Haiku config to $OPENCLAW_CONFIG_FILE"
echo ""
echo "IMPORTANT: Edit $OPENCLAW_CONFIG_FILE and replace '+YOUR_NUMBER_HERE'"
echo "  with your WhatsApp phone number (e.g., +919876543210)"
echo ""

# --- Step 5: Create Docker network ---

echo "--- Step 5: Creating Docker network ---"
echo ""

# Load .env for network name
source "$SCRIPT_DIR/config/.env"
DOCKER_NETWORK="${DOCKER_NETWORK:-openclaw_network}"

if docker network inspect "$DOCKER_NETWORK" &> /dev/null; then
    echo "Docker network '$DOCKER_NETWORK' already exists"
else
    docker network create "$DOCKER_NETWORK" 2>&1
    echo "Created Docker network: $DOCKER_NETWORK"
fi

echo ""
echo "IMPORTANT: Your Traefik docker-compose.yml must include:"
echo ""
echo "  networks:"
echo "    $DOCKER_NETWORK:"
echo "      external: true"
echo ""
echo "  Then restart Traefik: cd ~/traefik && docker compose restart"
echo ""

# --- Step 6: Create directories ---

echo "--- Step 6: Creating directories ---"
echo ""

mkdir -p "$SCRIPT_DIR/apps"
mkdir -p "$SCRIPT_DIR/shared/logs"
echo "Created: apps/"
echo "Created: shared/logs/"
echo ""

# --- Step 7: Make scripts executable ---

echo "--- Step 7: Making deploy scripts executable ---"
echo ""

chmod +x "$SCRIPT_DIR/deploy-scripts/"*.sh
echo "Made all scripts in deploy-scripts/ executable"
echo ""

# --- Done ---

echo "============================================"
echo "  Setup Complete!"
echo "============================================"
echo ""
echo "  What was configured:"
echo "    - OpenClaw installed and onboarded"
echo "    - Opus (claude-opus-4-6) as primary model"
echo "    - Haiku (claude-haiku-3-5) for sub-agents"
echo "    - Workspace: $WORKSPACE_PATH"
echo "    - Docker network: $DOCKER_NETWORK"
echo ""
echo "  Remaining manual steps:"
echo ""
echo "  1. Edit WhatsApp number in config:"
echo "     nano $OPENCLAW_CONFIG_FILE"
echo "     Replace '+YOUR_NUMBER_HERE' with your number"
echo ""
echo "  2. Add the Docker network to Traefik:"
echo "     Edit your Traefik docker-compose.yml"
echo "     Add '$DOCKER_NETWORK' as an external network"
echo "     Restart Traefik"
echo ""
echo "  3. Test it! Send a WhatsApp message:"
echo "     'Hello! What can you help me build?'"
echo ""
echo "============================================"
