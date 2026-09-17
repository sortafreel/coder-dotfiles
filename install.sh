#!/usr/bin/env bash
# Applied automatically by Coder on devbox creation/restart (via hogli devbox:setup --configure-dotfiles).
# Must stay idempotent: runs on every workspace start.
set -euo pipefail

# --- Shell aliases (managed block, replaced on every run; manual lines outside it are kept) ---
if grep -q '# >>> coder-dotfiles >>>' ~/.bash_aliases 2>/dev/null; then
  sed -i '/# >>> coder-dotfiles >>>/,/# <<< coder-dotfiles <<</d' ~/.bash_aliases
fi
cat >> ~/.bash_aliases << 'EOF'
# >>> coder-dotfiles >>>
alias gcm='git checkout master'
alias gcmm='git checkout main'
alias gpp='git pull'
# Re-select the slim stack after `hogli nuke` resets it.
alias slim='bash ~/.config/coderv2/dotfiles/posthog-slim-stack.sh'
# ReviewHog experiments: public tunnels for the Modal sandboxes. Start before the stack.
alias tunnels='ngrok start --all'
alias seed-github-app='bash ~/.config/coderv2/dotfiles/seed-github-app.sh'
# Ghostty's TERM has no terminfo on the box, which breaks clear/less/vim.
[ "$TERM" = xterm-ghostty ] && export TERM=xterm-256color
# <<< coder-dotfiles <<<
EOF

# --- tmux (managed block) ---
# Agents run inside tmux to survive a laptop sleep; the defaults have no mouse scrolling and a 2000-line scrollback.
if ! grep -q '# >>> coder-dotfiles >>>' ~/.tmux.conf 2>/dev/null; then
  cat >> ~/.tmux.conf << 'EOF'
# >>> coder-dotfiles >>>
set -g mouse on
set -g history-limit 50000
# <<< coder-dotfiles <<<
EOF
fi

# --- Commit signing safety net ---
# The posthog-linux template configures signing from the POSTHOG_GIT_SIGNING_KEY
# secret at boot, but its bootstrap can race ("Bootstrap did not complete before
# Git identity sync") and leave the box unsigned. Reapply if that happened.
if [ -n "${POSTHOG_GIT_SIGNING_KEY:-}" ] && [ "$(git config --global --get commit.gpgsign || true)" != "true" ]; then
  git config --global gpg.format ssh
  git config --global user.signingkey "key::${POSTHOG_GIT_SIGNING_KEY#key::}"
  git config --global commit.gpgsign true
  git config --global tag.gpgsign true
  echo "coder-dotfiles: reapplied git signing config (template bootstrap had not)"
fi

# --- git credentials over HTTPS ---
# The box ships gh logged in via the GH_TOKEN secret, but git has no credential helper,
# so an HTTPS push hangs on a username prompt. Point git at gh. Idempotent.
if gh auth status >/dev/null 2>&1; then
  gh auth setup-git || echo "coder-dotfiles: gh auth setup-git FAILED"
else
  echo "coder-dotfiles: gh not logged in (GH_TOKEN secret missing?), skipping git credential helper"
fi

# --- Metabase cookie ---
# `hogli metabase:*` reads the plain cookie header from this file and never opens a browser,
# so the METABASE_COOKIE_US secret (set from the laptop after `hogli metabase:login`) is enough.
if [ -n "${METABASE_COOKIE_US:-}" ]; then
  mkdir -p ~/.config/posthog/metabase
  ( umask 077 && printf '%s' "$METABASE_COOKIE_US" > ~/.config/posthog/metabase/cookie-us.new ) \
    && mv -f ~/.config/posthog/metabase/cookie-us.new ~/.config/posthog/metabase/cookie-us \
    || echo "coder-dotfiles: metabase cookie write FAILED"
else
  echo "coder-dotfiles: METABASE_COOKIE_US secret missing, hogli metabase:* will need a copied cookie"
fi

# --- ReviewHog experiment settings in ~/posthog/.env ---
# Modal sandboxes need the public tunnel URLs and the Modal provider; the gateway needs the local AI capture lane.
# Static, not secret. Set in place (the image ships SANDBOX_PROVIDER=docker), because a key present in .env
# beats the shell env under flox activation. The stack reads .env only at start.
ENV_FILE="$HOME/posthog/.env"
set_env_key() {
  if grep -qE "^$2=" "$ENV_FILE"; then sed -i "s|^$2=.*|$2=$3|" "$ENV_FILE"; else printf '%s=%s\n' "$2" "$3" >> "$ENV_FILE"; fi
}
if [ -f "$ENV_FILE" ]; then
  set_env_key "$ENV_FILE" SANDBOX_PROVIDER MODAL_DOCKER
  set_env_key "$ENV_FILE" SANDBOX_API_URL https://alexl-django.ngrok.dev
  set_env_key "$ENV_FILE" SANDBOX_LLM_GATEWAY_URL https://alexl-llmg.ngrok.dev
  set_env_key "$ENV_FILE" SANDBOX_MCP_URL https://alexl-mcp.ngrok.dev/mcp
  set_env_key "$ENV_FILE" LLM_GATEWAY_POSTHOG_HOST http://localhost:8010
  set_env_key "$ENV_FILE" LLM_GATEWAY_POSTHOG_AI_LANE_CAPTURE true
  set_env_key "$ENV_FILE" LLM_GATEWAY_POSTHOG_PROJECT_TOKEN phc_devbox_local_experiments
else
  echo "coder-dotfiles: $ENV_FILE missing, experiment settings not written"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Claude Code personal config ---
# Both steps are fast and offline, and must land before the backgrounded plugin
# install: that also rewrites settings.json, and interleaving two read-modify-write
# passes over the same file can drop whichever key was written first.
python3 "$SCRIPT_DIR/claude-settings.py" || echo "coder-dotfiles: claude settings merge FAILED"

mkdir -p ~/.claude/skills
cp -R "$SCRIPT_DIR/claude/skills/." ~/.claude/skills/ \
  || echo "coder-dotfiles: claude skills copy FAILED"

# --- Background work ---
# None block workspace start: ~5 repo clones, a marketplace clone plus 3 plugin installs, the slim stack selection, a phrocs refresh, the agent skills install, the bubblewrap apt install, the Codex CLI install + login, and the ngrok install.
nohup bash "$SCRIPT_DIR/clone-repos.sh" >> "$HOME/.coder-dotfiles-clone.log" 2>&1 &
nohup bash "$SCRIPT_DIR/install-claude-plugins.sh" >> "$HOME/.coder-dotfiles-plugins.log" 2>&1 &
nohup bash "$SCRIPT_DIR/posthog-slim-stack.sh" >> "$HOME/.coder-dotfiles-slim-stack.log" 2>&1 &
nohup bash "$SCRIPT_DIR/install-phrocs.sh" >> "$HOME/.coder-dotfiles-phrocs.log" 2>&1 &
nohup bash "$SCRIPT_DIR/install-agent-skills.sh" >> "$HOME/.coder-dotfiles-skills.log" 2>&1 &
nohup bash "$SCRIPT_DIR/install-bubblewrap.sh" >> "$HOME/.coder-dotfiles-bubblewrap.log" 2>&1 &
nohup bash "$SCRIPT_DIR/install-codex.sh" >> "$HOME/.coder-dotfiles-codex.log" 2>&1 &
nohup bash "$SCRIPT_DIR/install-ngrok.sh" >> "$HOME/.coder-dotfiles-ngrok.log" 2>&1 &

echo "coder-dotfiles: install.sh done (repo clones -> ~/.coder-dotfiles-clone.log, claude plugins -> ~/.coder-dotfiles-plugins.log, slim stack -> ~/.coder-dotfiles-slim-stack.log, phrocs -> ~/.coder-dotfiles-phrocs.log, skills -> ~/.coder-dotfiles-skills.log, bubblewrap -> ~/.coder-dotfiles-bubblewrap.log, codex -> ~/.coder-dotfiles-codex.log, ngrok -> ~/.coder-dotfiles-ngrok.log)"
