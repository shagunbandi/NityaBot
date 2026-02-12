#!/bin/bash
# configure.sh - Merge Opus+Haiku model config with onboarding settings

echo ""
echo "--- Configuring Opus + Haiku model routing ---"
echo ""

# Ensure variables are set (in case script is run standalone)
OPENCLAW_CONFIG_DIR="${OPENCLAW_CONFIG_DIR:-$SCRIPT_DIR/.openclaw}"
OPENCLAW_CONFIG_FILE="$OPENCLAW_CONFIG_DIR/openclaw.json"

if [ ! -f "$OPENCLAW_CONFIG_FILE" ]; then
    echo "ERROR: Onboarding config not found at $OPENCLAW_CONFIG_FILE"
    echo "Make sure you completed the onboarding step first."
    exit 1
fi

# Backup the onboarding config
BACKUP="$OPENCLAW_CONFIG_FILE.backup.$(date +%Y%m%d-%H%M%S)"
cp "$OPENCLAW_CONFIG_FILE" "$BACKUP"
echo "Backed up onboarding config to: $BACKUP"

# Merge our Opus+Haiku settings into the onboarding config
python3 -c "
import json

# Load onboarding config
with open('$OPENCLAW_CONFIG_FILE', 'r') as f:
    config = json.load(f)

# Load our template
with open('$SCRIPT_DIR/config/openclaw.json', 'r') as f:
    template = json.load(f)

# Merge agents config (Opus + Haiku setup)
if 'agents' not in config:
    config['agents'] = {}
if 'defaults' not in config['agents']:
    config['agents']['defaults'] = {}

config['agents']['defaults'].update(template['agents']['defaults'])

# Ensure gateway mode is set
if 'gateway' not in config:
    config['gateway'] = {}
config['gateway']['mode'] = 'local'

# Enable WhatsApp plugin (in case onboarding didn't)
if 'plugins' not in config:
    config['plugins'] = {}
if 'entries' not in config['plugins']:
    config['plugins']['entries'] = {}
if 'whatsapp' not in config['plugins']['entries']:
    config['plugins']['entries']['whatsapp'] = {}
config['plugins']['entries']['whatsapp']['enabled'] = True

with open('$OPENCLAW_CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)

print('Merged Opus+Haiku model routing into config')
"

echo "Updated config with Opus (architect) + Haiku (developers) setup"
echo ""
