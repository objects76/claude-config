#!/bin/bash
# Custom statusline script for Claude Code
# Displays: git branch, model, tokens, 5h/7d usage limits with reset countdown

get_git_branch() {
    if git rev-parse --git-dir > /dev/null 2>&1; then
        branch=$(git branch --show-current 2>/dev/null || git rev-parse --abbrev-ref HEAD 2>/dev/null)
        if [ -n "$branch" ]; then
            echo "git:$branch"
        fi
    fi
}

# Convert ISO-8601 timestamp into a compact "time remaining" string (e.g. "4h12m", "2d3h", "37m").
remaining_until() {
    local iso="$1"
    [ -z "$iso" ] || [ "$iso" = "null" ] && return 0
    local target now diff d h m
    target=$(date -d "$iso" +%s 2>/dev/null) || return 0
    now=$(date +%s)
    diff=$(( target - now ))
    (( diff <= 0 )) && { printf "now"; return 0; }
    if (( diff >= 86400 )); then
        d=$(( diff / 86400 )); h=$(( (diff % 86400) / 3600 ))
        printf "%dd%dh" "$d" "$h"
    elif (( diff >= 3600 )); then
        h=$(( diff / 3600 )); m=$(( (diff % 3600) / 60 ))
        printf "%dh%dm" "$h" "$m"
    else
        m=$(( diff / 60 ))
        printf "%dm" "$m"
    fi
}

# Convert ISO-8601 timestamp into local clock time (MM/DD HH:MM, omits date if it's today).
local_clock() {
    local iso="$1"
    [ -z "$iso" ] || [ "$iso" = "null" ] && return 0
    local target_day today
    target_day=$(date -d "$iso" +%Y%m%d 2>/dev/null) || return 0
    today=$(date +%Y%m%d)
    if [ "$target_day" = "$today" ]; then
        date -d "$iso" +%H:%M
    else
        date -d "$iso" +"%m/%d %H:%M"
    fi
}

main() {
    local parts=()

    local json_input=$(cat)
    local model=$(echo "$json_input"  | jq -r '.model.display_name // empty')
    local tokens=$(echo "$json_input" | jq -r '.context_window.used_percentage // empty')
    local five_h=$(echo "$json_input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
    local week=$(echo "$json_input"   | jq -r '.rate_limits.seven_day.used_percentage // empty')
    local five_h_reset=$(echo "$json_input" | jq -r '.rate_limits.five_hour.resets_at // empty')
    local week_reset=$(echo "$json_input"   | jq -r '.rate_limits.seven_day.resets_at // empty')

    # Git branch
    local git_info=$(get_git_branch)
    [ -n "$git_info" ] && parts+=("$git_info")

    # Model
    [ -n "$model" ] && [ "$model" != "null" ] && parts+=("$model")

    # Tokens
    if [ -n "$tokens" ] && [ "$tokens" != "null" ]; then
        parts+=("cxt:${tokens}%")
    else
        parts+=("cxt:0%")
    fi

    # 5h / 7d usage limits with reset countdown (Pro/Max 구독 시에만 제공)
    if [ -n "$five_h" ] || [ -n "$week" ]; then
        local limit_str="limit:"
        if [ -n "$five_h" ]; then
            limit_str+="5h=$(printf '%.0f' "$five_h")%"
            local r5=$(remaining_until "$five_h_reset")
            [ -n "$r5" ] && limit_str+="(${r5})"
        fi
        [ -n "$five_h" ] && [ -n "$week" ] && limit_str+=" "
        if [ -n "$week" ]; then
            limit_str+="7d=$(printf '%.0f' "$week")%"
            local r7=$(remaining_until "$week_reset")
            [ -n "$r7" ] && limit_str+="(${r7})"
        fi
        parts+=("$limit_str")
    fi

    # Join with " | "
    local first=1
    for part in "${parts[@]}"; do
        [ $first -eq 1 ] && first=0 || printf " | "
        printf "%s" "$part"
    done
    printf "\n"
}

main
