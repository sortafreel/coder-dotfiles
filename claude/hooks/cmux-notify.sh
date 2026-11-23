#!/usr/bin/env bash
# Show a cmux desktop notification (OSC 777) when a Claude Code or Codex session
# finishes a turn, hits an API error, or waits for an answer or a permission.
#
#   Claude Code: a hook in ~/.claude/settings.json, event JSON on stdin.
#   Codex:       `notify` in ~/.codex/config.toml, run as `cmux-notify.sh codex '<event JSON>'`.
#
# Claude Code's own `terminalSequence` output gets wrapped for tmux passthrough,
# so inside tmux this script writes the sequence itself, to two places:
#   - the pane's tty, because cmux's `tmux -CC` mirror reads the raw pane output;
#   - each regular client's tty, because tmux drops OSC 777 on the way to them.
# Outside tmux it returns `terminalSequence` and lets Claude Code write it. Codex
# has no such output, so there the sequence goes to the terminal Codex runs on.

agent=Claude
if [ "${1:-}" = codex ]; then
    agent=Codex
    input=${2:-}
else
    input=$(cat)
fi

parsed=$(jq -r '
  def clean:
    gsub("[[:cntrl:]]+"; " ") | gsub("`|\\*\\*"; "") | gsub(";"; ",")
    | gsub(" +"; " ") | ltrimstr(" ") | rtrimstr(" ")
    | if length > 180 then .[0:179] + "…" else . end;
  . as $in
  | (.hook_event_name // .type // "") as $event
  | if $event == "Stop" then ["finished", (.last_assistant_message // "")]
    elif $event == "agent-turn-complete" then
      (.["last-assistant-message"] // "") as $reply
      # Codex names a new thread with a side request that also reports here. Its reply is {"title": ...}.
      | if ($reply | try (fromjson | type == "object" and keys == ["title"]) catch false) then empty
        else ["finished", $reply] end
    elif $event == "StopFailure" then ["stopped on an error", (.last_assistant_message // .error // "")]
    elif $event == "Notification" then ["needs you", (.message // "")]
    elif $event == "PreToolUse" then ["has a question", (.tool_input.questions[0].question // "")]
    else empty end
  | [$event, ($in.notification_type // ""), ($in.session_id // "")] + map(tostring | clean)
  | .[]
' <<<"$input" 2>/dev/null) || exit 0
[ -n "$parsed" ] || exit 0
{ IFS= read -r event; IFS= read -r notification_type; IFS= read -r session_id; IFS= read -r title; IFS= read -r body; } <<<"$parsed"
title="$agent $title"

# AskUserQuestion is notified from PreToolUse with the question text, and then
# shows as a permission prompt, so skip the generic prompt notice that follows.
stamp_dir="${XDG_RUNTIME_DIR:-/tmp}/claude-cmux-notify-$(id -u)"
stamp="$stamp_dir/${session_id:-unknown}.asked"
if [ "$event" = PreToolUse ]; then
    mkdir -p "$stamp_dir" && touch "$stamp"
elif [ "$event" = Notification ] && [ "$notification_type" = permission_prompt ] \
    && [ -n "$(find "$stamp" -newermt '-30 seconds' 2>/dev/null)" ]; then
    rm -f "$stamp"
    exit 0
fi

# Name the box in the title, e.g. "dev4" for devbox-<owner>-dev4.
where=""
if [ -n "${CODER_WORKSPACE_NAME:-}" ]; then
    where=${CODER_WORKSPACE_NAME#devbox-}
    where=${where#"${CODER_WORKSPACE_OWNER_NAME:-}"-}
    [ "$where" = "${CODER_WORKSPACE_OWNER_NAME:-}" ] && where=devbox
fi
[ -n "$where" ] && title="$title · $where"
[ -n "$body" ] || body="$title"

seq=$(printf '\033]777;notify;%s;%s\007' "$title" "$body")

send() {
    [ -w "$1" ] || return 0
    # A stalled SSH link can block a tty write, so never hold up the agent on it.
    timeout 2 sh -c 'printf "%s" "$1" > "$2"' _ "$seq" "$1" 2>/dev/null || true
}

if [ -n "${TMUX:-}" ] && [ -n "${TMUX_PANE:-}" ] && command -v tmux >/dev/null 2>&1; then
    session=$(tmux display-message -p -t "$TMUX_PANE" '#{session_id}' 2>/dev/null) || exit 0
    pane_tty=$(tmux display-message -p -t "$TMUX_PANE" '#{pane_tty}' 2>/dev/null)
    has_mirror=0
    while read -r control_mode client_tty; do
        if [ "$control_mode" = 1 ]; then
            has_mirror=1
        else
            send "$client_tty"
        fi
    done < <(tmux list-clients -t "$session" -F '#{client_control_mode} #{client_tty}' 2>/dev/null)
    [ "$has_mirror" = 1 ] && [ -n "$pane_tty" ] && send "$pane_tty"
elif [ "$agent" = Codex ]; then
    # Codex starts `notify` without a controlling terminal, so /dev/tty is not there.
    codex_tty=$(ps -o tty= -p "$PPID" 2>/dev/null | tr -d ' ')
    [ -n "$codex_tty" ] && [ "$codex_tty" != "?" ] && send "/dev/$codex_tty"
else
    jq -nc --arg seq "$seq" '{terminalSequence: $seq}'
fi
exit 0
