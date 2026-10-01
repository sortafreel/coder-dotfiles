#!/usr/bin/env bash
# Install the Claude Code marketplace and plugins. Backgrounded by install.sh because
# `marketplace add` clones a git repo and each install hits the network.
# Idempotent: every step is guarded, so a re-run on workspace start is a no-op.
set -uo pipefail

export PATH="$HOME/.local/bin:$PATH"
source "$(dirname "${BASH_SOURCE[0]}")/wait-for.sh"
wait_for "claude binary (template installs it after dotfiles start)" 600 test -x "$HOME/.local/bin/claude" || exit 0

MARKETPLACE=claude-plugins-official

if ! claude plugin marketplace list 2>/dev/null | grep -q "$MARKETPLACE"; then
  echo "coder-dotfiles: adding ${MARKETPLACE} marketplace..."
  claude plugin marketplace add "anthropics/${MARKETPLACE}" \
    || { echo "coder-dotfiles: marketplace add FAILED (will retry next start)"; exit 0; }
fi

installed="$(claude plugin list 2>/dev/null)"

# User-scoped: available in every directory on the box. The posthog and slack MCP
# servers ship with these plugins — there is nothing to add to ~/.claude.json.
for plugin in posthog slack; do
  case "$installed" in
    *"${plugin}@${MARKETPLACE}"*) continue ;;
  esac
  echo "coder-dotfiles: installing ${plugin} plugin..."
  claude plugin install "${plugin}@${MARKETPLACE}" --scope user \
    || echo "coder-dotfiles: install FAILED for ${plugin} (will retry next start)"
done

# Local scope: the posthog repo disables this plugin in its tracked settings, which outranks user scope.
# It writes the gitignored .claude/settings.local.json, so the checkout stays clean.
if [ -d "$HOME/posthog" ] && ! grep -qs "typescript-lsp@${MARKETPLACE}" "$HOME/posthog/.claude/settings.local.json"; then
  echo "coder-dotfiles: installing typescript-lsp plugin (local scope)..."
  (cd "$HOME/posthog" && claude plugin install "typescript-lsp@${MARKETPLACE}" --scope local) \
    || echo "coder-dotfiles: install FAILED for typescript-lsp (will retry next start)"
fi

echo "coder-dotfiles: claude plugins done"
