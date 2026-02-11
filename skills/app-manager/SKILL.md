---
name: app-manager
description: Check status of deployed apps, stop apps, view logs, and manage running applications on the Pi.
metadata: {"openclaw":{"always":true}}
---

# App Manager Skill

Manage applications that are already deployed on the Pi.

## When to use this skill

When the user asks:
- "What apps are running?" / "Show me my apps" / "Status"
- "Stop the blog app" / "Take down analytics"
- "Show me the logs for ..." / "What's wrong with ..."
- "Update/redeploy the ..." (rebuild and deploy again)

## Quick commands

These are lightweight operations. You can run them directly or spawn a quick sub-agent — no need for a full planning cycle.

### Check all apps

```bash
bash ~/clawbot/deploy-scripts/status-app.sh
```

Report the output to the user in a clean format:
```
📋 Your apps:
• sip-calculator — https://sip-calculator.yourdomain.com — running (2 days)
• blog — https://blog.yourdomain.com — running (5 hours)
```

### Check one app

```bash
bash ~/clawbot/deploy-scripts/status-app.sh <app-name>
```

### Stop an app

```bash
bash ~/clawbot/deploy-scripts/stop-app.sh <app-name>
```

Confirm with the user before stopping: "I'll stop the blog app. This will take it offline. OK?"

### View logs

```bash
bash ~/clawbot/deploy-scripts/logs-app.sh <app-name> [lines]
```

Summarize the logs for the user — don't dump raw log output on WhatsApp. Highlight errors or important entries.

### Redeploy / Update

If the user wants to update an existing app:
1. The source code already exists in `~/clawbot/apps/<app-name>/`
2. Spawn sub-agents to make the requested changes to the code
3. Re-run `deploy-app.sh` — it will rebuild the Docker image and restart the container
4. The DNS record already exists, so it just updates the container

### List app source code

To see what an existing app contains:
```bash
ls -la ~/clawbot/apps/<app-name>/
```

This is useful when the user wants to modify an existing app — you can read the current code before planning changes.
