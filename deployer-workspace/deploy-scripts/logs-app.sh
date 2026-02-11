#!/bin/bash
set -euo pipefail

# logs-app.sh - View logs for a deployed app
#
# Usage: bash logs-app.sh <app-name> [lines]
#
# Default: last 50 lines

die() { echo "FAILURE: $*" >&2; exit 1; }

WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
APPS_DIR="$WORKSPACE_DIR/apps"

# Detect docker-compose
if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    die "Neither 'docker compose' (v2) nor 'docker-compose' (v1) found"
fi

[ $# -ge 1 ] || die "Usage: logs-app.sh <app-name> [lines]"

APP_NAME="$1"
LINES="${2:-50}"
APP_DIR="$APPS_DIR/$APP_NAME"

[ -d "$APP_DIR" ]                      || die "App not found: $APP_NAME (directory does not exist: $APP_DIR)"
[ -f "$APP_DIR/docker-compose.yml" ]   || die "App is not deployed (no docker-compose.yml in $APP_DIR)"

cd "$APP_DIR"

echo "=== Logs for $APP_NAME (last $LINES lines) ==="
echo ""

$DC logs --tail="$LINES" 2>&1 || die "Could not retrieve logs. Is the container running?"
