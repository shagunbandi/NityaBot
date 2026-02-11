#!/bin/bash
set -euo pipefail

# setup.sh - One-command setup for OpenClaw Pi Builder
#
# This script orchestrates the full setup by calling sub-scripts in setup/:
#   1. check-prereqs.sh  - Verify Docker, docker compose, jq, git, config
#   2. build-images.sh   - Clone OpenClaw repo, build both Docker images
#   3. generate-compose.sh - Create dirs, network, docker-compose.yml
#   4. onboard.sh        - WhatsApp QR + Anthropic token (manual step)
#   5. configure.sh      - Copy Opus+Haiku model config
#   6. start.sh          - Start gateway + deployer, print summary

# --- Shared variables (used by all sub-scripts) ---

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OPENCLAW_SRC_DIR="$SCRIPT_DIR/.openclaw-src"
export OPENCLAW_CONFIG_DIR="$SCRIPT_DIR/.openclaw"

SETUP_DIR="$SCRIPT_DIR/setup"

echo "============================================"
echo "  OpenClaw Pi Builder - Setup"
echo "============================================"
echo ""

# --- Run each step ---

source "$SETUP_DIR/check-prereqs.sh"
source "$SETUP_DIR/build-images.sh"
source "$SETUP_DIR/generate-compose.sh"
source "$SETUP_DIR/onboard.sh"
source "$SETUP_DIR/configure.sh"
source "$SETUP_DIR/start.sh"
