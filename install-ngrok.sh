#!/usr/bin/env bash
# ngrok for ReviewHog experiments: Modal sandboxes call back into the box, so ports 8010, 3308 and 8787
# need public HTTPS. Same three reserved domains as the laptop, so only one machine can run them at a time.
# The authtoken comes from the NGROK_AUTHTOKEN secret; it is never written to this config.
set -uo pipefail

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR" "$HOME/.config/ngrok"

if ! command -v ngrok >/dev/null 2>&1 && [ ! -x "$BIN_DIR/ngrok" ]; then
  case "$(uname -m)" in aarch64|arm64) arch=arm64 ;; *) arch=amd64 ;; esac
  curl -fsSL "https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-$arch.tgz" | tar -xz -C "$BIN_DIR" ngrok \
    || { echo "coder-dotfiles: ngrok download FAILED (will retry next start)"; exit 0; }
fi
echo "coder-dotfiles: $("$BIN_DIR/ngrok" --version 2>/dev/null || ngrok --version)"

cat > "$HOME/.config/ngrok/ngrok.yml" << 'YML'
version: "3"
tunnels:
  django:
    proto: http
    addr: 8010
    domain: alexl-django.ngrok.dev
    host_header: localhost
  gateway:
    proto: http
    addr: 3308
    domain: alexl-llmg.ngrok.dev
  mcp:
    proto: http
    addr: 8787
    domain: alexl-mcp.ngrok.dev
YML
[ -n "${NGROK_AUTHTOKEN:-}" ] || echo "coder-dotfiles: NGROK_AUTHTOKEN secret missing, ngrok will refuse to start"
echo "coder-dotfiles: ngrok config written (tunnels: django 8010, gateway 3308, mcp 8787)"
