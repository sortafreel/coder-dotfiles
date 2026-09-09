#!/usr/bin/env bash
# Install the Claude Code marketplace and plugins. Backgrounded by install.sh because
# `marketplace add` clones a git repo and each install hits the network.
# Idempotent: every step is guarded, so a re-run on workspace start is a no-op.
set -uo pipefail

# Coder runs dotfiles before the template puts ~/.local/bin (where claude lives) on PATH.
export PATH="$HOME/.local/bin:$PATH"

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

# Project-scoped: the LSP is only useful inside the posthog checkout.
if [ -d "$HOME/posthog" ]; then
  case "$installed" in
    *"typescript-lsp@${MARKETPLACE}"*) ;;
    *)
      echo "coder-dotfiles: installing typescript-lsp plugin (project scope)..."
      (cd "$HOME/posthog" && claude plugin install "typescript-lsp@${MARKETPLACE}" --scope project) \
        || echo "coder-dotfiles: install FAILED for typescript-lsp (will retry next start)"
      ;;
  esac
fi

echo "coder-dotfiles: claude plugins done"
