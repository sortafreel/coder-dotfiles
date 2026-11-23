#!/usr/bin/env python3
"""Turn on cmux notifications for Codex in ~/.codex/config.toml.

Sets single keys in place and leaves the rest of the file alone. A managed block
would not work here: Codex adds its own keys to the same `[tui]` table.

Codex hooks are not used. Codex asks to review every new hook at startup, on each box.
"""

import json
import os
import pathlib
import re
import tomllib

NOTIFY_SCRIPT = "cmux-notify.sh"

# (table, key, value). `notify` only reports a finished turn, so Codex's own notices
# cover the times it waits for an answer. Inside tmux Codex detects neither OSC 9
# support nor focus changes, so both are set by hand.
WANTED = [
    ("", "notify", [str(pathlib.Path.home() / ".claude" / "hooks" / NOTIFY_SCRIPT), "codex"]),
    ("tui", "notifications", ["approval-requested", "plan-mode-prompt", "async-question"]),
    ("tui", "notification_method", "osc9"),
    ("tui", "notification_condition", "always"),
]

ANY_HEADER = re.compile(r"^[ \t]*\[")


def lookup(config: dict, table: str, key: str):
    return (config.get(table, {}) if table else config).get(key)


def set_key(text: str, table: str, key: str, value) -> str:
    lines = text.splitlines()
    assignment = f"{key} = {json.dumps(value)}"

    start = 0
    if table:
        header = re.compile(rf"^[ \t]*\[{re.escape(table)}\][ \t]*(#.*)?$")
        start = next((i + 1 for i, line in enumerate(lines) if header.match(line)), None)
        if start is None:
            if lines and lines[-1].strip():
                lines.append("")
            lines += [f"[{table}]", assignment]
            return "\n".join(lines) + "\n"
    end = next((i for i in range(start, len(lines)) if ANY_HEADER.match(lines[i])), len(lines))

    existing = re.compile(rf"^[ \t]*{re.escape(key)}[ \t]*=")
    at = next((i for i in range(start, end) if existing.match(lines[i])), None)
    if at is None:
        after_last_key = next((i + 1 for i in range(end - 1, start - 1, -1) if lines[i].strip()), start)
        lines.insert(after_last_key, assignment)
    else:
        lines[at] = assignment
    return "\n".join(lines) + "\n"


path = pathlib.Path(os.environ.get("CODEX_HOME") or pathlib.Path.home() / ".codex") / "config.toml"
try:
    text = path.read_text()
except FileNotFoundError:
    text = ""

try:
    current = tomllib.loads(text)
except tomllib.TOMLDecodeError as error:
    raise SystemExit(f"coder-dotfiles: {path} is not valid TOML ({error}), codex notifications not set")

wanted = WANTED
own_notify = current.get("notify")
if own_notify is not None and NOTIFY_SCRIPT not in json.dumps(own_notify):
    print(f"coder-dotfiles: {path} has its own notify, left alone")
    wanted = [item for item in WANTED if item[1] != "notify"]

new = text
for table, key, value in wanted:
    if lookup(current, table, key) != value:
        new = set_key(new, table, key, value)
if new == text:
    raise SystemExit(0)

# The edit is line-based, so prove the result before it replaces a working config.
try:
    result = tomllib.loads(new)
except tomllib.TOMLDecodeError as error:
    raise SystemExit(f"coder-dotfiles: codex notifications not set, the edit would break {path} ({error})")
if any(lookup(result, table, key) != value for table, key, value in wanted):
    raise SystemExit(f"coder-dotfiles: codex notifications not set, could not place the keys in {path}")

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(new)
print(f"coder-dotfiles: set cmux notifications in {path}")
