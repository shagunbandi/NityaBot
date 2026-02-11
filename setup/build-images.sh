#!/bin/bash
# build-images.sh - Clone OpenClaw repo and build both Docker images

# --- Clone / update OpenClaw source ---

echo "--- Getting OpenClaw source ---"
echo ""

if [ -d "$OPENCLAW_SRC_DIR" ]; then
    echo "OpenClaw source already exists at $OPENCLAW_SRC_DIR"
    echo "Pulling latest..."
    cd "$OPENCLAW_SRC_DIR"
    git pull 2>&1 || echo "Pull failed, continuing with existing version."
    cd "$SCRIPT_DIR"
else
    echo "Cloning OpenClaw..."
    git clone https://github.com/openclaw/openclaw.git "$OPENCLAW_SRC_DIR" 2>&1
fi

echo ""

# --- Build OpenClaw Docker image ---

echo "--- Building OpenClaw Docker image ---"
echo ""
echo "(This may take a few minutes on first run...)"
echo ""

docker build \
    -t openclaw:local \
    -f "$OPENCLAW_SRC_DIR/Dockerfile" \
    "$OPENCLAW_SRC_DIR" 2>&1

echo ""
echo "Docker image built: openclaw:local"
echo ""

# --- Build Deployer sidecar image ---

echo "--- Building Deployer sidecar image ---"
echo ""

docker build \
    -t openclaw-deployer:local \
    -f "$SCRIPT_DIR/deployer/Dockerfile" \
    "$SCRIPT_DIR/deployer" 2>&1

echo ""
echo "Docker image built: openclaw-deployer:local"
echo ""
