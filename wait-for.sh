#!/usr/bin/env bash
# Sourced by the background scripts. Coder runs dotfiles before the template's own bootstrap
# (claude install, ~/posthog pull) finishes, so each script polls for what it needs first.
wait_for() {
  local label="$1" timeout="$2" waited=0
  shift 2
  until "$@"; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "coder-dotfiles: gave up waiting for ${label} after ${timeout}s"
      return 1
    fi
    [ "$waited" -eq 0 ] && echo "coder-dotfiles: waiting for ${label}..."
    sleep 5
    waited=$((waited + 5))
  done
}

# True once the template has pulled ~/posthog to master: no pull in flight, and a file the
# July AMI snapshot predates is present.
checkout_ready() {
  local dir="${POSTHOG_DIR:-$HOME/posthog}"
  [ ! -e "$dir/.git/index.lock" ] && grep -q "^    desktop:" "$dir/devenv/intent-map.yaml" 2>/dev/null
}
