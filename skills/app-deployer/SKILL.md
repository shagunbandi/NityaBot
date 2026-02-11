---
name: app-deployer
description: Deploy applications to the Pi using whitelisted deploy scripts. Handles Cloudflare DNS, Docker builds, and Traefik integration.
metadata: {"openclaw":{"always":true}}
---

# App Deployer Skill

Deploy applications that have been built in `~/clawbot/apps/<app-name>/`.

## Deploy scripts

All deployment happens through scripts in `~/clawbot/deploy-scripts/`. These scripts handle Docker and Cloudflare — never run Docker commands directly.

### Deploy an app

```bash
bash ~/clawbot/deploy-scripts/deploy-app.sh <app-name> <port>
```

Requirements:
- A `Dockerfile` must exist in `~/clawbot/apps/<app-name>/`
- `<port>` is the internal port the app listens on inside the container (commonly 80 for nginx-served apps, 3000 for Node, 8080 for Go)

What the script does:
1. Loads secrets from `~/clawbot/config/.env`
2. Creates a Cloudflare DNS A record: `<app-name>.<CF_BASE_DOMAIN>` → `<PI_PUBLIC_IP>`
3. Generates `docker-compose.yml` with Traefik labels in the app directory
4. Builds the Docker image from the Dockerfile
5. Starts the container on the `openclaw_network`
6. Outputs `SUCCESS: <app-name> deployed at https://<app-name>.<CF_BASE_DOMAIN>` or `FAILURE: <error details>`

### Stop an app

```bash
bash ~/clawbot/deploy-scripts/stop-app.sh <app-name>
```

Stops and removes the container. Does not delete source code or DNS record.

### Check status

```bash
bash ~/clawbot/deploy-scripts/status-app.sh [app-name]
```

Without arguments: lists all running apps with name, URL, status, and uptime.
With app-name: detailed status for one app.

### View logs

```bash
bash ~/clawbot/deploy-scripts/logs-app.sh <app-name> [lines]
```

Shows the last N lines of container logs (default: 50).

## Rules

- Always use these scripts. Never run `docker compose`, `docker build`, or `docker run` directly.
- App names must be lowercase with hyphens: `my-app`, not `MyApp` or `my_app`.
- The deploy script reads environment variables from `~/clawbot/config/.env`. Do not hardcode Cloudflare tokens or IPs.
- If deployment fails, read the error output and fix the issue (usually a Dockerfile problem or port conflict).
