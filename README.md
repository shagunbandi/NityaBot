# OpenClaw Pi Builder

Build and deploy full applications on your Raspberry Pi by describing them on WhatsApp.

Say **"Create a SIP Calculator application"** and OpenClaw will plan it, build it, dockerize it, deploy it, and hand you a live URL -- all from your phone.

Uses **Opus as the architect** (planning, tech decisions, task breakdown, user communication) and **Haiku sub-agents as developers** (writing code, creating Dockerfiles, testing, deploying) through OpenClaw's native sub-agent system.

## What This Is

This is a shareable configuration layer on top of [OpenClaw](https://openclaw.ai), the open-source personal AI assistant. It turns OpenClaw into an application factory for your Pi.

It provides:
- **Custom skills** that teach OpenClaw how to build, dockerize, and deploy full applications
- **A deployer sidecar** (Flask API) that safely handles Docker operations
- **Deploy scripts** that handle Docker and Cloudflare DNS
- **OpenClaw config** with Opus (architect) + Haiku (developers) model routing
- **AGENTS.md** instructions that define the build-and-deploy workflow
- **A setup script** that wires everything together

## Prerequisites

1. **A Raspberry Pi** (or any Linux machine) with **Docker** and **docker compose** installed
2. **Traefik** already running as a reverse proxy
3. **Cloudflare** account with API access for your domain
4. **jq** installed (`sudo apt install jq`)
5. **A Claude Pro/Max subscription** (for Anthropic auth via `claude setup-token`)

## How It Works

### Architecture

```
You (WhatsApp)
  │
  ▼
┌──────────────────────────────────────────────────────┐
│  Docker Network (openclaw_network)                   │
│                                                      │
│  ┌──────────────────┐  HTTP   ┌──────────────────┐  │
│  │  OpenClaw         │ -----> │  Deployer         │  │
│  │  Container        │        │  (Flask sidecar)  │  │
│  │                   │        │                   │  │
│  │  - Opus + Haiku   │        │  - Docker socket  │  │
│  │  - Writes code    │        │  - Runs scripts   │  │
│  │  - NO Docker      │        │  - Builds images  │  │
│  │    access          │        │  - Starts apps    │  │
│  └──────────────────┘        └──────────────────┘  │
│         │                           │               │
│         ▼                           ▼               │
│    apps/ (shared volume)     Docker Daemon (host)   │
└──────────────────────────────────────────────────────┘
                                      │
                                      ▼
                              App Containers + Traefik
                                      │
                                      ▼
                              https://app.yourdomain.com
```

**OpenClaw has ZERO Docker access.** It writes code to a shared `apps/` volume and calls the deployer sidecar via HTTP. The deployer is the only container with the Docker socket -- and it only exposes 4 whitelisted operations.

### The Full Picture

```
You (WhatsApp): "Create a SIP Calculator application"
  │
  ▼
Opus (Architect) ── thinks, plans, decides
  │
  ├─ Opus asks you via WhatsApp: "Should it have graphs?
  │   Monthly/yearly projections? What currency?"
  │
  ├─ You reply: "Yes graphs, INR, monthly and lumpsum both"
  │
  ├─ Opus creates the full plan:
  │   1. React frontend with Recharts for graphs
  │   2. Calculate SIP + lumpsum with step-up
  │   3. INR formatting, mobile-first design
  │   4. Dockerfile with nginx
  │   5. Deploy to sip.yourdomain.com
  │
  ├─ Opus spawns Haiku sub-agents with small tasks:
  │
  │   ┌─ Haiku #1: "Write the SIP calculation logic in utils/sip.ts"
  │   ├─ Haiku #2: "Write the React components for the calculator form"
  │   ├─ Haiku #3: "Write the chart component using Recharts"
  │   ├─ Haiku #4: "Create the Dockerfile"
  │   └─ Haiku #5: "Call deployer API: POST /deploy {sip-calculator, 80}"
  │
  ├─ Opus reviews the results from each sub-agent
  │
  ▼
You (WhatsApp): "Your SIP Calculator is live at https://sip.yourdomain.com"
```

### What Each Model Does

| Model | Role | What It Does | Cost |
|-------|------|-------------|------|
| **Opus 4.6** | Architect | Talks to you, plans the app, picks the tech stack, breaks work into small tasks, reviews results, handles errors | $15/1M tokens |
| **Haiku 3.5** | Developer (x many) | Writes code files, creates Dockerfiles, calls deployer API -- one small task per sub-agent | $0.25/1M tokens |

Opus is the senior engineer who plans and reviews. Haiku sub-agents are junior devs who each get one clear, small task.

### Why Small Tasks Per Sub-Agent

Opus doesn't give Haiku a vague instruction like "build the app." It breaks work into atomic tasks:

- "Write `src/utils/sip.ts` with functions `calculateSIP(monthly, rate, years)` and `calculateLumpsum(amount, rate, years)` that return month-by-month arrays"
- "Write `src/components/SIPForm.tsx` - a form with inputs for monthly amount, expected return %, and time period. Use the `calculateSIP` function from `utils/sip.ts`"
- "Create a `Dockerfile` that builds the React app and serves it with nginx on port 80"
- "Call the deployer API: `curl -s -X POST http://deployer:5000/deploy -H 'Content-Type: application/json' -d '{\"app_name\": \"sip-calculator\", \"port\": 80}'`"

Each Haiku sub-agent gets exactly what to do, what files to create, and what the output should look like. This keeps Haiku fast, cheap, and accurate.

### The Build-Deploy Pipeline

```
1. PLAN        Opus decides tech stack, architecture, file structure
2. CLARIFY     Opus asks user for missing requirements (via WhatsApp)
3. BUILD       Haiku sub-agents write code (parallel where possible)
4. DOCKERIZE   Haiku creates Dockerfile
5. DEPLOY      Haiku calls deployer API (creates DNS, builds image, starts container)
6. VERIFY      Deployer checks the container is running
7. DELIVER     Opus sends you the live URL on WhatsApp
```

### Security Model

OpenClaw runs in complete isolation. It has no Docker socket, no Docker CLI, and no host access.

| What | How |
|------|-----|
| Writing app code | Haiku writes files into `~/clawbot/apps/<app-name>/` |
| Creating Dockerfiles | Haiku writes the Dockerfile as part of the app |
| Building & deploying | Haiku calls `POST http://deployer:5000/deploy` |
| Creating DNS records | The deployer's script calls Cloudflare API |
| Stopping/managing apps | Via deployer API (`/stop`, `/status`, `/logs`) |

| Resource | OpenClaw container | Deployer sidecar |
|----------|-------------------|------------------|
| Docker socket | NONE | mounted |
| apps/ | read-write (writes code) | read-write (builds images) |
| skills/ | read-only | none |
| AGENTS.md | read-only | none |
| shared/logs/ | read-write | read-write |
| config/.env | NONE | read-only |
| deploy-scripts/ | NONE | read-only, executable |
| Host filesystem | NONE | NONE |
| Network | internal Docker network | internal Docker network |

## Directory Structure

```
~/openclaw/                         # This repo
├── setup.sh                        # One-command setup (orchestrator)
├── setup/                          # Setup sub-scripts
│   ├── check-prereqs.sh            # Verify Docker, jq, git, config
│   ├── build-images.sh             # Clone OpenClaw, build Docker images
│   ├── generate-compose.sh         # Create dirs, network, docker-compose.yml
│   ├── configure.sh                # Opus+Haiku model config
│   └── start.sh                    # Start gateway + deployer
├── README.md                       # This file
├── .gitignore                      # Protects secrets
├── docker-compose.yml              # Generated by setup (gitignored)
├── .openclaw/                      # OpenClaw runtime (gitignored)
├── .openclaw-src/                  # Cloned OpenClaw repo (gitignored)
│
├── config/                         # Config templates
│   └── openclaw.json               # Opus + Haiku model routing template
│
├── openclaw-workspace/             # OpenClaw's workspace
│   ├── skills/                     # OpenClaw skills
│   │   ├── app-builder/
│   │   ├── app-deployer/
│   │   └── app-manager/
│   └── AGENTS.md                   # Opus/Haiku workflow instructions
│
├── deployer-workspace/             # Deployer's workspace
│   ├── config/
│   │   ├── .env.example            # Template for Cloudflare secrets
│   │   └── .env                    # Your actual secrets (gitignored)
│   └── deploy-scripts/             # Run inside the deployer container
│       ├── deploy-app.sh           # Build + DNS + deploy
│       ├── stop-app.sh             # Stop and remove an app
│       ├── status-app.sh           # List running apps
│       └── logs-app.sh             # Tail logs for an app
│
├── deployer/                       # Flask sidecar (Docker access)
│   ├── app.py                      # Flask API (4 endpoints)
│   ├── Dockerfile                  # Sidecar image
│   └── requirements.txt            # Flask dependency
│
├── apps/                           # Shared: Built apps live here (gitignored)
│   └── sip-calculator/
│       ├── src/                    # Application source code
│       ├── Dockerfile              # Created by Haiku
│       ├── docker-compose.yml      # Created by deploy script
│       └── data/                   # Persistent app data
│
└── shared/                         # Shared: logs and temp files (gitignored)
    └── logs/                       # Deploy logs
```

## Installation

### 1. Clone this repo

```bash
git clone <your-repo-url> ~/openclaw
cd ~/openclaw
```

### 2. Configure your secrets

```bash
cp deployer-workspace/config/.env.example deployer-workspace/config/.env
nano deployer-workspace/config/.env
```

Fill in:
- `CF_API_TOKEN` - Your Cloudflare API token (needs Zone.Zone Read + Zone.DNS Edit permissions)
- `CF_BASE_DOMAIN` - Your domain (e.g., `yourdomain.com`). Zone ID is looked up automatically.
- `ALLOWED_ZONE_SUFFIX` - Usually same as `CF_BASE_DOMAIN`. Prevents deploying to arbitrary domains.

### 3. Run setup

```bash
chmod +x setup.sh
./setup.sh
```

The setup script will:
1. Check that Docker, docker compose, jq, and git are available
2. Clone the [OpenClaw repo](https://github.com/openclaw/openclaw) and build the Docker image
3. Build the deployer sidecar image
4. Create the `openclaw_network` Docker network
5. Generate a `docker-compose.yml` with OpenClaw + deployer sidecar
6. **Pause for you** to run onboarding in a new terminal:
   ```
   docker compose run --rm openclaw-cli onboard --no-install-daemon
   ```
   - Choose **Anthropic** as your provider
   - Authenticate with `claude setup-token`
   - Choose **WhatsApp** as your channel
   - **Scan the QR code** with your phone
7. Copy the Opus+Haiku config
8. Start the OpenClaw gateway + deployer sidecar

### 4. Verify

Send a WhatsApp message:
```
Hello! What can you help me build?
```

## Usage Examples

### Build a complete app from scratch

```
Create a SIP Calculator application with graphs and INR support
```

Opus will ask clarifying questions, plan the tech stack, spawn Haiku developers to write code, dockerize it, and deploy it via the deployer API. You get a live URL.

### Build with specific tech

```
Build me a todo app using Go and HTMX, deploy it on port 8090
```

### Iterate on a deployed app

```
Add a dark mode toggle to the SIP calculator
```

Opus sees the app already exists in `apps/sip-calculator/`, plans the change, spawns Haiku to modify the code, and calls the deployer API to rebuild and redeploy.

### Check what's running

```
What apps are running?
```

### Stop an app

```
Stop the sip-calculator app
```

### View logs

```
Show me the logs for sip-calculator
```

## OpenClaw Configuration

The key configuration in `config/openclaw.json`:

```json5
{
  agents: {
    defaults: {
      // Opus as the primary model - handles all conversation and planning
      model: {
        primary: "anthropic/claude-opus-4-6",
      },
      // Haiku for sub-agents - the developers that write code and deploy
      subagents: {
        model: "anthropic/claude-haiku-3-5",
        maxConcurrent: 4,
      },
      // Point workspace to this repo
      workspace: "~/clawbot",
    },
  },

  // WhatsApp channel
  channels: {
    whatsapp: {
      allowFrom: ["+YOUR_NUMBER"],
    },
  },
}
```

This uses OpenClaw's native [sub-agent system](https://docs.openclaw.ai/tools/subagents):

- **Opus** handles your WhatsApp conversation directly (planning, questions, final reply)
- When Opus needs work done, it calls `sessions_spawn` which creates a **Haiku** sub-agent
- Each sub-agent gets one focused task, executes it, and reports back
- Opus can spawn multiple sub-agents in parallel for independent tasks
- Sub-agents can read/write files and run bash commands within the workspace

## How the Opus-Haiku Handoff Works

When you say "Create a SIP Calculator":

**Turn 1 - Opus (conversation)**
Opus reads your message, decides it needs more info, and replies on WhatsApp asking about features, design preferences, etc.

**Turn 2 - Opus (planning)**
After your reply, Opus creates a build plan and spawns sub-agents:

```
sessions_spawn: {
  task: "Create file ~/clawbot/apps/sip-calculator/src/utils/sip.ts with SIP and lumpsum calculation functions...",
  model: "anthropic/claude-haiku-3-5"
}

sessions_spawn: {
  task: "Create file ~/clawbot/apps/sip-calculator/src/components/SIPForm.tsx...",
  model: "anthropic/claude-haiku-3-5"
}
```

**Turns 3-7 - Haiku sub-agents (execution)**
Each sub-agent writes its assigned files using OpenClaw's file write tools, then announces completion back to Opus.

**Turn 8 - Haiku sub-agent (deploy)**
```
sessions_spawn: {
  task: "Deploy the app: curl -s -X POST http://deployer:5000/deploy -H 'Content-Type: application/json' -d '{\"app_name\": \"sip-calculator\", \"port\": 80}'. Report the full response.",
  model: "anthropic/claude-haiku-3-5"
}
```

**Turn 9 - Opus (delivery)**
Opus collects all results, verifies deployment succeeded, and messages you on WhatsApp with the live URL.

## Sharing This Setup

### In Git (safe to share)

- `config/openclaw.json` - Model routing config
- `config/.env.example` - Template for secrets
- `skills/` - All custom skills
- `deploy-scripts/` - Deploy scripts
- `deployer/` - Flask sidecar source
- `AGENTS.md` - Agent instructions
- `setup.sh` - Setup automation

### NOT in Git (secrets / runtime)

- `config/.env` - Your actual API tokens
- `apps/` - Built application code and data
- `shared/` - Logs
- `.openclaw/` - OpenClaw runtime, WhatsApp session, credentials
- `.openclaw-src/` - Cloned OpenClaw source code
- `docker-compose.yml` - Generated compose file (contains gateway token)

### For someone else to use this

```bash
git clone <your-repo-url> ~/openclaw
cd ~/openclaw
cp config/.env.example config/.env
nano config/.env   # fill in their own Cloudflare credentials + domain
./setup.sh         # installs OpenClaw, scan their own WhatsApp QR code
```

They get the same Opus+Haiku app-building pipeline on their own machine with their own domain.

## Integrating with Your Existing Traefik

Your Traefik's `docker-compose.yml` needs to join the `openclaw_network`:

```yaml
networks:
  openclaw_network:
    external: true
```

Deploy scripts create containers with Traefik labels:
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.${APP_NAME}.rule=Host(`${APP_NAME}.${CF_BASE_DOMAIN}`)"
  - "traefik.http.routers.${APP_NAME}.tls.certresolver=letsencrypt"
```

Traefik auto-discovers new apps and provisions HTTPS certificates.

## Troubleshooting

### OpenClaw not responding on WhatsApp

```bash
docker compose logs -f openclaw-gateway    # View gateway logs
docker compose restart openclaw-gateway    # Restart gateway
```

### WhatsApp disconnected

```bash
docker compose run --rm openclaw-cli channels login  # Re-scan QR code
```

### Deployer not responding

```bash
docker compose logs -f deployer            # View deployer logs
docker compose restart deployer            # Restart deployer

# Test deployer health
docker compose exec openclaw-gateway curl -s http://deployer:5000/health
```

### App build failed

```bash
# Check what Haiku produced
ls ~/openclaw/apps/<app-name>/

# Check deploy logs
cat ~/openclaw/shared/logs/deploy-*.log

# Test deployer API directly
docker compose exec openclaw-gateway curl -s -X POST http://deployer:5000/deploy \
  -H "Content-Type: application/json" \
  -d '{"app_name": "test-app", "port": 3000}'
```

### Token expired

```bash
# Re-authenticate inside the container
docker compose run --rm openclaw-cli models status
```

## Cost Estimates

Building a full app involves more tokens than a simple deploy because Haiku is writing code. But Haiku is $0.25/1M tokens, so it's still cheap.

| Action | Opus tokens | Haiku tokens | Estimated cost |
|--------|-------------|--------------|----------------|
| Build + deploy a simple app | ~3,000 | ~50,000 | ~$0.06 |
| Build + deploy a complex app | ~5,000 | ~150,000 | ~$0.12 |
| Iterate on existing app | ~2,000 | ~30,000 | ~$0.04 |
| Check status | 0 | ~1,000 | ~$0.0003 |
| Stop an app | ~1,000 | ~2,000 | ~$0.02 |
| Conversation (no build) | ~2,000 | 0 | ~$0.03 |

Monthly estimate for light usage (2-3 app builds/week + daily checks): **~$15-30/month**

## Links

- [OpenClaw](https://openclaw.ai) - The platform this runs on
- [OpenClaw Docs](https://docs.openclaw.ai) - Full documentation
- [OpenClaw GitHub](https://github.com/openclaw/openclaw) - Source code
- [Skills Docs](https://docs.openclaw.ai/tools/skills) - How skills work
- [Sub-Agents Docs](https://docs.openclaw.ai/tools/subagents) - How the Opus+Haiku model works
- [ClawHub](https://clawhub.com) - Community skills

## License

MIT
