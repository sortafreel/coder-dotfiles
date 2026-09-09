#!/usr/bin/env bash
# Refresh phrocs from the phrocs-latest release. The AMI bakes a stale build into
# tools/phrocs/dist and hogli neither checks nor refreshes it, so `hogli start` units fail.
set -uo pipefail

POSTHOG_DIR="${POSTHOG_DIR:-$HOME/posthog}"
DIST="$POSTHOG_DIR/tools/phrocs/dist"
source "$(dirname "${BASH_SOURCE[0]}")/wait-for.sh"
wait_for "posthog checkout pull" 900 checkout_ready || exit 0

# /usr/local/bin is root-owned on the box, so the installer lands in ~/.local/bin.
mkdir -p "$HOME/.local/bin"
bash "$POSTHOG_DIR/tools/phrocs/install.sh" \
  || { echo "coder-dotfiles: phrocs download FAILED (will retry next start)"; exit 0; }

# hogli resolves phrocs through the venv symlink into dist/. mv, not cp: the old binary may be running.
mkdir -p "$DIST"
cp "$HOME/.local/bin/phrocs" "$DIST/phrocs.new" && chmod 755 "$DIST/phrocs.new" && mv -f "$DIST/phrocs.new" "$DIST/phrocs" \
  || { echo "coder-dotfiles: phrocs swap into dist FAILED"; exit 0; }
echo "coder-dotfiles: phrocs refreshed -> $("$DIST/phrocs" --version)"
