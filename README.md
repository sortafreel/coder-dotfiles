# coder-dotfiles

Personal customizations for PostHog Coder devboxes. Coder clones this repo and runs `install.sh` on every workspace start.

Wired up once via:

```bash
hogli devbox:setup --configure-dotfiles
```

## What it does

- Clones the PostHog repo landscape (`clone-repos.sh`, backgrounded, shallow, idempotent)
- Adds shell aliases (`gcm`, `gcmm`, `gpp`, `slim`) via a managed block in `~/.bash_aliases`
- Selects the slim hogli dev stack for signals and reviewhog work (`posthog-slim-stack.sh`, backgrounded). `hogli nuke` resets the selection; run `slim` to re-apply
- Reapplies git commit-signing config from the `POSTHOG_GIT_SIGNING_KEY` secret if the template's boot-time bootstrap raced and left the box unconfigured
- Merges an `env` block into `~/.claude/settings.json` (`claude-settings.py`) — LLM Analytics session capture and the PostHog MCP exec allow-list
- Installs `~/.claude/skills/` from `claude/skills/` — currently the `phs` skills-store bridge
- Installs the Claude Code marketplace and plugins (`install-claude-plugins.sh`, backgrounded): `posthog` and `slack` user-scoped, `typescript-lsp` project-scoped in `~/posthog`

Logs: `~/.coder-dotfiles-clone.log`, `~/.coder-dotfiles-plugins.log`, and `~/.coder-dotfiles-slim-stack.log`.

## Still manual on a new box

- **MCP OAuth.** After the plugins install, `claude mcp list` shows `! Needs authentication` — the posthog and slack servers use OAuth. Auth via `/mcp`, or copy the `mcpOAuth` block of `~/.claude/.credentials.json` from a box that is already authed (that block only; account refresh tokens rotate, so sharing `claudeAiOauth` invalidates the other boxes).
- **Claude Code login.** If the `CLAUDE_CODE_OAUTH_TOKEN` secret has gone stale, a fresh box 401s even though the env var is set. `/login` once on the box, or refresh the secret with `claude setup-token` + `hogli devbox:setup --configure-claude`.

See `/phs alex-lebedev-devbox` for the full bring-up checklist.

## Rules

- Keep `install.sh` idempotent — it runs on every start
- No secrets in this repo (it may be public); secrets go in `hogli devbox:secret:set`. The `POSTHOG_API_KEY` in `claude-settings.py` is a public write-only ingest key, not a secret
- Don't duplicate what the platform already handles: git identity, Claude token, gh auth
- Anything slow or network-bound gets backgrounded from `install.sh` so workspace start isn't blocked
- Coder runs dotfiles before the template's bootstrap finishes (claude install, `~/posthog` pull). Background scripts poll for their prerequisite via `wait-for.sh` instead of assuming it exists
