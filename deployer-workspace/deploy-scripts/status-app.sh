#!/bin/bash
set -euo pipefail

# status-app.sh - Show status of deployed apps
#
# Usage:
#   bash status-app.sh           # List all apps
#   bash status-app.sh <app-name> # Detailed status for one app

die() { echo "FAILURE: $*" >&2; exit 1; }

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
APPS_DIR="$WORKSPACE_DIR/apps"
ENV_FILE="$WORKSPACE_DIR/config/.env"

# Detect docker-compose
if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    die "Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
fi

# Load env for domain info
if [ -f "$ENV_FILE" ]; then
    # shellcheck source=/dev/null
    source "$ENV_FILE"
fi

CF_BASE_DOMAIN="${CF_BASE_DOMAIN:-unknown}"

if [ $# -ge 1 ]; then
    # --- Detailed status for one app ---
    APP_NAME="$1"
    APP_DIR="$APPS_DIR/$APP_NAME"

    [ -d "$APP_DIR" ] || die "App not found: $APP_NAME (directory does not exist: $APP_DIR)"

    echo "=== $APP_NAME ==="
    echo "Directory: $APP_DIR"
    echo "Domain: ${APP_NAME}.${CF_BASE_DOMAIN}"

    if [ -f "$APP_DIR/docker-compose.yml" ]; then
        cd "$APP_DIR"

        CONTAINER_INFO=$($DC ps 2>/dev/null || echo "")

        if echo "$CONTAINER_INFO" | grep -q "Up"; then
            echo "State: running"
            echo "$CONTAINER_INFO" | grep "openclaw-${APP_NAME}" 2>/dev/null || true
        elif echo "$CONTAINER_INFO" | grep -q "Exit"; then
            echo "State: exited"
            echo "$CONTAINER_INFO" | grep "openclaw-${APP_NAME}" 2>/dev/null || true
        else
            echo "State: not running"
        fi
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
            if $DC ps 2>/dev/null | grep -q "Up"; then
                STATUS="running"
            elif $DC ps 2>/dev/null | grep -q "Exit"; then
                STATUS="exited"
            else
                STATUS="stopped"
            fi
        fi

        echo "  $APP_NAME -- https://$DOMAIN -- $STATUS"
    done

    echo ""
fi
