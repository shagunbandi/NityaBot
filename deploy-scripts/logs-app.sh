#!/bin/bash
set -euo pipefail

# logs-app.sh - View logs for a deployed app
#
# Usage: bash logs-app.sh <app-name> [lines]
#
# Default: last 50 lines

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOT_DIR="$(dirname "$SCRIPT_DIR")"

if [ $# -lt 1 ]; then
    echo "FAILURE: Usage: logs-app.sh <app-name> [lines]"
    exit 1
fi

APP_NAME="$1"
LINES="${2:-50}"
APP_DIR="$CLAWBOT_DIR/apps/$APP_NAME"

if [ ! -d "$APP_DIR" ]; then
    echo "FAILURE: App not found: $APP_NAME"
    echo "  Directory does not exist: $APP_DIR"
    exit 1
fi

if [ ! -f "$APP_DIR/docker-compose.yml" ]; then
    echo "FAILURE: App is not deployed (no docker-compose.yml in $APP_DIR)"
    exit 1
fi

cd "$APP_DIR"

echo "=== Logs for $APP_NAME (last $LINES lines) ==="
echo ""

docker compose logs --tail="$LINES" --no-log-prefix 2>&1 || {
    echo "FAILURE: Could not retrieve logs. Is the container running?"
    echo "  Check status: bash ~/clawbot/deploy-scripts/status-app.sh $APP_NAME"
    exit 1
}
