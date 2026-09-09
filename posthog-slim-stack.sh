#!/usr/bin/env bash
# Select the slim hogli dev stack (signals + reviewhog) in ~/posthog; mirrors the laptop's
# posthog_configs/slim-stack/apply.sh. Uses bin/hogli because the boot context has no flox shell.
set -uo pipefail

POSTHOG_DIR="${POSTHOG_DIR:-$HOME/posthog}"
HOGLI="$POSTHOG_DIR/bin/hogli"
[ -x "$HOGLI" ] || { echo "coder-dotfiles: $HOGLI not found, skipping slim stack"; exit 0; }

source "$(dirname "${BASH_SOURCE[0]}")/wait-for.sh"
# The AMI checkout predates the desktop intent; the template pulls master after dotfiles start.
checkout_ready() {
  [ ! -e "$POSTHOG_DIR/.git/index.lock" ] && grep -q "^    desktop:" "$POSTHOG_DIR/devenv/intent-map.yaml" 2>/dev/null
}
wait_for "posthog checkout pull" 900 checkout_ready || exit 0

cd "$POSTHOG_DIR"
"$HOGLI" dev:apply desktop mcp \
    --include embedding-worker \
    --exclude desktop \
    --exclude agent-proxy \
    --exclude capture \
    --exclude nodejs \
    --exclude property-defs-rs \
    --exclude personhog-replica \
    --exclude personhog-router \
    --skip-autostart mcp-ui-apps \
  && echo "coder-dotfiles: slim stack applied" \
  || echo "coder-dotfiles: slim stack apply FAILED (will retry next start)"
