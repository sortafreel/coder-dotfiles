#!/usr/bin/env python3
"""Merge personal env settings and the cmux notification hooks into ~/.claude/settings.json.

Runs on every workspace start, so it only ever updates the keys below — `enabledPlugins`,
other hooks, and anything Claude Code writes itself is left alone.

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

# Desktop notification in cmux when a session finishes, fails, or waits for an answer.
NOTIFY_SCRIPT = "cmux-notify.sh"
NOTIFY_HOOK = {"type": "command", "command": f"$HOME/.claude/hooks/{NOTIFY_SCRIPT}", "timeout": 10}
HOOKS = {
    "Stop": {"hooks": [NOTIFY_HOOK]},
    "StopFailure": {"hooks": [NOTIFY_HOOK]},
    # An idle prompt is left out: Stop already reported that turn.
    "Notification": {
        "matcher": "permission_prompt|elicitation_dialog|elicitation_url_dialog",
        "hooks": [NOTIFY_HOOK],
    },
    "PreToolUse": {"matcher": "AskUserQuestion", "hooks": [NOTIFY_HOOK]},
}


def merge_hooks(hooks: dict) -> None:
    """Replace our hook in each event and keep every other hook."""
    for event, ours in HOOKS.items():
        kept = []
        for group in hooks.get(event, []):
            others = [h for h in group.get("hooks", []) if NOTIFY_SCRIPT not in h.get("command", "")]
            if others:
                kept.append({**group, "hooks": others})
        hooks[event] = [*kept, ours]


path = pathlib.Path.home() / ".claude" / "settings.json"
path.parent.mkdir(parents=True, exist_ok=True)

try:
    settings = json.loads(path.read_text())
except (FileNotFoundError, json.JSONDecodeError):
    settings = {}

before = json.dumps(settings)
settings.setdefault("env", {}).update(ENV)
merge_hooks(settings.setdefault("hooks", {}))
if json.dumps(settings) == before:
    raise SystemExit(0)

path.write_text(json.dumps(settings, indent=2) + "\n")
print("coder-dotfiles: updated ~/.claude/settings.json (env block, cmux notification hooks)")
