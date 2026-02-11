# OpenClaw Pi Builder

Build and deploy full applications on your Raspberry Pi by describing them on WhatsApp.

Say **"Create a SIP Calculator application"** and OpenClaw will plan it, build it, dockerize it, deploy it, and hand you a live URL -- all from your phone.

Uses **Opus as the architect** (planning, tech decisions, task breakdown, user communication) and **Haiku sub-agents as developers** (writing code, creating Dockerfiles, testing, deploying) through OpenClaw's native sub-agent system.

## What This Is

This is a shareable configuration layer on top of [OpenClaw](https://openclaw.ai), the open-source personal AI assistant. It turns OpenClaw into an application factory for your Pi.

It provides:
- **Custom skills** that teach OpenClaw how to build, dockerize, and deploy full applications
- **Deploy scripts** that handle Docker and Cloudflare DNS
- **OpenClaw config** with Opus (architect) + Haiku (developers) model routing
- **AGENTS.md** instructions that define the build-and-deploy workflow
- **A setup script** that wires everything together

## Prerequisites

1. **A Raspberry Pi** (or any Linux machine) with Docker installed
2. **Traefik** already running as a reverse proxy
3. **Cloudflare** account with API access for your domain
4. **Node.js >= 22** installed
5. **A Claude Pro/Max subscription** (for Anthropic auth via `claude setup-token`)

## How It Works

### The Full Picture

```
You (WhatsApp): "Create a SIP Calculator application"
  │
  ▼
Opus (Architect) ─── thinks, plans, decides
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
  │   ├─ Haiku #4: "Create the Dockerfile and docker-compose.yml"
  │   └─ Haiku #5: "Run deploy-app.sh sip-calculator 3000"
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
| **Haiku 3.5** | Developer (x many) | Writes code files, creates Dockerfiles, runs tests, calls deploy scripts -- one small task per sub-agent | $0.25/1M tokens |

Opus is the senior engineer who plans and reviews. Haiku sub-agents are junior devs who each get one clear, small task.

### Why Small Tasks Per Sub-Agent

Opus doesn't give Haiku a vague instruction like "build the app." It breaks work into atomic tasks:

- "Write `src/utils/sip.ts` with functions `calculateSIP(monthly, rate, years)` and `calculateLumpsum(amount, rate, years)` that return month-by-month arrays"
- "Write `src/components/SIPForm.tsx` - a form with inputs for monthly amount, expected return %, and time period. Use the `calculateSIP` function from `utils/sip.ts`"
- "Create a `Dockerfile` that builds the React app and serves it with nginx on port 80"
- "Run `bash ~/clawbot/deploy-scripts/deploy-app.sh sip-calculator 3000`"

Each Haiku sub-agent gets exactly what to do, what files to create, and what the output should look like. This keeps Haiku fast, cheap, and accurate.

### The Build-Deploy Pipeline

```
1. PLAN        Opus decides tech stack, architecture, file structure
2. CLARIFY     Opus asks user for missing requirements (via WhatsApp)
3. BUILD       Haiku sub-agents write code (parallel where possible)
4. DOCKERIZE   Haiku creates Dockerfile + docker-compose.yml
5. DEPLOY      Haiku calls deploy-app.sh (creates DNS, starts container)
6. VERIFY      Haiku checks the app is responding
7. DELIVER     Opus sends you the live URL on WhatsApp
```

### Security Model

The actual infrastructure work (Docker, Cloudflare DNS) happens only through deploy scripts that run as your user. OpenClaw writes application code and calls scripts -- it doesn't manage Docker directly.

| What | How |
|------|-----|
| Writing app code | Haiku writes files into `~/clawbot/apps/<app-name>/` |
| Creating Dockerfiles | Haiku writes the Dockerfile as part of the app |
| Building & deploying | Haiku calls `deploy-scripts/deploy-app.sh` which runs Docker |
| Creating DNS records | The deploy script calls Cloudflare API |
| Stopping/managing apps | Via `deploy-scripts/stop-app.sh` and `status-app.sh` |

## Directory Structure

```
~/clawbot/                          # OpenClaw workspace (this repo)
├── setup.sh                        # One-command setup
├── README.md                       # This file
├── .gitignore                      # Protects secrets
├── AGENTS.md                       # Opus/Haiku workflow instructions
│
├── config/
│   ├── openclaw.json               # Opus + Haiku model routing
│   ├── .env.example                # Template for secrets (shareable)
│   └── .env                        # Your actual secrets (gitignored)
│
├── skills/                         # OpenClaw workspace skills
│   ├── app-builder/
│   │   └── SKILL.md                # Teaches Opus how to plan and build apps
│   ├── app-deployer/
│   │   └── SKILL.md                # Teaches Haiku how to deploy via scripts
│   └── app-manager/
│       └── SKILL.md                # Status checks, stop, logs
│
├── deploy-scripts/                 # The only thing that touches Docker
│   ├── deploy-app.sh               # Build + DNS + deploy
│   ├── stop-app.sh                 # Stop and remove an app
│   ├── status-app.sh               # List running apps
│   └── logs-app.sh                 # Tail logs for an app
│
├── apps/                           # Built apps live here (gitignored)
│   └── sip-calculator/
│       ├── src/                    # Application source code
│       ├── Dockerfile              # Created by Haiku
│       ├── docker-compose.yml      # Created by deploy script
│       └── data/                   # Persistent app data
│
└── shared/                         # Shared across apps (gitignored)
    ├── logs/                       # Deploy logs
    └── templates/                  # Reusable boilerplate (optional)
```

## Installation

### 1. Clone this repo

```bash
git clone <your-repo-url> ~/clawbot
cd ~/clawbot
```

### 2. Configure your secrets

```bash
cp config/.env.example config/.env
nano config/.env
```

Fill in:
- `CF_API_TOKEN` - Your Cloudflare API token
- `CF_ZONE_ID` - Your domain's zone ID
- `CF_BASE_DOMAIN` - Your domain (e.g., `yourdomain.com`). Subdomains CNAME to this.

### 3. Run setup

```bash
chmod +x setup.sh
./setup.sh
```

The setup script will:
1. Check that Docker, Node.js >= 22, and Traefik are running
2. Install OpenClaw globally (`npm i -g openclaw`)
3. **Pause for you** to run `openclaw onboard`:
   - Choose **Anthropic** as your provider
   - Authenticate with `claude setup-token`
   - Choose **WhatsApp** as your channel
   - **Scan the QR code** with your phone
4. Copy `config/openclaw.json` into `~/.openclaw/openclaw.json`
5. Set the OpenClaw workspace to `~/clawbot/`
6. Create the `openclaw_network` Docker network
7. Create `apps/` and `shared/` directories

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

Opus will ask clarifying questions, plan the tech stack, spawn Haiku developers to write code, dockerize it, and deploy it. You get a live URL.

### Build with specific tech

```
Build me a todo app using Go and HTMX, deploy it on port 8090
```

### Iterate on a deployed app

```
Add a dark mode toggle to the SIP calculator
```

Opus sees the app already exists in `apps/sip-calculator/`, plans the change, spawns Haiku to modify the code, rebuild, and redeploy.

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
  task: "Run: bash ~/clawbot/deploy-scripts/deploy-app.sh sip-calculator 3000. Report the output.",
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
- `AGENTS.md` - Agent instructions
- `setup.sh` - Setup automation

### NOT in Git (secrets / runtime)

- `config/.env` - Your actual API tokens
- `apps/` - Built application code and data
- `shared/` - Logs
- `~/.openclaw/` - OpenClaw runtime, WhatsApp session, credentials

### For someone else to use this

```bash
git clone <your-repo-url> ~/clawbot
cd ~/clawbot
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
openclaw status          # Check gateway status
openclaw doctor          # Diagnose issues
openclaw logs            # View gateway logs
```

### WhatsApp disconnected

```bash
openclaw channels login  # Re-scan QR code
```

### App build failed

```bash
# Check what Haiku produced
ls ~/clawbot/apps/<app-name>/

# Check deploy logs
cat ~/clawbot/shared/logs/deploy-*.log

# Test deploy script manually
bash ~/clawbot/deploy-scripts/deploy-app.sh test-app 3000
```

### Token expired

```bash
claude setup-token       # Re-authenticate with Anthropic
openclaw models status   # Verify auth is working
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
