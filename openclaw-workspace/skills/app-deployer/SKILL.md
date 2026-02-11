---
name: app-deployer
description: Deploy applications to the Pi via the Deployer API. Handles Cloudflare DNS, Docker builds, and Traefik integration through HTTP calls to the deployer sidecar.
metadata: {"openclaw":{"always":true}}
---

# App Deployer Skill

Deploy applications that have been built in `~/clawbot/apps/<app-name>/`.

## How deployment works

You are running inside a Docker container with **NO Docker access**. All deployment operations go through the **Deployer API** -- a separate container that handles Docker on your behalf.

**NEVER run `docker`, `docker-compose`, `docker build`, or `docker run` directly. You do not have access.**

The deployer runs at `http://deployer:5000` on the internal Docker network.

## Deploy an app

```bash
curl -s -X POST http://deployer:5000/deploy \
  -H "Content-Type: application/json" \
  -d '{"app_name": "<app-name>", "port": <port>}'
```

Requirements:
- A `Dockerfile` must exist in `~/clawbot/apps/<app-name>/`
- `port` is the internal port the app listens on inside the container (commonly 80 for nginx-served apps, 3000 for Node, 8080 for Go)

What the deployer does:
1. Creates a Cloudflare DNS CNAME record: `<app-name>.<CF_BASE_DOMAIN>`
2. Generates `docker-compose.yml` with Traefik labels in the app directory
3. Builds the Docker image from the Dockerfile
4. Starts the container on the Docker network
5. Returns JSON with `success`, `output`, and `exit_code`

Response on success:
```json
{"success": true, "output": "SUCCESS: sip-calculator deployed\n  URL: https://sip-calculator.yourdomain.com\n  ...", "exit_code": 0}
```

Response on failure:
```json
{"success": false, "output": "FAILURE: Docker build failed...", "exit_code": 1}
```

## Stop an app

```bash
curl -s -X POST http://deployer:5000/stop \
  -H "Content-Type: application/json" \
  -d '{"app_name": "<app-name>"}'
```

Stops and removes the container. Does not delete source code or DNS record.

## Check status

```bash
# All apps
curl -s http://deployer:5000/status

# One app
curl -s "http://deployer:5000/status?app_name=<app-name>"
```

## View logs

```bash
curl -s "http://deployer:5000/logs/<app-name>?lines=50"
```

Shows the last N lines of container logs (default: 50).

## Rules

- **NEVER run Docker commands directly.** Always use the Deployer API.
- App names must be lowercase with hyphens: `my-app`, not `MyApp` or `my_app`.
- The deployer reads environment variables from `config/.env`. Do not hardcode Cloudflare tokens or domains.
- If deployment fails, read the `output` field in the JSON response and fix the issue (usually a Dockerfile problem or port conflict).
