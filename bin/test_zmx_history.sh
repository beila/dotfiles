#!/usr/bin/env bash
# Regression tests for persistent zmx scrollback snapshots.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "$0")" && pwd)/zmx-history"
SELECT_UNDER_TEST="$(cd "$(dirname "$0")" && pwd)/zmx-select"
RESTORE_UNDER_TEST="$(cd "$(dirname "$0")" && pwd)/zmx-restore"
ZSH_HOOK="$(cd "$(dirname "$0")/../zsh" && pwd)/zmx-history.zsh"
TMP=$(mktemp -d)
FAKE_ROOT="$TMP/fake"
HISTORY_DIR="$TMP/history"
RUNTIME_DIR="$TMP/runtime"
STUBS="$TMP/stubs"
SAVED_CWD="$TMP/saved cwd"
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

mkdir -p "$FAKE_ROOT/logs" "$HISTORY_DIR" "$RUNTIME_DIR" "$STUBS" "$SAVED_CWD"
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
        if [[ -n "${ZMX_LIST_DETAILS_FILE:-}" && "${2:-}" != "--short" ]]; then
            cat "$ZMX_LIST_DETAILS_FILE"
        elif [[ "${2:-}" != "--short" ]]; then
            while IFS= read -r session; do
                [[ -n "$session" ]] \
                    && printf 'name=%s\tpid=999\tclients=0\n' "$session"
            done < "$FAKE_ROOT/sessions"
        else
            cat "$FAKE_ROOT/sessions"
        fi
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
"$UNDER_TEST" snapshot alpha "$SAVED_CWD"
check "one-shot command captures final output" "one-shot final" "$("$UNDER_TEST" show alpha)"
check "one-shot command captures cwd" "$SAVED_CWD" "$("$UNDER_TEST" cwd alpha)"
check "cwd metadata is private" "600" "$(stat -c '%a' "${snapshot%.history}.cwd")"
check "list can return saved cwd metadata in one call" \
    $'alpha\t'"${SAVED_CWD/#$HOME/'~'}" \
    "$("$UNDER_TEST" list --with-cwd | rg '^alpha\t')"

SECOND_CWD="$TMP/second cwd"
mkdir -p "$SECOND_CWD"
inode_before=$(stat -c '%i' "$snapshot")
"$UNDER_TEST" snapshot alpha "$SECOND_CWD"
inode_after=$(stat -c '%i' "$snapshot")
check "cwd changes do not rewrite unchanged scrollback" "$inode_before" "$inode_after"
check "cwd changes persist with unchanged scrollback" "$SECOND_CWD" "$("$UNDER_TEST" cwd alpha)"

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
HOOK_CWD="$TMP/hook cwd"
mkdir -p "$HOOK_CWD"
(
    cd "$HOOK_CWD" || exit
    ZMX_SESSION=alpha DOTFILES_ROOT="$(cd "$(dirname "$UNDER_TEST")/.." && pwd)" \
        zsh -f -c "source '$ZSH_HOOK'"
)
check "zsh normal exit captures final output" \
    "normal exit final" "$("$UNDER_TEST" show alpha)"
check "zsh normal exit captures final cwd" "$HOOK_CWD" "$("$UNDER_TEST" cwd alpha)"

printf 'removable snapshot\n' > "$FAKE_ROOT/history-beta"
"$UNDER_TEST" snapshot beta "$SAVED_CWD"
removable_snapshot=$("$UNDER_TEST" path beta)
removable_name="${removable_snapshot%.history}.name"
removable_cwd="${removable_snapshot%.history}.cwd"
check "remove target exists before deletion" "yes" \
    "$([[ -f "$removable_snapshot" && -f "$removable_name" && -f "$removable_cwd" ]] && printf yes || printf no)"
"$UNDER_TEST" remove beta
check "remove deletes snapshot and metadata" "no" \
    "$([[ -e "$removable_snapshot" || -e "$removable_name" || -e "$removable_cwd" ]] && printf yes || printf no)"
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

restore_snapshot="$TMP/restore.history"
seq -f 'line-%g' 1 55 > "$restore_snapshot"
cat > "$STUBS/restore-shell" <<'EOF'
#!/usr/bin/env bash
printf 'PROMPT:%s:%s\n' "$PWD" "$*"
EOF
chmod +x "$STUBS/restore-shell"
restore_output=$(ZMX_RESTORE_SHELL="$STUBS/restore-shell" \
    "$RESTORE_UNDER_TEST" "$restore_snapshot" "$HOOK_CWD")
check "restore prints only the trailing output" "line-6" \
    "$(printf '%s\n' "$restore_output" | sed -n '1p')"
check "restore prints output before the shell prompt" "line-55" \
    "$(printf '%s\n' "$restore_output" | sed -n '50p')"
check "restore starts the shell in the saved cwd" "PROMPT:$HOOK_CWD:-l" \
    "$(printf '%s\n' "$restore_output" | tail -n 1)"
check "restore removes its staged snapshot" "no" \
    "$([[ -e "$restore_snapshot" ]] && printf yes || printf no)"

: > "$FAKE_ROOT/sessions"
cat > "$STUBS/fzf" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$FZF_ARGS"
cat > "$FZF_RAW_INPUT"
sed $'s/\033\\[[0-9;]*m//g' "$FZF_RAW_INPUT" > "$FZF_INPUT"
if [[ -n "${FZF_ESC_CALL:-}" ]]; then
    count=0
    [[ -f "$FZF_CALL_COUNT" ]] && read -r count < "$FZF_CALL_COUNT"
    count=$((count + 1))
    printf '%s\n' "$count" > "$FZF_CALL_COUNT"
    if [[ "$count" -eq "$FZF_ESC_CALL" ]]; then
        printf '\nesc\n\n'
        exit 0
    elif [[ "$count" -gt "$FZF_ESC_CALL" ]]; then
        exit 130
    fi
fi
if [[ -n "${FZF_RESPONSES_DIR:-}" ]]; then
    count=0
    [[ -f "$FZF_CALL_COUNT" ]] && read -r count < "$FZF_CALL_COUNT"
    count=$((count + 1))
    printf '%s\n' "$count" > "$FZF_CALL_COUNT"
    response="$FZF_RESPONSES_DIR/$count"
    [[ -f "$response" ]] || exit 130
    cat "$response"
    exit 0
fi
if [[ -s "${FZF_OUTPUT_FILE:-}" ]]; then
    cat "$FZF_OUTPUT_FILE"
    : > "$FZF_OUTPUT_FILE"
    exit 0
fi
exit 130
EOF
chmod +x "$STUBS/fzf"
cat > "$STUBS/xprop" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$XPROP_CALLS"
EOF
chmod +x "$STUBS/xprop"
cat > "$STUBS/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "$*" == "-x zmx" ]] || exit 2
[[ -n "${PGREP_OUTPUT_FILE:-}" ]] && cat "$PGREP_OUTPUT_FILE"
EOF
chmod +x "$STUBS/pgrep"
export XPROP_CALLS="$TMP/xprop-calls"
: > "$XPROP_CALLS"
export FZF_ARGS="$TMP/fzf-args"
export FZF_INPUT="$TMP/fzf-input"
export FZF_RAW_INPUT="$TMP/fzf-raw-input"
export FZF_OUTPUT_FILE="$TMP/fzf-output"
export FZF_CALL_COUNT="$TMP/fzf-call-count"
: > "$FZF_OUTPUT_FILE"

FAKE_PROC="$TMP/proc"
ZMX_LIST_DETAILS="$TMP/zmx-list-details"
PGREP_OUTPUT="$TMP/pgrep-output"
mkdir -p "$FAKE_PROC"/{101,111,121,201,202,203,211,212,999}
ln -s "$HOOK_CWD" "$FAKE_PROC/101/cwd"
ln -s "$HOOK_CWD" "$FAKE_PROC/121/cwd"
printf 'Name:\tzsh\nPPid:\t201\n' > "$FAKE_PROC/101/status"
printf 'Name:\tzsh\nPPid:\t211\n' > "$FAKE_PROC/111/status"
printf '101 (zsh) S 201 101 101 34816 101 0\n' > "$FAKE_PROC/101/stat"
printf '111 (zsh) S 211 111 111 34816 311 0\n' > "$FAKE_PROC/111/stat"
printf '121 (zsh) S 221 121 121 34816 121 0\n' > "$FAKE_PROC/121/stat"
printf '999 (zsh) S 299 999 999 34816 999 0\n' > "$FAKE_PROC/999/stat"
printf 'zmx\0attach\0attached\0zsh\0-l\0' > "$FAKE_PROC/201/cmdline"
printf 'zmx\0tail\0attached\0' > "$FAKE_PROC/202/cmdline"
printf 'zmx\0attach\0attached\0zsh\0-l\0' > "$FAKE_PROC/203/cmdline"
printf 'zmx\0attach\0preview-only\0zsh\0-l\0' > "$FAKE_PROC/211/cmdline"
printf 'zmx\0tail\0preview-only\0' > "$FAKE_PROC/212/cmdline"
printf '201\n202\n203\n211\n212\n' > "$PGREP_OUTPUT"
printf 'name=attached\tpid=101\tclients=2\nname=preview-only\tpid=111\tclients=1\nname=shelp2\tpid=121\tclients=0\n' \
    > "$ZMX_LIST_DETAILS"
export ZMX_PROC_ROOT="$FAKE_PROC"
PATH="$STUBS:$PATH" \
    ZMX_LIST_DETAILS_FILE="$ZMX_LIST_DETAILS" PGREP_OUTPUT_FILE="$PGREP_OUTPUT" \
    "$SELECT_UNDER_TEST" >/dev/null 2>"$TMP/select-attached.stderr" || true
check "picker marks a real attach client despite a concurrent preview" "yes" \
    "$(rg -q '^attached ❯ 🔗' "$FZF_INPUT" && printf yes || printf no)"
check "picker does not mark a server with only a preview client" "yes" \
    "$(rg -q '^preview-only ●[[:space:]]' "$FZF_INPUT" \
        && ! rg -q '^preview-only .*🔗' "$FZF_INPUT" \
        && printf yes || printf no)"
check "picker marks a shell-owned foreground group as a prompt" "yes" \
    "$(rg -q '^shelp2 ❯[[:space:]]' "$FZF_INPUT" && printf yes || printf no)"
active_marker=$'\033[38;5;214m●\033[39m'
prompt_marker=$'\033[32m❯\033[39m'
check "picker gives active jobs a distinct orange marker" "yes" \
    "$(rg -Fq "$active_marker" "$FZF_RAW_INPUT" && printf yes || printf no)"
check "picker gives prompts a distinct green marker" "yes" \
    "$(rg -Fq "$prompt_marker" "$FZF_RAW_INPUT" && printf yes || printf no)"
highlighted_help_name=$'\033[1ms\033[22;2mhelp\033[22;1m2\033[22m'
check "picker dims help and highlights the rest of session names" "yes" \
    "$(rg -Fq "$highlighted_help_name" "$FZF_RAW_INPUT" && printf yes || printf no)"
highlighted_plain_name=$'\033[1mattached\033[22m'
check "picker highlights session names without help" "yes" \
    "$(rg -Fq "$highlighted_plain_name" "$FZF_RAW_INPUT" && printf yes || printf no)"
check "picker enables ANSI row styling" "--ansi" \
    "$(rg -N -Fx -- "--ansi" "$FZF_ARGS" || true)"
attached_row=$(rg -N '^attached[[:space:]]' "$FZF_INPUT")
plain_row=$(rg -N '^shelp2[[:space:]]' "$FZF_INPUT")
check "status emoji preserve the cwd column" "16" \
    "$(printf '%s' "${attached_row%"$HOOK_CWD"}" | wc -L)"
check "unmarked sessions use the same cwd column" "16" \
    "$(printf '%s' "${plain_row%"$HOOK_CWD"}" | wc -L)"

PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" >/dev/null 2>"$TMP/select.stderr" || true
if [[ ! -e "$FZF_INPUT" ]]; then
    cat "$TMP/select.stderr" >&2
fi
saved_row=$(rg -N '^alpha[[:space:]]' "$FZF_INPUT" || true)
printf -v expected_saved_row '%-16s  %s' "alpha ×" "$HOOK_CWD"
check "picker lists stopped sessions with snapshots and cwd" "$expected_saved_row" "$saved_row"
dead_marker=$'\033[31m×\033[39m'
check "picker gives stopped sessions a distinct red marker" "yes" \
    "$(rg -Fq "$dead_marker" "$FZF_RAW_INPUT" && printf yes || printf no)"
check "picker header explains the compact activity markers" "yes" \
    "$(rg -q '●.*active.*❯.*prompt.*×.*dead' "$FZF_ARGS" && printf yes || printf no)"
check "picker omits obsolete preset sessions" "" "$(rg -N '^work1' "$FZF_INPUT" || true)"
preview_cycle='--bind=ctrl-/:change-preview-window(down,50%|hidden|)'
check "picker cycles horizontal, vertical, and hidden previews" "$preview_cycle" \
    "$(rg -N -Fx -- "$preview_cycle" "$FZF_ARGS" || true)"
check "picker leaves mouse dragging available for terminal text selection" "--no-mouse" \
    "$(rg -N -Fx -- "--no-mouse" "$FZF_ARGS" || true)"
initial_expect_arg="--expect=ctrl-n,ctrl-d,esc"
check "initial picker leaves Ctrl-backslash unbound" \
    "$initial_expect_arg" \
    "$(rg -N -F -- "$initial_expect_arg" "$FZF_ARGS" || true)"

printf '\nctrl-d\n%s\n' "$expected_saved_row" > "$FZF_OUTPUT_FILE"
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

printf 'previous snapshot\n' > "$FAKE_ROOT/history-previous"
"$UNDER_TEST" snapshot previous
printf '\n\nprevious\n' > "$FZF_OUTPUT_FILE"
: > "$XPROP_CALLS"
: > "$FAKE_ROOT/attach.calls"
WINDOWID=123 PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" \
    >/dev/null 2>"$TMP/select-previous.stderr" || true
check "picker reselects previous session after attach returns" "load:pos(1)" \
    "$(rg -N '^load:pos' "$FZF_ARGS" || true)"
check "picker keeps previous session in title property" \
    "-id 123 -f _ZMX_SESSION 8u -set _ZMX_SESSION previous" \
    "$(tail -n 1 "$XPROP_CALLS")"
restore_attach=no
rg -q '^attach previous .*/zmx-restore .*/zmx-restore\.' \
    "$FAKE_ROOT/attach.calls" && restore_attach=yes
check "picker restores stopped sessions through the bootstrap" "yes" "$restore_attach"
"$UNDER_TEST" remove previous

printf 'return\n' > "$FAKE_ROOT/sessions"
printf '\n\nreturn\n' > "$FZF_OUTPUT_FILE"
: > "$FAKE_ROOT/attach.calls"
: > "$FZF_CALL_COUNT"
FZF_ESC_CALL=2 PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" \
    >/dev/null 2>"$TMP/select-escape.stderr" || true
check "Escape after detach reattaches the same session" \
    $'attach return zsh -l\nattach return zsh -l' \
    "$(cat "$FAKE_ROOT/attach.calls")"

printf 'first\nsecond\n' > "$FAKE_ROOT/sessions"
responses="$TMP/fzf-responses"
mkdir -p "$responses"
printf '\n\nfirst\n' > "$responses/1"
printf '\n\nsecond\n' > "$responses/2"
printf '\nctrl-\\\n\n' > "$responses/3"
printf '\nctrl-\\\n\n' > "$responses/4"
: > "$FAKE_ROOT/attach.calls"
: > "$FZF_CALL_COUNT"
FZF_RESPONSES_DIR="$responses" PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" \
    >/dev/null 2>"$TMP/select-toggle.stderr" || true
check "repeated Ctrl-backslash alternates between the last two sessions" \
    $'attach first zsh -l\nattach second zsh -l\nattach first zsh -l\nattach second zsh -l' \
    "$(cat "$FAKE_ROOT/attach.calls")"
switch_expect_arg="--expect=ctrl-n,ctrl-d,esc,ctrl-\\"
check "picker binds Ctrl-backslash when a switch target exists" \
    "$switch_expect_arg" \
    "$(rg -N -F -- "$switch_expect_arg" "$FZF_ARGS" || true)"
check "picker marks the last session with a compact rank" "yes" \
    "$(rg -q '^second ❯ 🥇' "$FZF_INPUT" && printf yes || printf no)"
check "picker marks the previous session with a compact rank" "yes" \
    "$(rg -q '^first ❯ 🥈' "$FZF_INPUT" && printf yes || printf no)"

printf 'only\n' > "$FAKE_ROOT/sessions"
single_responses="$TMP/fzf-single-responses"
mkdir -p "$single_responses"
printf '\n\nonly\n' > "$single_responses/1"
printf '\nctrl-\\\n\n' > "$single_responses/2"
: > "$FAKE_ROOT/attach.calls"
: > "$FZF_CALL_COUNT"
FZF_RESPONSES_DIR="$single_responses" PATH="$STUBS:$PATH" "$SELECT_UNDER_TEST" \
    >/dev/null 2>"$TMP/select-single-toggle.stderr" || true
check "Ctrl-backslash reattaches the latest session before a previous one exists" \
    $'attach only zsh -l\nattach only zsh -l' \
    "$(cat "$FAKE_ROOT/attach.calls")"
check "single-session picker marks only the last session" "yes" \
    "$(rg -q '^only ❯ 🥇' "$FZF_INPUT" \
        && ! rg -q '🥈' "$FZF_INPUT" \
        && printf yes || printf no)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
