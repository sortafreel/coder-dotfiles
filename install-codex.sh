#!/usr/bin/env bash
# Codex CLI: install, log in with the OPENAI_API_KEY secret, register the PostHog MCP server.
# The MCP OAuth login needs a browser and stays manual (see the alex-lebedev-devbox skill).
set -uo pipefail

CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
BIN_DIR="${CODEX_INSTALL_DIR:-$HOME/.local/bin}"
export PATH="$BIN_DIR:$PATH"

if ! command -v codex >/dev/null 2>&1; then
  curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh \
    || { echo "coder-dotfiles: codex install FAILED (will retry next start)"; exit 0; }
fi
echo "coder-dotfiles: $(codex --version 2>/dev/null)"

if ! codex login status >/dev/null 2>&1; then
  if [ -n "${OPENAI_API_KEY:-}" ]; then
    printenv OPENAI_API_KEY | codex login --with-api-key >/dev/null \
      && echo "coder-dotfiles: codex logged in with the OPENAI_API_KEY secret" \
      || echo "coder-dotfiles: codex login FAILED"
  else
    echo "coder-dotfiles: OPENAI_API_KEY secret missing, skipping codex login"
  fi
fi

# `codex mcp add` starts the OAuth browser flow at once and blocks, so write the config block directly.
if ! codex mcp get posthog >/dev/null 2>&1; then
  mkdir -p "$CODEX_DIR"
  printf '\n[mcp_servers.posthog]\nurl = "https://mcp.posthog.com/mcp"\nstartup_timeout_sec = 30\n' >> "$CODEX_DIR/config.toml"
  echo "coder-dotfiles: registered the posthog MCP server in codex (OAuth login is manual)"
fi
