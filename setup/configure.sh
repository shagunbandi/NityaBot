#!/bin/bash
# configure.sh - Copy Opus+Haiku model config and patch paths

echo ""
echo "--- Configuring Opus + Haiku model routing ---"
echo ""

OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"

if [ -f "$OPENCLAW_CONFIG_FILE" ]; then
    BACKUP="$OPENCLAW_CONFIG_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$OPENCLAW_CONFIG_FILE" "$BACKUP"
    echo "Backed up existing config to: $BACKUP"
fi

cp "$SCRIPT_DIR/deployer-workspace/config/openclaw.json" "$OPENCLAW_CONFIG_FILE"

# Update workspace path to container path
python3 -c "
with open('$OPENCLAW_CONFIG_FILE', 'r') as f:
    content = f.read()
content = content.replace('~/clawbot', '/home/node/.openclaw/workspace')
with open('$OPENCLAW_CONFIG_FILE', 'w') as f:
    f.write(content)
print('Updated workspace path for container')
"

echo "Copied Opus+Haiku config to $OPENCLAW_CONFIG_FILE"
echo ""
echo "IMPORTANT: Edit $OPENCLAW_CONFIG_FILE and replace '+YOUR_NUMBER_HERE'"
echo "  with your WhatsApp phone number (e.g., +919876543210)"
echo ""
