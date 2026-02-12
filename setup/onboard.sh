#!/bin/bash
# onboard.sh - Display onboarding instructions and wait for user

# Detect docker-compose
if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    echo "ERROR: Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
    exit 1
fi

echo "--- OpenClaw Onboarding ---"
echo ""
echo "============================================"
echo "  MANUAL STEP REQUIRED"
echo "============================================"
echo ""
echo "  Run the following command in a NEW terminal:"
echo ""
echo "    cd $SCRIPT_DIR"
echo "    $DC run --rm openclaw-cli onboard --no-install-daemon"
echo ""
echo "  The wizard will guide you through:"
echo ""
echo "    1. Choose provider: Anthropic"
echo "    2. Authenticate: claude setup-token"
echo "       (paste your Claude Code token)"
echo "    3. Gateway bind: lan"
echo "    4. Gateway auth: token"
echo "    5. Gateway token: $GATEWAY_TOKEN"
echo "    6. Tailscale: Off"
echo "    7. Install daemon: No"
echo "    8. Choose channel: WhatsApp"
echo "    9. Scan the QR code with your phone"
echo ""
echo "  Complete the onboarding, then come back here"
echo "  and press ENTER to continue."
echo ""
echo "============================================"
echo ""
read -p "Press ENTER after completing onboarding... "
