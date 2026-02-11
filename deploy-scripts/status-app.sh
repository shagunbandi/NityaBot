#!/bin/bash
set -euo pipefail

# status-app.sh - Show status of deployed apps
#
# Usage:
#   bash status-app.sh           # List all apps
#   bash status-app.sh <app-name> # Detailed status for one app

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOT_DIR="$(dirname "$SCRIPT_DIR")"
APPS_DIR="$CLAWBOT_DIR/apps"
ENV_FILE="$CLAWBOT_DIR/config/.env"

# Load env for domain info
if [ -f "$ENV_FILE" ]; then
    source "$ENV_FILE"
fi

CF_BASE_DOMAIN="${CF_BASE_DOMAIN:-unknown}"

if [ $# -ge 1 ]; then
    # --- Detailed status for one app ---
    APP_NAME="$1"
    APP_DIR="$APPS_DIR/$APP_NAME"

    if [ ! -d "$APP_DIR" ]; then
        echo "FAILURE: App not found: $APP_NAME"
        echo "  Directory does not exist: $APP_DIR"
        exit 1
    fi

    echo "=== $APP_NAME ==="
    echo "Directory: $APP_DIR"
    echo "Domain: ${APP_NAME}.${CF_BASE_DOMAIN}"

    if [ -f "$APP_DIR/docker-compose.yml" ]; then
        cd "$APP_DIR"

        CONTAINER_INFO=$(docker compose ps --format json 2>/dev/null || echo "")

        if [ -n "$CONTAINER_INFO" ]; then
            STATUS=$(echo "$CONTAINER_INFO" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        data = data[0] if data else {}
    state = data.get('State', data.get('state', 'unknown'))
    status = data.get('Status', data.get('status', ''))
    print(f'State: {state}')
    if status:
        print(f'Status: {status}')
except:
    print('State: unknown')
" 2>/dev/null || echo "State: unknown")
            echo "$STATUS"
        else
            echo "State: not running"
        fi

        # Show image info
        IMAGE=$(docker compose images --format json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        data = data[0] if data else {}
    print(f\"Image: {data.get('Repository', 'unknown')}:{data.get('Tag', 'latest')}\")
    print(f\"Size: {data.get('Size', 'unknown')}\")
except:
    pass
" 2>/dev/null || true)

    else
        echo "State: not deployed (no docker-compose.yml)"
    fi

    # Show files
    echo ""
    echo "Files:"
    ls -la "$APP_DIR" 2>/dev/null | tail -n +2

else
    # --- List all apps ---

    if [ ! -d "$APPS_DIR" ]; then
        echo "No apps directory found. No apps have been created yet."
        exit 0
    fi

    APP_DIRS=$(ls -d "$APPS_DIR"/*/ 2>/dev/null || true)

    if [ -z "$APP_DIRS" ]; then
        echo "No apps found in $APPS_DIR"
        exit 0
    fi

    echo "=== Deployed Apps ==="
    echo ""

    for APP_DIR in $APP_DIRS; do
        APP_NAME=$(basename "$APP_DIR")
        DOMAIN="${APP_NAME}.${CF_BASE_DOMAIN}"
        STATUS="no compose file"

        if [ -f "$APP_DIR/docker-compose.yml" ]; then
            cd "$APP_DIR"
            STATUS=$(docker compose ps --format json 2>/dev/null | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        data = data[0] if data else {}
    state = data.get('State', data.get('state', 'stopped'))
    status_detail = data.get('Status', '')
    if status_detail:
        print(f'{state} ({status_detail})')
    else:
        print(state)
except:
    print('stopped')
" 2>/dev/null || echo "stopped")
        fi

        echo "  $APP_NAME — https://$DOMAIN — $STATUS"
    done

    echo ""
fi
