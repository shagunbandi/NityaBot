---
name: app-deployer
description: Deploy applications to the Pi via the Deployer API. Handles Cloudflare DNS, Docker builds, and Traefik integration through HTTP calls to the deployer sidecar.
metadata: {"openclaw":{"always":true}}
---

# App Deployer Skill

Deploy applications via the **Deployer API** at `http://deployer:5000`.

**NEVER run `docker`, `docker-compose`, or any Docker commands. You have no Docker access.**

---

## Dockerfile Requirements

Every app directory must have a `Dockerfile` before calling the deploy API.

Rules:
- **EXPOSE the port** you pass to the deploy API
- Use multi-stage builds when building frontend/compiled code
- Use lightweight base images (alpine)
- Do NOT put secrets or `.env` files in the image -- credentials are injected at runtime

**React/static app (port 80):**
```dockerfile
FROM node:22-alpine AS build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
EXPOSE 80
HEALTHCHECK CMD wget -q --spider http://localhost/ || exit 1
```

**Node.js backend (port 3000):**
```dockerfile
FROM node:22-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3000
CMD ["node", "server.js"]
```

---

## Deploy an App

```bash
curl -s -X POST http://deployer:5000/deploy \
  -H "Content-Type: application/json" \
  -d '{"app_name": "my-app", "port": 80}'
```

**What this does, step by step:**
1. Reads credentials from `config/.env` (mounted from the host)
2. Creates a Cloudflare DNS CNAME: `my-app.pocketfusion.in`
3. Generates `docker-compose.yml` with Traefik labels (HTTPS, TLS cert, routing rule)
4. Builds the Docker image from the `Dockerfile` in the app directory
5. Starts the container on the `openclaw_network` — named **`openclaw-<app-name>`** (e.g. `openclaw-my-app`)
6. Verifies a container named `openclaw-<app-name>` is in `Up` state — fails if not
7. Returns `{"success": true/false, "output": "...", "exit_code": N}`

On success, the app is live at `https://my-app.pocketfusion.in` with a valid TLS cert.

---

## Deploy with Basic Auth (password-protected)

For apps that need HTTP Basic Auth. Traefik prompts for credentials before serving the app. Requires `BASIC_AUTH_USER` and `BASIC_AUTH_PASS` in `config/.env`.

```bash
curl -s -X POST http://deployer:5000/deploy \
  -H "Content-Type: application/json" \
  -d '{"app_name": "my-app", "port": 3000, "basic_auth": true}'
```

Use this when the user asks for a secure/password-protected app, or when the app directory has a `.secure-deploy` file.

---

## Environment Variables Injected into Your App

The deployer injects these into every app container at runtime from `config/.env`. Your code reads them as normal environment variables -- no `.env` file needed inside the image.

| Variable | Value |
|---|---|
| `POSTGRES_HOST` | `postgres` |
| `POSTGRES_PORT` | `5432` |
| `POSTGRES_USER` | set in config/.env |
| `POSTGRES_PASSWORD` | set in config/.env |
| `POSTGRES_DB` | set in config/.env |
| `MONGODB_URI` | `mongodb://mongodb:27017` (or with auth) |
| `GOOGLE_PLACES_API_KEY` | set in config/.env |

Use one **schema per app** in Postgres and one **database per app** in MongoDB. Create tables/collections on startup if they don't exist. Never use SQLite or in-container storage.

---

## Stop an App

```bash
curl -s -X POST http://deployer:5000/stop \
  -H "Content-Type: application/json" \
  -d '{"app_name": "my-app"}'
```

Stops and removes the container. Does not delete source code or DNS record.

---

## Status & Logs

```bash
# All apps
curl -s http://deployer:5000/status

# One app
curl -s "http://deployer:5000/status?app_name=my-app"

# Logs (last 50 lines)
curl -s "http://deployer:5000/logs/my-app?lines=50"
```

---

## Rules

- App names: lowercase with hyphens (`my-app`, not `MyApp`)
- A `Dockerfile` must exist in the app directory before deploying
- All deployed containers are named `openclaw-<app-name>` -- this is enforced by the deployer. Never use a different name.
- If deployment fails, read the `output` field for the error -- it usually points to a Dockerfile issue or wrong port
- Never hardcode credentials; rely on injected env vars
