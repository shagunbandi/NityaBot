---
name: app-builder
description: Plan and build full applications from user descriptions. Handles tech stack decisions, code generation via sub-agents, Dockerfile creation, and deployment orchestration via the Deployer API.
metadata: {"openclaw":{"always":true}}
---

# App Builder Skill

You can build complete applications from scratch based on user descriptions.

## When to use this skill

When the user asks you to:
- Create, build, or make an application/app/website/tool
- "I want a ..." followed by a description of software
- "Build me ..." or "Make me ..."

## Workflow

1. **Clarify**: Ask the user 3-5 short questions about requirements (features, design, tech preferences). Skip if the request is already clear.

2. **Plan**: Choose the tech stack and plan the file structure. Tell the user your plan in one short message.

3. **Build**: Spawn Haiku sub-agents via `sessions_spawn` with atomic tasks. Each sub-agent writes 1-3 specific files to `~/clawbot/apps/<app-name>/`. Spawn independent tasks in parallel.

4. **Dockerize**: Spawn a sub-agent to create a `Dockerfile` in the app directory. Use multi-stage builds for compiled apps. Serve web apps via nginx.

5. **Deploy**: Spawn a sub-agent to call the Deployer API:
   ```bash
   curl -s -X POST http://deployer:5000/deploy \
     -H "Content-Type: application/json" \
     -d '{"app_name": "<app-name>", "port": <port>}'
   ```
   **NEVER run Docker commands directly. You have no Docker access.**

6. **Deliver**: Tell the user the live URL from the deployer's response.

## Task breakdown guidelines

Each sub-agent task must include:
- **Exact file path(s)** to create (e.g., `~/clawbot/apps/my-app/src/utils/calc.ts`)
- **What the code should do** (function names, inputs, outputs)
- **Dependencies** on other files (import paths, interfaces)

Keep tasks small. A sub-agent writing 500 lines is too much. Split into multiple sub-agents.

## Tech stack preferences

- **Simple web apps**: Static HTML/CSS/JS or React + Vite, served via nginx
- **Apps with charts**: React + Recharts or Chart.js
- **APIs/backends**: Node.js (Express/Fastify) or Go
- **Databases**: SQLite for simple apps, PostgreSQL for complex ones
- **Styling**: Tailwind CSS preferred, or simple CSS

## Example sub-agent task

```
Create the file ~/clawbot/apps/sip-calc/src/utils/sip.ts

This file should export two functions:

1. calculateSIP(monthlyAmount: number, annualRate: number, years: number)
   - Returns an array of objects: { month: number, invested: number, value: number }
   - Calculate compound interest monthly
   - invested = monthlyAmount * month
   - value = running compound calculation

2. calculateLumpsum(amount: number, annualRate: number, years: number)
   - Returns an array of objects: { month: number, invested: number, value: number }
   - invested is always the initial amount
   - value compounds monthly

Use TypeScript. No external dependencies.
```

## Example deploy sub-agent task

```
The app code is ready in ~/clawbot/apps/sip-calc/ with a Dockerfile.

Deploy it by running:
  curl -s -X POST http://deployer:5000/deploy \
    -H "Content-Type: application/json" \
    -d '{"app_name": "sip-calc", "port": 80}'

Report the full JSON response back to me.
If it fails, include the "output" field so I can diagnose the issue.
```
