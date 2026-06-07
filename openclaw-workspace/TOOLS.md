# TOOLS.md - Setup Notes

## Deployer - CRITICAL Path Info

⚠️ **The deployer container mounts `/home/node/.openclaw/workspace/apps/` as `/workspace/apps/`.**

- **ALWAYS write app files to:** `/home/node/.openclaw/workspace/apps/<app-name>/`
- When spawning sub-agents, tell them to write files to `/home/node/.openclaw/workspace/apps/<app-name>/`

## Token Management

**What costs money:**
- Opus (you) processes the full context window on every turn — system prompt + all skills + conversation history
- Sub-agents (Haiku) each start their own context — keep spawn prompts tight and focused
- Long conversation history accumulates fast; compaction is set to `safeguard` mode (auto-compacts near limit)

**Keep costs down:**

- **Reset sessions between unrelated tasks.** `/new` or `/reset` clears the conversation. Stale history is pure waste.
- **Keep memory files lean.** Only write to `memory/YYYY-MM-DD.md` when you learn something genuinely new or permanent. Don't re-document things already covered in skills or AGENTS.md.
- **Keep sub-agent prompts tight.** Each sub-agent pays for its own context. One focused task per agent, not walls of background info.
- **Sub-agents should return summaries, not raw output.** Ask Haiku to report "success/failure + key info" — not full file contents or log dumps.
- **Don't add always-loaded skills unless truly needed.** Every `"always": true` skill is injected into every session. Only 3 exist right now (app-builder, app-deployer, app-manager) — keep it that way.
- **Avoid reading large files into context.** If you need to check a file exists or find a specific value, use targeted grep/head rather than reading the whole file.

**Compaction behavior (auto):**
- Mode: `safeguard` — automatically compacts when approaching the context limit
- When compaction fires: the conversation history is summarized and replaced with a compact version
- Before it fires: write anything important to `memory/YYYY-MM-DD.md` so it survives the compaction
