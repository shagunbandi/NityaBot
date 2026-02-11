#!/bin/bash
set -euo pipefail

# stop-app.sh - Stop and remove a deployed app
#
# Usage: bash stop-app.sh <app-name>
#
# Stops the Docker container and removes it.
# Does NOT delete the source code or DNS record.

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

[ $# -ge 1 ] || die "Usage: stop-app.sh <app-name>"

APP_NAME="$1"
APP_DIR="$APPS_DIR/$APP_NAME"

[ -d "$APP_DIR" ]                      || die "App directory not found: $APP_DIR"
[ -f "$APP_DIR/docker-compose.yml" ]   || die "No docker-compose.yml found in $APP_DIR (app may not be deployed)"

echo "Stopping $APP_NAME..."

cd "$APP_DIR"
$DC down 2>&1

echo ""
echo "SUCCESS: $APP_NAME stopped"
echo "  Source code preserved in: $APP_DIR"
echo "  DNS record preserved (redeploy will reuse it)"
