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

# Enable WhatsApp plugin and set gateway mode
python3 -c "
import json
with open('$OPENCLAW_CONFIG_FILE', 'r') as f:
    config = json.load(f)

# Enable WhatsApp plugin
if 'plugins' not in config:
    config['plugins'] = {}
if 'entries' not in config['plugins']:
    config['plugins']['entries'] = {}
if 'whatsapp' not in config['plugins']['entries']:
    config['plugins']['entries']['whatsapp'] = {}
config['plugins']['entries']['whatsapp']['enabled'] = True

# Ensure gateway mode is set
if 'gateway' not in config:
    config['gateway'] = {}
config['gateway']['mode'] = 'local'

with open('$OPENCLAW_CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)

print('Updated config: enabled WhatsApp and set gateway mode')
"

echo "Copied Opus+Haiku config to $OPENCLAW_CONFIG_FILE"
echo ""
echo "IMPORTANT: After onboarding completes, approve WhatsApp pairing with:"
echo "  docker-compose run --rm openclaw-cli pairing approve whatsapp <CODE>"
echo ""
echo "Or manually add your phone number to $OPENCLAW_CONFIG_FILE"
echo "
