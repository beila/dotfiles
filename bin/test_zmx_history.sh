#!/usr/bin/env bash
# Regression tests for persistent zmx scrollback snapshots.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "$0")" && pwd)/zmx-history"
SELECT_UNDER_TEST="$(cd "$(dirname "$0")" && pwd)/zmx-select"
ZSH_HOOK="$(cd "$(dirname "$0")/../zsh" && pwd)/zmx-history.zsh"
TMP=$(mktemp -d)
FAKE_ROOT="$TMP/fake"
HISTORY_DIR="$TMP/history"
RUNTIME_DIR="$TMP/runtime"
STUBS="$TMP/stubs"
DAEMON_PID=""
PASS=0
FAIL=0

cleanup() {
    if [[ -n "$DAEMON_PID" ]]; then
        kill "$DAEMON_PID" 2>/dev/null || true
        wait "$DAEMON_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT

check() {
    local description=$1 expected=$2 actual=$3
    if [[ "$expected" == "$actual" ]]; then
        printf 'PASS: %s\n' "$description"
        PASS=$((PASS + 1))
    else
        printf 'FAIL: %s\n  expected: %q\n  actual:   %q\n' \
            "$description" "$expected" "$actual"
        FAIL=$((FAIL + 1))
    fi
}

wait_for() {
    local description=$1
    shift
    local _
    for _ in {1..100}; do
        "$@" && return 0
        sleep 0.05
    done
    printf 'FAIL: timed out waiting for %s\n' "$description"
    FAIL=$((FAIL + 1))
    return 1
}

calls_exceed() {
    [[ $(wc -l < "$1") -gt $2 ]]
}

mkdir -p "$FAKE_ROOT/logs" "$HISTORY_DIR" "$RUNTIME_DIR" "$STUBS"
printf 'alpha\n' > "$FAKE_ROOT/sessions"
printf '%0120d TAIL-INITIAL\n' 0 > "$FAKE_ROOT/history-alpha"
: > "$FAKE_ROOT/logs/alpha.log"
: > "$FAKE_ROOT/history.calls"
: > "$FAKE_ROOT/attach.calls"

cat > "$STUBS/zmx" <<'EOF'
#!/usr/bin/env bash
set -u
case "${1:-}" in
    version)
        printf 'zmx\tfake\nsocket_dir\t%s/sockets\nlog_dir\t%s/logs\n' \
            "$FAKE_ROOT" "$FAKE_ROOT"
        ;;
    list)
        while IFS= read -r session; do
            [[ -n "$session" ]] && printf 'list\n' >> "$FAKE_ROOT/logs/$session.log"
        done < "$FAKE_ROOT/sessions"
        cat "$FAKE_ROOT/sessions"
        ;;
    history)
        printf '%s\n' "$2" >> "$FAKE_ROOT/history.calls"
        printf 'history\n' >> "$FAKE_ROOT/logs/$2.log"
        content=$(cat "$FAKE_ROOT/history-$2")
        if [[ -e "$FAKE_ROOT/history.delay" ]]; then
            rm -f "$FAKE_ROOT/history.delay"
            : > "$FAKE_ROOT/history.delay.started"
            sleep 0.3
        fi
        printf '%s\n' "$content"
        ;;
    attach)
        printf '%s\n' "$*" >> "$FAKE_ROOT/attach.calls"
        ;;
    *)
        exit 2
        ;;
esac
EOF
chmod +x "$STUBS/zmx"

export FAKE_ROOT
export ZMX_BIN="$STUBS/zmx"
export ZMX_HISTORY_DIR="$HISTORY_DIR"
export ZMX_HISTORY_MAX_BYTES=64
export ZMX_HISTORY_SCAN_SECONDS=0.1
export ZMX_HISTORY_SESSIONS_FILE="$FAKE_ROOT/sessions"
export XDG_RUNTIME_DIR="$RUNTIME_DIR"

"$UNDER_TEST" &
DAEMON_PID=$!

wait_for "initial snapshot" "$UNDER_TEST" has alpha
snapshot=$("$UNDER_TEST" path alpha)
snapshot_size=$(wc -c < "$snapshot")
snapshot_tail=$("$UNDER_TEST" show alpha | tail -n 1)
check "initial snapshot is capped" "yes" "$([[ $snapshot_size -le 64 ]] && printf yes || printf no)"
check "history directory is private" "700" "$(stat -c '%a' "$HISTORY_DIR")"
check "snapshot file is private" "600" "$(stat -c '%a' "$snapshot")"
check "initial snapshot keeps newest output" "yes" \
    "$(printf '%s\n' "$snapshot_tail" | rg -q 'TAIL-INITIAL$' && printf yes || printf no)"
check "saved session is discoverable" "alpha" "$("$UNDER_TEST" list)"

sleep 0.2
printf 'second snapshot\n' > "$FAKE_ROOT/history-alpha"
printf 'terminal output\n' >> "$FAKE_ROOT/logs/alpha.log"
wait_for "changed snapshot" rg -Fxq "second snapshot" "$snapshot"
check "changed history replaces the snapshot" "second snapshot" "$("$UNDER_TEST" show alpha)"

sleep 0.2
inode_before=$(stat -c '%i' "$snapshot")
calls_before=$(wc -l < "$FAKE_ROOT/history.calls")
printf 'terminal output with unchanged screen\n' >> "$FAKE_ROOT/logs/alpha.log"
wait_for "unchanged history comparison" \
    calls_exceed "$FAKE_ROOT/history.calls" "$calls_before"
inode_after=$(stat -c '%i' "$snapshot")
check "unchanged history is not rewritten" "$inode_before" "$inode_after"

kill -KILL "$DAEMON_PID"
wait "$DAEMON_PID" 2>/dev/null || true
DAEMON_PID=""
check "snapshot survives abrupt daemon stop" "second snapshot" "$("$UNDER_TEST" show alpha)"

printf 'one-shot final\n' > "$FAKE_ROOT/history-alpha"
"$UNDER_TEST" snapshot alpha
check "one-shot command captures final output" "one-shot final" "$("$UNDER_TEST" show alpha)"

printf 'stale concurrent capture\n' > "$FAKE_ROOT/history-alpha"
: > "$FAKE_ROOT/history.delay"
"$UNDER_TEST" snapshot alpha &
snapshot_pid=$!
wait_for "delayed snapshot start" test -e "$FAKE_ROOT/history.delay.started"
printf 'serialized final\n' > "$FAKE_ROOT/history-alpha"
"$UNDER_TEST" snapshot alpha
wait "$snapshot_pid"
check "serialized snapshots keep the newest output" \
    "serialized final" "$("$UNDER_TEST" show alpha)"

printf 'normal exit final\n' > "$FAKE_ROOT/history-alpha"
ZMX_SESSION=alpha DOTFILES_ROOT="$(cd "$(dirname "$UNDER_TEST")/.." && pwd)" \
    zsh -f -c "source '$ZSH_HOOK'"
check "zsh normal exit captures final output" \
    "normal exit final" "$("$UNDER_TEST" show alpha)"

printf 'removable snapshot\n' > "$FAKE_ROOT/history-beta"
"$UNDER_TEST" snapshot beta
removable_snapshot=$("$UNDER_TEST" path beta)
removable_name="${removable_snapshot%.history}.name"
check "remove target exists before deletion" "yes" \
    "$([[ -f "$removable_snapshot" && -f "$removable_name" ]] && printf yes || printf no)"
"$UNDER_TEST" remove beta
check "remove deletes snapshot and name index" "no" \
    "$([[ -e "$removable_snapshot" || -e "$removable_name" ]] && printf yes || printf no)"
check "remove preserves other saved sessions" "alpha" "$("$UNDER_TEST" list)"

real_zmx=$(command -v zmx || true)
if [[ -n "$real_zmx" && -n "$(command -v script)" ]]; then
    repo_root=$(cd "$(dirname "$UNDER_TEST")/.." && pwd)
    real_history="$TMP/real-history"
    printf -v real_command 'env -u ZMX_SESSION %q attach real-normal-exit zsh -lic %q' \
        "$real_zmx" "print -r -- FINAL-ZMX-MARKER"
    real_rc=0
    ZMX_DIR="$TMP/real-zmx" ZMX_HISTORY_DIR="$real_history" \
        ZMX_BIN="$real_zmx" DOTFILES_ROOT="$repo_root" \
        script -qefc "$real_command" /dev/null >/dev/null || real_rc=$?
    check "real zmx session exits cleanly" "0" "$real_rc"
    real_snapshot=$(ZMX_HISTORY_DIR="$real_history" "$UNDER_TEST" path real-normal-exit)
    real_marker=no
    if rg -Fq 'FINAL-ZMX-MARKER' "$real_snapshot"; then
        real_marker=yes
    fi
    check "real zmx normal exit captures final output" "yes" "$real_marker"
fi

: > "$FAKE_ROOT/sessions"
cat > "$STUBS/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FZF_ARGS"
cat > "$FZF_INPUT"
if [[ -s "${FZF_OUTPUT_FILE:-}" ]]; then
    cat "$FZF_OUTPUT_FILE"
    : > "$FZF_OUTPUT_FILE"
    exit 0
fi
exit 130
EOF
chmod +x "$STUBS/fzf"
export FZF_ARGS="$TMP/fzf-args"
export FZF_INPUT="$TMP/fzf-input"
export FZF_OUTPUT_FILE="$TMP/fzf-output"
: > "$FZF_OUTPUT_FILE"
PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" >/dev/null 2>"$TMP/select.stderr" || true
if [[ ! -e "$FZF_INPUT" ]]; then
    cat "$TMP/select.stderr" >&2
fi
saved_row=$(rg -N '^alpha.*\(saved\)$' "$FZF_INPUT" || true)
check "picker lists stopped sessions with snapshots" "alpha           (saved)" "$saved_row"
check "picker omits obsolete preset sessions" "" "$(rg -N '^work1' "$FZF_INPUT" || true)"
preview_cycle='--bind=ctrl-/:change-preview-window(down,50%|hidden|)'
check "picker cycles horizontal, vertical, and hidden previews" "$preview_cycle" \
    "$(rg -N -Fx -- "$preview_cycle" "$FZF_ARGS" || true)"

printf '\nctrl-d\nalpha           (saved)\n' > "$FZF_OUTPUT_FILE"
: > "$FAKE_ROOT/attach.calls"
select_rc=0
PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" >/dev/null 2>"$TMP/select-remove.stderr" || select_rc=$?
check "Ctrl-D exits after removing the final saved entry" "0" "$select_rc"
alpha_saved=yes
"$UNDER_TEST" has alpha || alpha_saved=no
check "Ctrl-D removes the stopped session snapshot" "no" "$alpha_saved"
check "Ctrl-D does not attach a replacement session" "" "$(cat "$FAKE_ROOT/attach.calls")"

printf 'running snapshot\n' > "$FAKE_ROOT/history-gamma"
"$UNDER_TEST" snapshot gamma
printf 'gamma\n' > "$FAKE_ROOT/sessions"
printf '\nctrl-d\ngamma\n' > "$FZF_OUTPUT_FILE"
PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" >/dev/null 2>"$TMP/select-running.stderr" || true
gamma_saved=no
"$UNDER_TEST" has gamma && gamma_saved=yes
check "Ctrl-D preserves a running session snapshot" "yes" "$gamma_saved"
: > "$FAKE_ROOT/sessions"
"$UNDER_TEST" remove gamma

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
