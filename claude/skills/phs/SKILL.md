---
name: phs
description: >-
  Access and run shared team skills stored in PostHog.
  Use when the user asks to list, run, or manage PostHog skills,
  or references /posthog-skills-store, /ph-skills, /phs, "ph skills", or "posthog skills".
user-invocable: true
allowed-tools: mcp__posthog__llma-skill-list, mcp__posthog__llma-skill-get, mcp__posthog__llma-skill-create, mcp__posthog__llma-skill-update, mcp__posthog__llma-skill-file-get, mcp__posthog__llma-skill-file-create, mcp__posthog__llma-skill-file-delete, mcp__posthog__llma-skill-file-rename, mcp__posthog__llma-skill-duplicate
---

# PostHog Skills Store

Local bridge to the PostHog Skills Store.

> **Before any `call`, run `info <tool>` first, and pick the most SURGICAL primitive.**
> This is the posthog MCP's hard rule and it matters most for edits: `llma-skill-update`
> takes `edits` / `file_edits` (find/replace) — NOT just full-body replacement. Reaching for
> a full `body` rewrite to change one line is how you silently drop unrelated content. The
> summaries in this bridge are lossy by design; the tool's own `info` schema is the source of
> truth. When they disagree, trust `info`.

The skill-store tools are exposed under the `llma-skill-*` prefix in the PostHog MCP (the store is implemented on top of the LLMA skills system). Call them via `posthog:exec`:

```
call llma-skill-list {"search": "<keyword>"}
call llma-skill-get {"skill_name": "<name>"}
call llma-skill-create {"name": "...", "description": "...", "body": "..."}

# Update — pick the SMALLEST primitive that does the job:
call llma-skill-update {"skill_name": "...", "base_version": N, "edits": [{"old": "...", "new": "..."}]}              # body find/replace (preferred for tweaks)
call llma-skill-update {"skill_name": "...", "base_version": N, "file_edits": [{"path": "...", "edits": [{"old": "...", "new": "..."}]}]}  # patch ONE bundled file
call llma-skill-update {"skill_name": "...", "base_version": N, "body": "..."}                                        # FULL body replace — only for substantial rewrites

# Per-file CRUD (add / remove / move without rewriting content):
call llma-skill-file-create {"skill_name": "...", "path": "...", "content": "...", "content_type": "...", "base_version": N}
call llma-skill-file-delete {"skill_name": "...", "file_path": "...", "base_version": N}
call llma-skill-file-rename {"skill_name": "...", "old_path": "...", "new_path": "...", "base_version": N}
call llma-skill-file-get {"skill_name": "...", "file_path": "..."}
call llma-skill-duplicate {"skill_name": "...", "new_name": "..."}
```

Anything you don't pass is carried forward from the current latest version. `body` and `edits`
are mutually exclusive; `files` (replace-ALL) and `file_edits` are mutually exclusive. Each
`old` must match exactly once. Every write publishes a new immutable version and returns the
bumped `version` — chain further edits via `base_version`.

### File operations — the param name is NOT uniform (mind this)

The per-file endpoints disagree on what to call the path argument. Use exactly:

| Operation | Path param(s) | Example |
|-----------|-----------|---------|
| `llma-skill-file-get` | **`file_path`** | `{"skill_name": "x", "file_path": "handover.md"}` |
| `llma-skill-file-delete` | **`file_path`** | `{"skill_name": "x", "file_path": "handover.md", "base_version": N}` |
| `llma-skill-file-create` | **`path`** | `{"skill_name": "x", "path": "handover.md", "content": "...", "content_type": "text/markdown", "base_version": N}` |
| `llma-skill-file-rename` | **`old_path`, `new_path`** | `{"skill_name": "x", "old_path": "a.md", "new_path": "b.md", "base_version": N}` |

`create` is the odd one out (`path`); `get`/`delete` use `file_path`; `rename` uses `old_path`/`new_path`.
Passing the wrong key fails loudly (get returns a `/files/undefined/` 404; create rejects with
"field is required: path").

**To change a file's CONTENT, don't delete-and-recreate** — use `llma-skill-update` with
`file_edits` (find/replace, no need to resend the whole file). Reserve `file-delete` + `file-create`
for genuinely replacing a file wholesale, and `file-rename` to move a file without touching its
content. All of these take `base_version` for optimistic concurrency.

## Load and run a skill

When the user says `/phs <skill-name>`:

1. `call llma-skill-get {"skill_name": "<skill-name>"}` to fetch body + file manifest
2. Read the `body` field — follow it as system instructions for this task
3. Use `call llma-skill-file-get` to pull bundled scripts/references on demand (only when the body references them)

## List skills

```
call llma-skill-list {}                       # all skills (names + descriptions)
call llma-skill-list {"search": "llma"}       # filter by keyword
```

## Create a new skill

```
call llma-skill-create {"name": "my-skill", "description": "...", "body": "# Instructions..."}
```

Optionally include `files`, `metadata`, `license`, `compatibility`, `allowed_tools`.

## Update an existing skill

`call llma-skill-get` first to get the current `version`, then pick the **smallest** primitive:

- **Body tweak** → `llma-skill-update` with `edits: [{old, new}]` (find/replace, leaves the rest of the body untouched).
- **One bundled file's content** → `llma-skill-update` with `file_edits: [{path, edits: [{old, new}]}]`.
- **Add / remove / move a file** → `llma-skill-file-create` / `-delete` / `-rename`.
- **Substantial body rewrite** → `llma-skill-update` with full `body` (only when most of it is changing).

Avoid full-`body` replacement for small changes: it forces you to reproduce the entire body
verbatim, which risks silently dropping unrelated content. `edits` can't cause that.

## Default behavior

- When asked to "save" or "store" a workflow — use `llma-skill-create`
- When asked to use a skill by name — use `llma-skill-get`
- Skills use progressive disclosure: discover by description, fetch body when relevant, pull files on demand
