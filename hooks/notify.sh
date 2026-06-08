#!/usr/bin/env bash
# notify.sh TIMEOUT_MS "multi line message"
#
# Sends a desktop notification (dunstify) that, when clicked, activates the
# top-level X11 window containing the caller process.
#
# Arguments:
#   TIMEOUT_MS  notification timeout in milliseconds (0 = never auto-close)
#   message     notification text; first line becomes summary, rest becomes body

set -e

# --- find top-level window id for the given PID --------------------------
# Walks up the ancestor chain until it finds a process that owns a WM-managed
# top-level window. Among that process's windows, prefers one whose title
# contains the caller's current working directory basename.
#
# Echoes the window id (hex, e.g. 0x04a0003b) on success.
get_wid() {
    local caller=${1:-$PPID}
    local cwd cwd_base
    cwd=$(readlink "/proc/$caller/cwd" 2>/dev/null || echo "$PWD")
    cwd_base=$(basename "$cwd")

    local pid=$caller
    while [ -n "$pid" ] && [ "$pid" != "1" ] && [ "$pid" != "0" ]; do
        local wins
        wins=$(xdotool search --pid "$pid" 2>/dev/null || true)
        if [ -n "$wins" ]; then
            local candidates
            candidates=$(wmctrl -lp | awk -v p="$pid" '$3 == p {print $1}')
            if [ -n "$candidates" ]; then
                local best="" fallback="" wid title
                while read -r wid; do
                    [ -z "$wid" ] && continue
                    [ -z "$fallback" ] && fallback=$wid
                    title=$(xdotool getwindowname "$wid" 2>/dev/null || true)
                    if [[ "$title" == *"$cwd_base"* ]]; then
                        best=$wid
                        break
                    fi
                done <<< "$candidates"
                echo "${best:-$fallback}"
                return 0
            fi
        fi
        pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    done
    return 1
}

# --- argument handling --------------------------------------------------
if [ $# -lt 2 ]; then
    echo "usage: $0 TIMEOUT_MS \"multi line message\"" >&2
    exit 1
fi

timeout_ms=$1
msg=$2

case "$timeout_ms" in
    ''|*[!0-9]*)
        echo "notify.sh: TIMEOUT_MS must be a non-negative integer (got: $timeout_ms)" >&2
        exit 1
        ;;
esac

dir=$(dirname "$(readlink -f "$0")")

wid=$(get_wid "$PPID") || {
    echo "notify.sh: could not find a window for caller PID $PPID" >&2
    exit 1
}

summary=${msg%%$'\n'*}
if [[ "$msg" == *$'\n'* ]]; then
    body=${msg#*$'\n'}
else
    body=""
fi

if [ -n "$body" ]; then
    "$dir/dunstify" --activate="$wid" -t "$timeout_ms" "$summary" "$body"
else
    "$dir/dunstify" --activate="$wid" -t "$timeout_ms" "$summary"
fi
