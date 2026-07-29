#!/usr/bin/env python3
"""Merge personal env settings into ~/.claude/settings.json without clobbering other keys.

Runs on every workspace start, so it only ever updates the keys below — `enabledPlugins`
and anything Claude Code writes itself is left alone.

POSTHOG_API_KEY is the public, write-only ingest key for the "PostHog App + Website"
project, not a secret. Anything actually sensitive belongs in `hogli devbox:secret:set`.
"""

import json
import pathlib

ENV = {
    # Capture each Claude Code session as PostHog LLM Analytics events.
    "POSTHOG_LLMA_CC_ENABLED": "true",
    "POSTHOG_API_KEY": "sTMFPsFhdP1Ssg",
    "POSTHOG_HOST": "https://us.i.posthog.com",
    # Let these PostHog MCP exec-domain tools skip the permission prompt.
    "POSTHOG_MCP_EXEC_GATE_ALLOW": (
        "llma-skill-*,alert-create,alert-update,insight-create,"
        "insight-update,cdp-functions-partial-update"
    ),
}

path = pathlib.Path.home() / ".claude" / "settings.json"
path.parent.mkdir(parents=True, exist_ok=True)

try:
    settings = json.loads(path.read_text())
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

env = settings.setdefault("env", {})
if all(env.get(k) == v for k, v in ENV.items()):
    raise SystemExit(0)

env.update(ENV)
path.write_text(json.dumps(settings, indent=2) + "\n")
print("coder-dotfiles: updated ~/.claude/settings.json env block")
