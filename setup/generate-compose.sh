#!/bin/bash
# generate-compose.sh - Create directories, Docker network, and docker-compose.yml

# --- Create directories ---

echo "--- Creating directories ---"
echo ""

mkdir -p "$OPENCLAW_CONFIG_DIR"
mkdir -p "$SCRIPT_DIR/apps"
mkdir -p "$SCRIPT_DIR/shared/logs"
echo "Created: .openclaw/ (config)"
echo "Created: apps/"
echo "Created: shared/logs/"
echo ""

# --- Create Docker network ---

echo "--- Creating Docker network ---"
echo ""

# shellcheck source=/dev/null
source "$SCRIPT_DIR/deployer-workspace/config/.env"
DOCKER_NETWORK="${DOCKER_NETWORK:-openclaw_network}"

if docker network inspect "$DOCKER_NETWORK" &> /dev/null; then
    echo "Docker network '$DOCKER_NETWORK' already exists"
else
    docker network create "$DOCKER_NETWORK" 2>&1
    echo "Created Docker network: $DOCKER_NETWORK"
fi

echo ""

# --- Generate gateway token ---

if command -v openssl &> /dev/null; then
    GATEWAY_TOKEN="$(openssl rand -hex 32)"
else
    GATEWAY_TOKEN="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
fi

# --- Generate docker-compose.yml ---

echo "--- Generating docker-compose.yml ---"
echo ""

cat > "$SCRIPT_DIR/docker-compose.yml" << COMPOSE_EOF
services:
  openclaw-gateway:
    image: openclaw:local
    container_name: openclaw-gateway
    environment:
      HOME: /home/node
      OPENCLAW_HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: ${GATEWAY_TOKEN}
    volumes:
      # OpenClaw config
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      # OpenClaw workspace (skills, AGENTS.md)
      - ${SCRIPT_DIR}/openclaw-workspace:/home/node/.openclaw/workspace
      # Shared folders (mounted at workspace subdirs)
      - ${SCRIPT_DIR}/apps:/home/node/.openclaw/workspace/apps
      - ${SCRIPT_DIR}/shared:/home/node/.openclaw/workspace/shared
      # NO docker.sock - OpenClaw has zero Docker access
    ports:
      - "18789:18789"
      - "18790:18790"
    networks:
      - ${DOCKER_NETWORK}
    init: true
    restart: unless-stopped
    command:
      [
        "node",
        "dist/index.js",
        "gateway",
        "--bind",
        "lan",
        "--port",
        "18789",
      ]

  deployer:
    image: openclaw-deployer:local
    container_name: openclaw-deployer
    environment:
      WORKSPACE_DIR: /workspace
      SCRIPTS_DIR: /deploy-scripts
    volumes:
      # Docker socket - deployer is the ONLY container with Docker access
      - /var/run/docker.sock:/var/run/docker.sock
      # Deploy scripts (read-only)
      - ${SCRIPT_DIR}/deployer-workspace/deploy-scripts:/deploy-scripts:ro
      # Config env (read-only)
      - ${SCRIPT_DIR}/deployer-workspace/config/.env:/workspace/config/.env:ro
      # Shared folders (rw - needs to generate docker-compose.yml and build images)
      - ${SCRIPT_DIR}/apps:/workspace/apps
      - ${SCRIPT_DIR}/shared:/workspace/shared
    networks:
      - ${DOCKER_NETWORK}
    # NO ports exposed to host - only accessible from the Docker network
    init: true
    restart: unless-stopped

  openclaw-cli:
    image: openclaw:local
    container_name: openclaw-cli
    environment:
      HOME: /home/node
      OPENCLAW_HOME: /home/node
      TERM: xterm-256color
      OPENCLAW_GATEWAY_TOKEN: ${GATEWAY_TOKEN}
      BROWSER: echo
    volumes:
      - ${OPENCLAW_CONFIG_DIR}:/home/node/.openclaw
      # OpenClaw workspace (skills, AGENTS.md)
      - ${SCRIPT_DIR}/openclaw-workspace:/home/node/.openclaw/workspace
      # Shared folders (mounted at workspace subdirs)
      - ${SCRIPT_DIR}/apps:/home/node/.openclaw/workspace/apps
      - ${SCRIPT_DIR}/shared:/home/node/.openclaw/workspace/shared
      # NO docker.sock
    stdin_open: true
    tty: true
    init: true
    networks:
      - ${DOCKER_NETWORK}
    entrypoint: ["node", "dist/index.js"]

networks:
  ${DOCKER_NETWORK}:
    external: true
COMPOSE_EOF

echo "Generated docker-compose.yml"
echo "Gateway token: $GATEWAY_TOKEN"
echo ""

# Save token for reference
echo "$GATEWAY_TOKEN" > "$OPENCLAW_CONFIG_DIR/.gateway-token"

# --- Make deploy scripts executable ---

echo "--- Making deploy scripts executable ---"
echo ""

chmod +x "$SCRIPT_DIR/deployer-workspace/deploy-scripts/"*.sh
echo "Made all scripts in deployer-workspace/deploy-scripts/ executable"
echo ""
