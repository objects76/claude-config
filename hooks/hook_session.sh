#!/bin/bash
# Claude Code session hook: notify on long-running stop AND ask-user states.
#
# Events handled:
#   UserPromptSubmit       - 작업 시작 시각 기록
#   Stop                   - 작업 종료 시 duration이 임계값 이상이면 notify
#   PreToolUse             - AskUserQuestion / ExitPlanMode 호출 시 notify
#   Notification           - idle_prompt / elicitation_dialog 시 notify
#                            (permission_prompt는 의도적으로 제외)

DURATION_THRESHOLD=60
EUROPE_TIME=0
MSG_TRUNCATE=200

# 로컬 알림: 이 스크립트와 같은 폴더의 dunstify 사용 (--activate 지원 빌드)
HOOK_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
DUNSTIFY="${HOOK_DIR}/dunstify"

# ---------------------------------------------------------------------------
# get_wid: 호출자(또는 그 조상)가 소유한 X11 top-level 윈도우 id를 반환.
#   현재 작업 디렉터리 basename이 타이틀에 포함된 윈도우를 우선 선택.
# ---------------------------------------------------------------------------
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

# ---------------------------------------------------------------------------
# dunstify_local: 같은 폴더의 dunstify로 로컬 알림을 띄움.
#   클릭 시 호출자 창을 활성화하도록 --activate=WID 사용.
#   dunstify는 클릭 대기를 위해 메인 루프를 도므로 백그라운드 실행.
#   Args: timeout_ms urgency title body
#     timeout_ms - 0이면 자동 닫힘 없음 (클릭/dunst-server 만료까지 대기)
#     urgency    - low|normal|critical (빈 값이면 -u 생략)
# ---------------------------------------------------------------------------
dunstify_local() {
    local timeout_ms=$1
    local urgency=$2
    local title=$3
    local body=$4

    local wid
    wid=$(get_wid "$$" 2>/dev/null || true)

    local args=()
    [ -n "$urgency" ] && args+=( -u "$urgency" )
    [ -n "$timeout_ms" ] && args+=( -t "$timeout_ms" )
    [ -n "$wid" ] && args+=( --activate="$wid" )

    if [ -n "$body" ]; then
        ( "$DUNSTIFY" "${args[@]}" "$title" "$body" >/dev/null 2>&1 ) &
    else
        ( "$DUNSTIFY" "${args[@]}" "$title" >/dev/null 2>&1 ) &
    fi
    disown 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# notify_ssh: SSH 환경에서 client 머신으로 notify-send forward
#   Args: title body extra_flags (e.g. "-u critical" or "-u normal -t 5000")
# ---------------------------------------------------------------------------
notify_ssh() {
    local title=$1
    local body=$2
    local extra=$3

    local client_host
    client_host=$(echo "$SSH_CONNECTION" | awk '{print $1}')
    if [ -z "$client_host" ] && [ -n "$SSH_CLIENT" ]; then
        client_host=$(echo "$SSH_CLIENT" | awk '{print $1}')
    fi
    local remote_user="${NOTIFY_USER:-$USER}"
    if [ -z "$client_host" ]; then
        echo "Could not detect SSH client host" >&2
        return 1
    fi

    local prefixed_title="[$(hostname)] $title"
    local cmd="notify-send"
    [ -n "$extra" ] && cmd="$cmd $extra"
    cmd="$cmd $(printf '%q' "$prefixed_title")"
    [ -n "$body" ] && cmd="$cmd $(printf '%q' "$body")"

    ssh -o SendEnv=DISPLAY \
        -o ForwardX11=no \
        -o ConnectTimeout=2 \
        "${remote_user}@${client_host}" "$cmd" 2>/dev/null || \
        echo "Failed to send notification to ${remote_user}@${client_host}: $cmd" >&2
}

# ---------------------------------------------------------------------------
# truncate_message: 메시지가 너무 길면 줄임
# ---------------------------------------------------------------------------
truncate_message() {
    local msg="$1"
    if [ ${#msg} -gt $MSG_TRUNCATE ]; then
        echo "${msg:0:$MSG_TRUNCATE}..."
    else
        echo "$msg"
    fi
}

# ---------------------------------------------------------------------------
# send_notification: Stop 이벤트용 (duration_str을 title로)
# ---------------------------------------------------------------------------
send_notification() {
    local duration="$1"
    local message="$2"
    local hours=$((duration / 3600))
    local minutes=$(((duration % 3600) / 60))
    local seconds=$((duration % 60))
    local duration_str
    duration_str=$(printf "%02d:%02d:%02d" "$hours" "$minutes" "$seconds")
    message=$(truncate_message "$message")

    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_CONNECTION" ]; then
        notify_ssh "$duration_str" "$message" ""
    else
        dunstify_local "0" "" "$duration_str" "$message"
    fi
}

# ---------------------------------------------------------------------------
# send_ask_notification: ask-user 상태용 (label을 title로)
#   timeout_ms: 0이면 critical 유지, 그 외 normal urgency
# ---------------------------------------------------------------------------
send_ask_notification() {
    local label="$1"
    local message="$2"
    local timeout_ms="${3:-0}"
    message=$(truncate_message "$message")

    if [ -n "$SSH_CLIENT" ] || [ -n "$SSH_CONNECTION" ]; then
        if [ "$timeout_ms" -gt 0 ]; then
            notify_ssh "$label" "$message" "-u normal -t $timeout_ms"
        else
            notify_ssh "$label" "$message" "-u critical"
        fi
    else
        if [ "$timeout_ms" -gt 0 ]; then
            dunstify_local "$timeout_ms" normal "$label" "$message"
        else
            dunstify_local 0 critical "$label" "$message"
        fi
    fi
}

# ---------------------------------------------------------------------------
# hook_stop: 기존 Stop 이벤트 처리
# ---------------------------------------------------------------------------
hook_stop() {
    local json_input="$1"
    local message
    message=$(echo "$json_input" | jq -r '.last_assistant_message // "Task completed"')
    if [ -f "$START_FILE" ]; then
        local start_time
        start_time=$(cat "$START_FILE")
        local now
        now=$(date +%s)
        local duration=$((now - start_time))
        if [ "$duration" -ge "$DURATION_THRESHOLD" ]; then
            if [ "$duration" -lt "$EUROPE_TIME" ]; then
                local delay=$((EUROPE_TIME - duration))
                local session_marker="${START_FILE}_delayed"
                date +%s > "$session_marker"
                (
                    sleep "$delay"
                    if [ -f "$session_marker" ]; then
                        send_notification "$duration" "$message"
                        rm -f "$session_marker"
                    fi
                ) &
            else
                send_notification "$duration" "$message"
            fi
        fi
        rm -f "$START_FILE"
    fi
}

# ---------------------------------------------------------------------------
# hook_pretool: Claude가 사용자 입력을 요청하는 tool 호출 직전
#   - AskUserQuestion: 선택지 질문
#   - ExitPlanMode: plan 승인 요청
#   그 외 tool은 무시 (matcher가 잘 걸려 있으면 들어오지 않음)
# ---------------------------------------------------------------------------
hook_pretool() {
    local json_input="$1"
    local tool_name
    tool_name=$(echo "$json_input" | jq -r '.tool_name')

    case "$tool_name" in
        "AskUserQuestion")
            local q_count first_q msg
            q_count=$(echo "$json_input" | jq -r '.tool_input.questions | length')
            first_q=$(echo "$json_input" | jq -r '.tool_input.questions[0].question // "User input needed"')
            if [ "$q_count" -gt 1 ]; then
                msg="$first_q (+$((q_count - 1)) more)"
            else
                msg="$first_q"
            fi
            send_ask_notification "❓ Claude is asking" "$msg"
            ;;
        "ExitPlanMode")
            local plan first_line line_count
            plan=$(echo "$json_input" | jq -r '.tool_input.plan // ""')
            first_line=$(echo "$plan" | head -n 1)
            line_count=$(echo "$plan" | wc -l)
            send_ask_notification "📋 Plan ready for approval" \
                "${first_line} (${line_count} lines)"
            ;;
    esac
}

# ---------------------------------------------------------------------------
# hook_notification: idle / elicitation 등 (permission_prompt 제외)
# ---------------------------------------------------------------------------
hook_notification() {
    local json_input="$1"
    local notif_type message
    notif_type=$(echo "$json_input" | jq -r '.notification_type // ""')
    message=$(echo "$json_input" | jq -r '.message // ""')

    case "$notif_type" in
        "idle_prompt")
            send_ask_notification "💤 Claude is idle" "$message"
            ;;
        "elicitation_dialog")
            send_ask_notification "💬 MCP elicitation" "$message"
            ;;
        # permission_prompt 는 명시적으로 무시
    esac
}

# ---------------------------------------------------------------------------
# main: stdin JSON 을 읽어 hook_event_name 기준 분기
# ---------------------------------------------------------------------------
main() {
    JSON=$(cat)
    EVENT_TYPE=$(echo "$JSON" | jq -r '.hook_event_name')
    SESSION_ID=$(echo "$JSON" | jq -r '.session_id')
    START_FILE="/tmp/claude_prompt_start_${USER}_${SESSION_ID}"
    case "$EVENT_TYPE" in
        "UserPromptSubmit")
            date +%s > "$START_FILE"
            rm -f "${START_FILE}_delayed"
            ;;
        "Stop")
            hook_stop "$JSON"
            ;;
        "PreToolUse")
            hook_pretool "$JSON"
            ;;
        "Notification")
            hook_notification "$JSON"
            ;;
    esac
}

# 수동 테스트:
#   ~/.claude/hooks/hook_session.sh notify 75 "테스트 알림"
#   ~/.claude/hooks/hook_session.sh ask "❓ Test" "사용자 입력 대기 중"
if [[ "$1" == "notify" ]]; then
    send_notification "$2" "$3"
    exit 0
fi
if [[ "$1" == "ask" ]]; then
    send_ask_notification "$2" "$3" "${4:-0}"
    exit 0
fi

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
