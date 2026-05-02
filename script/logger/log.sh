# shellcheck shell=bash
# log.sh — sourceable leveled logger with notification hook.
#
# Source this file from any bash/zsh script that wants leveled logging:
#
#   LOG_TAG=my-script                    # REQUIRED; identifies script in file names
#   LOG_CONTEXT=some-scope               # OPTIONAL; e.g. repo name for sync_repo
#   source "$DOTFILES_ROOT/script/logger/log.sh"
#   log INFO  "START"
#   log ERROR "OPERATION-FAILED reason=..."
#
# Every call writes a structured line to a file under $LOG_ROOT/$MACHINE_NAME/.
# File name: <TAG>[.<CONTEXT>].<DATE>[.<TIME>].log
#   - If no file exists for this TAG+CONTEXT+DATE, use the undecorated name
#     (the "first run of the day" gets the clean name).
#   - Otherwise, include HHMMSS of this run's start time.
#
# Per-call output destinations:
#   - Always: append to the log file.
#   - If stderr is a TTY (interactive): also print the line to stderr, in colour
#     by level, so the operator sees events inline.
#   - If level >= $LOG_NOTIFY_THRESHOLD AND $LOG_NOTIFY_MODE permits: dispatch
#     to $LOG_NOTIFY_CMD (default bin/notify-webhook). Notifications are
#     fire-and-forget so the caller is never blocked by network calls.
#
#   LOG_NOTIFY_MODE values:
#     auto   (default) — notify only when stderr is NOT a TTY. So running the
#                        script manually in a terminal shows events there but
#                        does not ping the phone; systemd / cron runs notify
#                        normally.
#     always          — always notify if level >= threshold.
#     never           — never notify.
#
#   Environment knobs (all optional):
#     LOG_ROOT                  where log files live; default ~/.local/state/logs
#     LOG_REL_BASE              paths in notifications are shown relative to this;
#                               default $LOG_ROOT. Set to a location synced
#                               across machines (e.g., ~/my-notes) to get
#                               notification paths that open on any machine.
#     LOG_NOTIFY_THRESHOLD      level name (DEBUG/INFO/WARN/ERROR/CRITICAL); default ERROR
#     LOG_NOTIFY_MODE           auto|always|never; default auto
#     LOG_NOTIFY_CMD            path to notifier; default $DOTFILES_ROOT/bin/notify-webhook
#     LOG_MACHINE_NAME          override machine name; default from hostnamectl --pretty
#
# State:
#   _LOG_FILE                 resolved at first log() call; cached for the rest of the run
#   _LOG_RUN_START            epoch seconds of first log() call; used for optional .HHMMSS suffix

: "${LOG_TAG:?LOG_TAG must be set before sourcing log.sh}"
: "${LOG_CONTEXT:=}"
: "${LOG_ROOT:=$HOME/.local/state/logs}"
: "${LOG_REL_BASE:=$LOG_ROOT}"
: "${LOG_NOTIFY_THRESHOLD:=ERROR}"
: "${LOG_NOTIFY_MODE:=auto}"
: "${LOG_NOTIFY_CMD:=${DOTFILES_ROOT:-$HOME/.dotfiles}/bin/notify-webhook}"

# Machine name matches sync_repo's convention.
if [ -z "${LOG_MACHINE_NAME:-}" ]; then
    LOG_MACHINE_NAME=$(hostnamectl --pretty 2>/dev/null | grep -v '\.')
    LOG_MACHINE_NAME=${LOG_MACHINE_NAME:-$(hostname -s 2>/dev/null || echo unknown)}
fi

_LOG_FILE=""
_LOG_RUN_START=""

_log_level_num() {
    case "$1" in
        DEBUG)    echo 10 ;;
        INFO)     echo 20 ;;
        WARN)     echo 30 ;;
        ERROR)    echo 40 ;;
        CRITICAL) echo 50 ;;
        *)        echo 0  ;;
    esac
}

_log_init_file() {
    # Called on first log() invocation.
    _LOG_RUN_START=$(date +%s)
    local dir="$LOG_ROOT/$LOG_MACHINE_NAME"
    mkdir -p "$dir" 2>/dev/null

    local date_part today_time
    date_part=$(date -d "@$_LOG_RUN_START" +%Y%m%d 2>/dev/null) || date_part=$(date +%Y%m%d)
    today_time=$(date -d "@$_LOG_RUN_START" +%H%M%S 2>/dev/null) || today_time=$(date +%H%M%S)

    # Build base name with optional CONTEXT.
    local base
    if [ -n "$LOG_CONTEXT" ]; then
        # Sanitize: replace slashes and whitespace with '-'
        local ctx_safe
        ctx_safe=$(printf '%s' "$LOG_CONTEXT" | tr '/ ' '--')
        base="${LOG_TAG}.${ctx_safe}.${date_part}"
    else
        base="${LOG_TAG}.${date_part}"
    fi

    local undecorated="$dir/$base.log"
    if [ -e "$undecorated" ]; then
        # Another run already took the undecorated name today; use a timestamped file.
        _LOG_FILE="$dir/$base.$today_time.log"
    else
        _LOG_FILE="$undecorated"
    fi
}

_log_rel_path() {
    # Print $_LOG_FILE relative to $LOG_REL_BASE if possible; else absolute.
    case "$_LOG_FILE" in
        "$LOG_REL_BASE"/*) printf '%s' "${_LOG_FILE#"$LOG_REL_BASE"/}" ;;
        *)                 printf '%s' "$_LOG_FILE" ;;
    esac
}

# Per-level stderr colour. Only applied when stderr is a TTY.
_log_color_for() {
    case "$1" in
        DEBUG)    printf '\033[2m'   ;; # dim
        INFO)     printf ''          ;; # default
        WARN)     printf '\033[33m'  ;; # yellow
        ERROR)    printf '\033[31m'  ;; # red
        CRITICAL) printf '\033[1;31m';; # bold red
        *)        printf ''          ;;
    esac
}

# Decide whether to dispatch a notification for the current log call.
# Reads $LOG_NOTIFY_MODE (auto|always|never). Default "auto" = only notify when
# stderr is NOT a TTY, so manual terminal runs don't ping the phone.
_log_should_notify() {
    case "$LOG_NOTIFY_MODE" in
        never)  return 1 ;;
        always) return 0 ;;
        auto|*)
            if [ -t 2 ]; then
                return 1   # interactive: user is watching stderr
            else
                return 0   # non-interactive: systemd/cron/pipe
            fi
            ;;
    esac
}

log() {
    local level=$1; shift
    local msg="$*"

    [ -z "$_LOG_FILE" ] && _log_init_file

    local line
    line=$(printf '%s [%s] [%s]%s %s' \
        "$(date -Iseconds)" \
        "$LOG_TAG" \
        "$level" \
        "${LOG_CONTEXT:+ [$LOG_CONTEXT]}" \
        "$msg")

    # Always append to the log file.
    printf '%s\n' "$line" >> "$_LOG_FILE"

    # Mirror to stderr if interactive, with colour.
    if [ -t 2 ]; then
        local color reset='\033[0m'
        color=$(_log_color_for "$level")
        if [ -n "$color" ]; then
            printf '%b%s%b\n' "$color" "$line" "$reset" >&2
        else
            printf '%s\n' "$line" >&2
        fi
    fi

    # Notification path — only when threshold met AND mode permits.
    local threshold_num level_num
    threshold_num=$(_log_level_num "$LOG_NOTIFY_THRESHOLD")
    level_num=$(_log_level_num "$level")

    if [ "$level_num" -ge "$threshold_num" ] && _log_should_notify; then
        local rel body title
        rel=$(_log_rel_path)
        title="${LOG_TAG}${LOG_CONTEXT:+ $LOG_CONTEXT} ${level}"
        body=$(printf '%s\nLog: %s' "$line" "$rel")
        # Fire-and-forget. The dispatcher is expected to handle its own errors.
        ( "$LOG_NOTIFY_CMD" -p high -t "$title" "$body" >/dev/null 2>&1 & )
    fi
}

# Public helper: print where logs are going. Useful for early diagnostic output
# that callers might want to echo.
log_file() {
    [ -z "$_LOG_FILE" ] && _log_init_file
    printf '%s' "$_LOG_FILE"
}
