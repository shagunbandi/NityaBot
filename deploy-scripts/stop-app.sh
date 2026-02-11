#!/bin/bash
set -euo pipefail

# stop-app.sh - Stop and remove a deployed app
#
# Usage: bash stop-app.sh <app-name>
#
# Stops the Docker container and removes it.
# Does NOT delete the source code or DNS record.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 1 ]; then
    echo "FAILURE: Usage: stop-app.sh <app-name>"
    exit 1
fi

APP_NAME="$1"
APP_DIR="$CLAWBOT_DIR/apps/$APP_NAME"

if [ ! -d "$APP_DIR" ]; then
    echo "FAILURE: App directory not found: $APP_DIR"
    exit 1
fi

if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
    echo "FAILURE: No docker-compose.yml found in $APP_DIR (app may not be deployed)"
    exit 1
fi

echo "Stopping $APP_NAME..."

cd "$APP_DIR"

# Stop and remove containers
docker compose down 2>&1

echo ""
echo "SUCCESS: $APP_NAME stopped"
echo "  Source code preserved in: $APP_DIR"
echo "  DNS record preserved (redeploy will reuse it)"
echo "  To redeploy: bash ~/clawbot/deploy-scripts/deploy-app.sh $APP_NAME <port>"
