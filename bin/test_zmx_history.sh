#!/usr/bin/env bash
# Regression tests for persistent zmx scrollback snapshots.

set -uo pipefail

UNDER_TEST="$(cd "$(dirname "$0")" && pwd)/zmx-history"
SELECT_UNDER_TEST="$(cd "$(dirname "$0")" && pwd)/zmx-select"
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

mkdir -p "$FAKE_ROOT/logs" "$HISTORY_DIR" "$RUNTIME_DIR" "$STUBS"
printf 'alpha\n' > "$FAKE_ROOT/sessions"
printf '%0120d TAIL-INITIAL\n' 0 > "$FAKE_ROOT/history-alpha"
: > "$FAKE_ROOT/logs/alpha.log"
: > "$FAKE_ROOT/history.calls"

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
        cat "$FAKE_ROOT/history-$2"
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
    bash -c '[[ $(wc -l < "$1") -gt $2 ]]' _ "$FAKE_ROOT/history.calls" "$calls_before"
inode_after=$(stat -c '%i' "$snapshot")
check "unchanged history is not rewritten" "$inode_before" "$inode_after"

kill -KILL "$DAEMON_PID"
wait "$DAEMON_PID" 2>/dev/null || true
DAEMON_PID=""
check "snapshot survives abrupt daemon stop" "second snapshot" "$("$UNDER_TEST" show alpha)"

: > "$FAKE_ROOT/sessions"
: > "$TMP/empty-sessions"
cat > "$STUBS/fzf" <<'EOF'
#!/usr/bin/env bash
cat > "$FZF_INPUT"
exit 130
EOF
chmod +x "$STUBS/fzf"
export FZF_INPUT="$TMP/fzf-input"
PATH="$STUBS:$PATH" ZMX_SESSIONS_FILE="$TMP/empty-sessions" \
    "$SELECT_UNDER_TEST" >/dev/null 2>&1 || true
saved_row=$(rg -N '^alpha.*\(saved\)$' "$FZF_INPUT" || true)
check "picker lists stopped ad-hoc sessions with snapshots" "alpha           (saved)" "$saved_row"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]
