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
# One-shot callers can use the `dlog` CLI wrapper on PATH (see bin/dlog).
# The wrapper is named `dlog` rather than `log` because zsh has a `log` builtin
# that shadows PATH entries.
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
# Log-file retention:
#   By default the log file is KEPT only when the run produced at least one
#   event at level >= $LOG_KEEP_THRESHOLD (default ERROR). Clean runs leave no
#   file behind. Implementation: all writes go to a /tmp file during the run;
#   the temp file is moved to the final $LOG_ROOT path at log_finalize (auto-
#   triggered by an EXIT trap, or callable explicitly). Clean runs delete the
#   temp file instead. Notifications contain the final path even though the
#   file isn't there yet during the run — by the time the user opens the
#   notification (post-exit), log_finalize has moved the file into place.
#   Set LOG_KEEP_THRESHOLD=DEBUG to keep every file; NEVER (case-insensitive)
#   to always delete.
#   Critical invariant: $LOG_ROOT is never written to DURING a run. Safe to
#   set $LOG_ROOT inside a synced jj/git repo without creating self-referential
#   race conditions (the file only lands under $LOG_ROOT after the process
#   exits, so the repo it's inside can be safely sync'd mid-process).
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
#     LOG_NOTIFY_DEDUP_WINDOW   seconds; suppress re-notification of the same
#                               (TAG, CONTEXT, LEVEL, normalized-msg) signature
#                               within this window. Default 21600 (6h); 0 disables.
#     LOG_NOTIFY_DEDUP_DIR      directory for dedup state files; default
#                               $LOG_ROOT/.notify-dedup
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
# Notification deduplication: suppress re-notification if the same
# (TAG, CONTEXT, LEVEL, normalized-message) signature was already notified
# within this many seconds. Normalization collapses hex IDs (≥8 chars) and
# multi-digit numbers so "REBASE-CONFLICT main local=abc123 remote=def456"
# matches the next run's "REBASE-CONFLICT main local=xyz789 remote=uvw012".
# Default 6 hours. Set to 0 to disable.
: "${LOG_NOTIFY_DEDUP_WINDOW:=21600}"
: "${LOG_NOTIFY_DEDUP_DIR:=$LOG_ROOT/.notify-dedup}"
# Keep the log file only if the run produced an event at this level or higher.
# Set to DEBUG to keep every run; NEVER to always delete.
: "${LOG_KEEP_THRESHOLD:=ERROR}"
# Notification deduplication: suppress a notification if the same
# (TAG, CONTEXT, LEVEL, normalized-message) signature was already notified
# within this many seconds. Defaults to 6 hours. Set to 0 to disable.
: "${LOG_NOTIFY_DEDUP_WINDOW:=21600}"
: "${LOG_NOTIFY_DEDUP_DIR:=$LOG_ROOT/.notify-dedup}"

# Machine name matches sync_repo's convention.
if [ -z "${LOG_MACHINE_NAME:-}" ]; then
    LOG_MACHINE_NAME=$(hostnamectl --pretty 2>/dev/null | grep -v '\.')
    LOG_MACHINE_NAME=${LOG_MACHINE_NAME:-$(hostname -s 2>/dev/null || echo unknown)}
fi

_LOG_FILE=""
_LOG_FINAL_FILE=""
_LOG_TEMP_FILE=""
_LOG_RUN_START=""
_LOG_MAX_LEVEL_NUM=0
_LOG_FILE_CREATED_BY_US=0
_LOG_EXIT_INSTALLED=0
# Signatures (sha1 hashes) accumulated for dedup-state persistence at
# log_finalize. Deferred so we never touch $LOG_NOTIFY_DEDUP_DIR mid-run.
_LOG_PENDING_DEDUP_KEYS=""

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
    # Computes the FINAL destination path, but initially directs writes to a
    # /tmp temp file. The temp file is promoted to the final path when the run
    # records an event at >= LOG_KEEP_THRESHOLD (or via explicit log_finalize).
    # Clean runs never touch $LOG_ROOT on disk — critical for setups where
    # $LOG_ROOT lives inside a synced jj/git repo.
    _LOG_RUN_START=$(date +%s)
    local dir="$LOG_ROOT/$LOG_MACHINE_NAME"

    local date_part today_time
    date_part=$(date -d "@$_LOG_RUN_START" +%Y%m%d 2>/dev/null) || date_part=$(date +%Y%m%d)
    today_time=$(date -d "@$_LOG_RUN_START" +%H%M%S 2>/dev/null) || today_time=$(date +%H%M%S)

    # Build base name with optional CONTEXT.
    local base
    if [ -n "$LOG_CONTEXT" ]; then
        # Sanitize: replace slashes and whitespace with '-', strip leading '.'
        # and '-' so basenames like ".dotfiles" or "/foo" don't yield
        # "tag..dotfiles.log" / "tag.-foo.log".
        local ctx_safe
        ctx_safe=$(printf '%s' "$LOG_CONTEXT" | tr '/ ' '--' | sed 's/^[.-]*//')
        base="${LOG_TAG}.${ctx_safe}.${date_part}"
    else
        base="${LOG_TAG}.${date_part}"
    fi

    local undecorated="$dir/$base.log"
    if [ -e "$undecorated" ]; then
        # A prior run today already claimed the undecorated name; use timestamped.
        _LOG_FINAL_FILE="$dir/$base.$today_time.log"
    else
        _LOG_FINAL_FILE="$undecorated"
    fi

    # Create temp file in /tmp (OS-managed). If mktemp fails, fall back to
    # writing directly to final file so we don't lose events.
    _LOG_TEMP_FILE=$(mktemp "${TMPDIR:-/tmp}/log.${LOG_TAG}.XXXXXX" 2>/dev/null)
    if [ -n "$_LOG_TEMP_FILE" ]; then
        _LOG_FILE="$_LOG_TEMP_FILE"
    else
        mkdir -p "$dir" 2>/dev/null
        _LOG_FILE="$_LOG_FINAL_FILE"
    fi
    _LOG_FILE_CREATED_BY_US=1

    # Install EXIT trap (once per process) so we can retroactively delete the
    # file if no event at/above LOG_KEEP_THRESHOLD was recorded. We install
    # unconditionally — any inherited trap from a parent shell is dormant in
    # this (sub)shell and overwriting it only affects this process. If a
    # caller sets their own EXIT trap AFTER sourcing log.sh, they must call
    # log_finalize themselves.
    if [ "$_LOG_EXIT_INSTALLED" -eq 0 ]; then
        trap log_finalize EXIT
        _LOG_EXIT_INSTALLED=1
    fi
}

# Promote the temp file to the final location. Called automatically on the
# first log event at >= LOG_KEEP_THRESHOLD, and by log_finalize() when the run
# ends with an event that warrants retention.
_log_promote_to_final() {
    [ -z "$_LOG_TEMP_FILE" ] && return 0   # already promoted or not using temp
    [ ! -f "$_LOG_TEMP_FILE" ] && return 0 # somehow gone

    mkdir -p "$(dirname "$_LOG_FINAL_FILE")" 2>/dev/null

    # Re-check the "first run of day" claim at promote time. If a concurrent
    # run took the undecorated name between our init and now, fall through to
    # a timestamped name so we don't clobber.
    if [ -e "$_LOG_FINAL_FILE" ]; then
        local hms
        hms=$(date -d "@$_LOG_RUN_START" +%H%M%S 2>/dev/null || date +%H%M%S)
        _LOG_FINAL_FILE="${_LOG_FINAL_FILE%.log}.$hms.log"
        # Preserve the undecorated one; still clobber-safe.
    fi

    if mv "$_LOG_TEMP_FILE" "$_LOG_FINAL_FILE" 2>/dev/null; then
        _LOG_FILE="$_LOG_FINAL_FILE"
        _LOG_TEMP_FILE=""
    fi
}

# Discard the log file if the run didn't reach LOG_KEEP_THRESHOLD. If it did,
# promote the temp file to its final location (idempotent).
log_finalize() {
    [ -z "$_LOG_FILE" ] && return 0
    [ "$_LOG_FILE_CREATED_BY_US" -ne 1 ] && return 0

    local keep_num
    case "$(printf '%s' "$LOG_KEEP_THRESHOLD" | tr '[:lower:]' '[:upper:]')" in
        NEVER) keep_num=999 ;;  # always delete
        *)     keep_num=$(_log_level_num "$LOG_KEEP_THRESHOLD") ;;
    esac
    [ "$keep_num" -eq 0 ] && keep_num=$(_log_level_num ERROR)  # invalid → default

    if [ "$_LOG_MAX_LEVEL_NUM" -ge "$keep_num" ]; then
        # Keep the log: make sure it's at the final location.
        _log_promote_to_final
    else
        # Discard the log: remove temp (or final file if we bypassed temp).
        if [ -n "$_LOG_TEMP_FILE" ] && [ -f "$_LOG_TEMP_FILE" ]; then
            rm -f "$_LOG_TEMP_FILE"
        elif [ -f "$_LOG_FILE" ]; then
            rm -f "$_LOG_FILE"
        fi
        _LOG_TEMP_FILE=""
    fi
    # Persist deferred dedup state (no-op if none pending).
    _log_flush_dedup_state
    _LOG_FILE_CREATED_BY_US=0   # prevent double-finalize
}

_log_rel_path() {
    # Print the FINAL destination path relative to $LOG_REL_BASE if possible.
    # We always use the final path for notification bodies so the notification
    # links to a location that exists after log_finalize (the current file may
    # still be in /tmp during the run).
    local p="${_LOG_FINAL_FILE:-$_LOG_FILE}"
    case "$p" in
        "$LOG_REL_BASE"/*) printf '%s' "${p#"$LOG_REL_BASE"/}" ;;
        *)                 printf '%s' "$p" ;;
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

# Build a dedup key from TAG, CONTEXT, LEVEL, and a *normalized* message so
# that repeated errors whose only difference is rev hashes / timestamps /
# numeric IDs collapse to one signature. Printed as a hex digest.
_log_dedup_key() {
    local level=$1 msg=$2 normalized
    # Collapse: hex runs of ≥8 chars → X (commit IDs, UUIDs)
    #          : digit runs of ≥2 chars → N (timestamps, rcs, sizes)
    normalized=$(printf '%s' "$msg" | sed -E 's/[0-9a-fA-F]{8,}/X/g; s/[0-9]{2,}/N/g')
    printf '%s\n%s\n%s\n%s' "$LOG_TAG" "$LOG_CONTEXT" "$level" "$normalized" \
        | sha1sum | awk '{print $1}'
}

# Returns 0 if the caller should proceed with notification; 1 to suppress it.
# Dedup state writes are deferred to log_finalize so the dedup dir under
# $LOG_ROOT isn't touched mid-run (important when $LOG_ROOT is inside a
# synced repo). We read existing on-disk state to honour prior-run dedup.
_log_notify_dedup_ok() {
    [ "${LOG_NOTIFY_DEDUP_WINDOW:-0}" -le 0 ] && return 0
    local key=$1
    local f="$LOG_NOTIFY_DEDUP_DIR/$key"
    # On-disk state from previous processes
    if [ -f "$f" ]; then
        local last_ts now
        last_ts=$(stat -c %Y "$f" 2>/dev/null || echo 0)
        now=$(date +%s)
        if [ $((now - last_ts)) -lt "$LOG_NOTIFY_DEDUP_WINDOW" ]; then
            return 1
        fi
    fi
    # In-process state from earlier calls in THIS run
    case "$_LOG_PENDING_DEDUP_KEYS" in
        *" $key "*) return 1 ;;
    esac
    # Record intent to persist this key on log_finalize.
    _LOG_PENDING_DEDUP_KEYS="$_LOG_PENDING_DEDUP_KEYS $key "
    return 0
}

# Persist deferred dedup keys to $LOG_NOTIFY_DEDUP_DIR.
_log_flush_dedup_state() {
    [ -z "$_LOG_PENDING_DEDUP_KEYS" ] && return 0
    mkdir -p "$LOG_NOTIFY_DEDUP_DIR" 2>/dev/null || return 0
    local key
    for key in $_LOG_PENDING_DEDUP_KEYS; do
        : > "$LOG_NOTIFY_DEDUP_DIR/$key"
    done
    _LOG_PENDING_DEDUP_KEYS=""
}

log() {
    local level=$1; shift
    local msg="$*"

    [ -z "$_LOG_FILE" ] && _log_init_file

    local level_num
    level_num=$(_log_level_num "$level")
    if [ "$level_num" -gt "$_LOG_MAX_LEVEL_NUM" ]; then
        _LOG_MAX_LEVEL_NUM=$level_num
    fi

    local line
    line=$(printf '%s [%s] [%s]%s %s' \
        "$(date -Iseconds)" \
        "$LOG_TAG" \
        "$level" \
        "${LOG_CONTEXT:+ [$LOG_CONTEXT]}" \
        "$msg")

    # Always append to the log file (the /tmp temp until log_finalize).
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
    local threshold_num
    threshold_num=$(_log_level_num "$LOG_NOTIFY_THRESHOLD")

    if [ "$level_num" -ge "$threshold_num" ] && _log_should_notify; then
        local key
        key=$(_log_dedup_key "$level" "$msg")
        if _log_notify_dedup_ok "$key"; then
            local rel body title
            rel=$(_log_rel_path)
            title="${LOG_TAG}${LOG_CONTEXT:+ $LOG_CONTEXT} ${level}"
            # Body is just the message; the title already carries
            # tag/context/level, and the notifier (Telegram, etc.) shows
            # its own timestamp — no need to repeat ours.
            body=$(printf '%s\nLog: %s' "$msg" "$rel")
            # Fire-and-forget. The dispatcher is expected to handle its own errors.
            ( "$LOG_NOTIFY_CMD" -p high -t "$title" "$body" >/dev/null 2>&1 & )
        fi
    fi
}

# Public helper: print where logs are going. Useful for early diagnostic output
# that callers might want to echo.
log_file() {
    [ -z "$_LOG_FILE" ] && _log_init_file
    printf '%s' "$_LOG_FILE"
}
