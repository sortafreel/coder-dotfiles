#!/usr/bin/env bash
# Install the same user-level agent skills as the laptop (mattpocock/skills, plus find-skills)
# into ~/.claude/skills. Uses the flox env's node by path,
# because activating flox from the dotfiles context would run the heavy on-activate hook.
set -uo pipefail

POSTHOG_DIR="${POSTHOG_DIR:-$HOME/posthog}"
source "$(dirname "${BASH_SOURCE[0]}")/wait-for.sh"

flox_bin() { ls -d "$POSTHOG_DIR"/.flox/run/*/bin 2>/dev/null | head -1; }
have_npx() { [ -n "$(flox_bin)" ] && [ -x "$(flox_bin)/npx" ]; }
wait_for "node in the flox env" 900 have_npx || exit 0
export PATH="$(flox_bin):$PATH"

# Re-installing on every start would download both repos each boot. Refresh by hand with
# `npx skills update -g -y`.
if grep -q '"mattpocock/skills"' "$HOME/.agents/.skill-lock.json" 2>/dev/null; then
  echo "coder-dotfiles: agent skills already installed"
  exit 0
fi

npx -y skills@latest add mattpocock/skills -g -a claude-code -s '*' -y \
  && npx -y skills@latest add vercel-labs/skills -g -a claude-code -s find-skills -y \
  && echo "coder-dotfiles: agent skills installed: $(ls "$HOME/.claude/skills" | wc -l | tr -d ' ') in ~/.claude/skills" \
  || echo "coder-dotfiles: agent skills install FAILED (will retry next start)"
