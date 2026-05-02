#!/usr/bin/env bash
# test_log.sh — exhaustive test harness for script/logger/log.sh.
#
# Runs all tests against an isolated temp LOG_ROOT and HJDOCS_ROOT so it
# doesn't touch your real logs. Uses the 'mock' notification backend to
# capture notifications without network calls.
#
# Usage:  bash script/logger/test_log.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
export DOTFILES_ROOT
LIB="$DOTFILES_ROOT/script/logger/log.sh"
CLI="$DOTFILES_ROOT/script/logger/bin/log"

TMPDIR=$(mktemp -d /tmp/test_log.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

pass=0
fail=0
# pass/fail counters are updated by each test via a file (subshells prevent
# direct variable updates from being visible to the parent shell).
PASS_FILE="$TMPDIR/pass"
FAIL_FILE="$TMPDIR/fail"
printf '0' > "$PASS_FILE"
printf '0' > "$FAIL_FILE"
_bump() {
    local f=$1
    local n
    n=$(cat "$f")
    printf '%d' $((n+1)) > "$f"
}
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        printf 'PASS: %s\n' "$label"
        _bump "$PASS_FILE"
    else
        printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$label" "$expected" "$actual"
        _bump "$FAIL_FILE"
    fi
}
check_nonempty() {
    local label=$1 actual=$2
    if [ -n "$actual" ]; then
        printf 'PASS: %s\n' "$label"
        _bump "$PASS_FILE"
    else
        printf 'FAIL: %s (empty)\n' "$label"
        _bump "$FAIL_FILE"
    fi
}
check_contains() {
    local label=$1 haystack=$2 needle=$3
    case "$haystack" in
        *"$needle"*)
            printf 'PASS: %s\n' "$label"
            _bump "$PASS_FILE"
            ;;
        *)
            printf 'FAIL: %s\n  expected to contain: [%s]\n  in: [%s]\n' "$label" "$needle" "$haystack"
            _bump "$FAIL_FILE"
            ;;
    esac
}

# Shared per-test env setup. Each test runs in a subshell so LOG_* and the
# cached _LOG_FILE don't leak between tests.
setup_test_env() {
    export LOG_ROOT="$TMPDIR/logs"
    export LOG_REL_BASE="$TMPDIR"      # so rel path becomes logs/<machine>/...
    export LOG_MACHINE_NAME="testhost"
    export NOTIFY_BACKEND="mock"
    export NOTIFY_MOCK_FILE="$TMPDIR/mock-notifications.log"
    : > "$NOTIFY_MOCK_FILE"
}

echo
echo "=== Test 1: basic log file creation and naming ==="
(
    setup_test_env
    export LOG_TAG="test1"
    # shellcheck source=/dev/null
    source "$LIB"
    log INFO  "hello 1"
    log ERROR "hello 2"
    expected_dir="$TMPDIR/logs/testhost"
    today=$(date +%Y%m%d)
    expected_file="$expected_dir/test1.$today.log"
    check "file created at expected path" "yes" "$([ -f "$expected_file" ] && echo yes || echo no)"
    lines=$(wc -l < "$expected_file")
    check "file has 2 lines" "2" "$lines"
)

echo
echo "=== Test 2: LOG_CONTEXT appears in both filename and each line ==="
(
    setup_test_env
    export LOG_TAG="test2"
    export LOG_CONTEXT="myrepo"
    source "$LIB"
    log INFO  "start"
    today=$(date +%Y%m%d)
    expected_file="$TMPDIR/logs/testhost/test2.myrepo.$today.log"
    check "file name includes context" "yes" "$([ -f "$expected_file" ] && echo yes || echo no)"
    content=$(cat "$expected_file")
    check_contains "line contains context" "$content" "[myrepo]"
)

echo
echo "=== Test 3: CONTEXT with slash sanitized in filename ==="
(
    setup_test_env
    export LOG_TAG="test3"
    export LOG_CONTEXT="/home/user/proj"
    source "$LIB"
    log INFO  "s"
    today=$(date +%Y%m%d)
    expected_file="$TMPDIR/logs/testhost/test3.-home-user-proj.$today.log"
    check "slashes in context replaced" "yes" "$([ -f "$expected_file" ] && echo yes || echo no)"
)

echo
echo "=== Test 4: below-threshold does NOT notify ==="
(
    setup_test_env
    export LOG_TAG="test4"
    source "$LIB"
    log INFO  "ignore me"
    log DEBUG "nor me"
    log WARN  "still below default threshold"
    # Give background notifier time (there shouldn't be one, but just in case)
    sleep 0.2
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "no notifications for sub-threshold" "0" "$mock_lines"
)

echo
echo "=== Test 5: at/above-threshold DOES notify ==="
(
    setup_test_env
    export LOG_TAG="test5"
    export LOG_CONTEXT="ctx"
    source "$LIB"
    log ERROR    "error one"
    log CRITICAL "error two"
    # Wait for background notifier subshells
    sleep 1
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "two notifications fired" "2" "$mock_lines"
    # Each line: <ts>\t<priority>\t<title>\t<url>\t<msg>
    first_title=$(awk -F'\t' 'NR==1{print $3}' "$NOTIFY_MOCK_FILE")
    check_contains "title includes tag and context" "$first_title" "test5"
    check_contains "title includes context"        "$first_title" "ctx"
    check_contains "title includes level"          "$first_title" "ERROR"
    first_msg=$(awk -F'\t' 'NR==1{print $5}' "$NOTIFY_MOCK_FILE")
    check_contains "notification body includes log line" "$first_msg" "error one"
    check_contains "notification body includes rel path"  "$first_msg" "logs/testhost/test5.ctx."
)

echo
echo "=== Test 6: second run same day uses .HHMMSS.log ==="
(
    setup_test_env
    export LOG_TAG="test6"
    # first run
    (
        source "$LIB"
        log INFO "first run"
    )
    # second run in same shell invocation but fresh subshell (cached _LOG_FILE cleared)
    (
        source "$LIB"
        log INFO "second run"
    )
    today=$(date +%Y%m%d)
    count=$(ls "$TMPDIR/logs/testhost/" 2>/dev/null | grep -c "^test6\.")
    check "two distinct files created" "2" "$count"
    undecorated="$TMPDIR/logs/testhost/test6.$today.log"
    check "undecorated file exists" "yes" "$([ -f "$undecorated" ] && echo yes || echo no)"
    # Find the timestamped one
    stamped=$(ls "$TMPDIR/logs/testhost/" | grep "^test6\." | grep -v "^test6\.$today\.log$")
    check_nonempty "timestamped file name" "$stamped"
    case "$stamped" in
        test6.$today.[0-9][0-9][0-9][0-9][0-9][0-9].log)
            printf 'PASS: timestamped file name pattern\n'
            pass=$((pass+1))
            ;;
        *)
            printf 'FAIL: timestamped file name pattern\n  actual: %s\n' "$stamped"
            fail=$((fail+1))
            ;;
    esac
)

echo
echo "=== Test 7: CLI wrapper writes to the logger location ==="
(
    setup_test_env
    export LOG_TAG="test7"
    "$CLI" INFO  "from cli 1"
    "$CLI" ERROR "from cli 2"
    sleep 0.5
    today=$(date +%Y%m%d)
    # Two separate CLI invocations = two separate runs = two files (1 undecorated + 1 timestamped).
    file_count=$(ls "$TMPDIR/logs/testhost/" 2>/dev/null | grep -c "^test7\.")
    check "two files written by two CLI invocations" "2" "$file_count"
    undecorated="$TMPDIR/logs/testhost/test7.$today.log"
    check "undecorated file exists for first CLI call" "yes" "$([ -f "$undecorated" ] && echo yes || echo no)"
    # Each file has one line
    total_lines=$(wc -l "$TMPDIR"/logs/testhost/test7.*.log 2>/dev/null | tail -1 | awk '{print $1}')
    check "total two log lines across files" "2" "$total_lines"
    # CLI's ERROR call fires a notification
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "one notification from CLI ERROR" "1" "$mock_lines"
)

echo
echo "=== Test 8: backend=none produces no notifications ==="
(
    setup_test_env
    export NOTIFY_BACKEND="none"
    export LOG_TAG="test8"
    source "$LIB"
    log ERROR "would normally notify"
    sleep 0.3
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "no mock notifications when backend=none" "0" "$mock_lines"
)

echo
echo "=== Test 9: unknown backend is silent no-op ==="
(
    setup_test_env
    export NOTIFY_BACKEND="does-not-exist"
    export LOG_TAG="test9"
    source "$LIB"
    # Should not fail or hang.
    log ERROR "test unknown backend"
    sleep 0.3
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "no mock notifications when backend unknown" "0" "$mock_lines"
    log_file_path=$(ls "$TMPDIR/logs/testhost/" 2>/dev/null | head -1)
    check_nonempty "log file still created despite bad backend" "$log_file_path"
)

echo
echo "=== Test 10: LOG_NOTIFY_THRESHOLD override ==="
(
    setup_test_env
    export LOG_TAG="test10"
    export LOG_NOTIFY_THRESHOLD="WARN"
    source "$LIB"
    log INFO  "below"
    log WARN  "at threshold"
    log ERROR "above"
    sleep 1
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "notified for WARN and ERROR" "2" "$mock_lines"
)

echo
echo "=== Test 11: log_file() reports the file being used ==="
(
    setup_test_env
    export LOG_TAG="test11"
    source "$LIB"
    log INFO "hello"
    p=$(log_file)
    check "log_file returns absolute path" "yes" "$([ -f "$p" ] && echo yes || echo no)"
)

echo
echo "=== Test 12: LOG_NOTIFY_MODE=auto suppresses notify when stderr is TTY ==="
# We simulate TTY via script(1) (wraps child in a pseudoterminal). If script
# isn't available, skip.
if command -v script >/dev/null 2>&1; then
    (
        setup_test_env
        export LOG_TAG="test12"
        # Use a subshell inside script(1). Need to pass all env explicitly.
        cmd="LOG_ROOT='$LOG_ROOT' LOG_REL_BASE='$LOG_REL_BASE' LOG_MACHINE_NAME='$LOG_MACHINE_NAME' NOTIFY_BACKEND='$NOTIFY_BACKEND' NOTIFY_MOCK_FILE='$NOTIFY_MOCK_FILE' LOG_TAG='$LOG_TAG' DOTFILES_ROOT='$DOTFILES_ROOT' bash -c 'source \"$LIB\"; log ERROR \"would notify in non-TTY\"; sleep 0.5'"
        script -qfc "$cmd" /dev/null >/dev/null 2>&1
        sleep 0.3
        mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
        check "no notification under TTY in auto mode" "0" "$mock_lines"
    )
else
    echo "SKIP: script(1) not installed; cannot simulate TTY"
fi

echo
echo "=== Test 13: LOG_NOTIFY_MODE=always fires even under TTY ==="
if command -v script >/dev/null 2>&1; then
    (
        setup_test_env
        export LOG_TAG="test13"
        cmd="LOG_ROOT='$LOG_ROOT' LOG_REL_BASE='$LOG_REL_BASE' LOG_MACHINE_NAME='$LOG_MACHINE_NAME' NOTIFY_BACKEND='$NOTIFY_BACKEND' NOTIFY_MOCK_FILE='$NOTIFY_MOCK_FILE' LOG_NOTIFY_MODE=always LOG_TAG='$LOG_TAG' DOTFILES_ROOT='$DOTFILES_ROOT' bash -c 'source \"$LIB\"; log ERROR \"must notify despite TTY\"; sleep 0.5'"
        script -qfc "$cmd" /dev/null >/dev/null 2>&1
        sleep 0.3
        mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
        check "notification under TTY when mode=always" "1" "$mock_lines"
    )
else
    echo "SKIP: script(1) not installed; cannot simulate TTY"
fi

echo
echo "=== Test 14: LOG_NOTIFY_MODE=never suppresses even without TTY ==="
(
    setup_test_env
    export LOG_TAG="test14"
    export LOG_NOTIFY_MODE=never
    source "$LIB"
    log ERROR "should not fire"
    sleep 0.3
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "no notification when mode=never" "0" "$mock_lines"
)

echo
echo "=== Test 15: under non-TTY stderr + auto, notification still fires ==="
# This is the default in this test harness (non-interactive), already covered
# by Test 5, but we reassert explicitly for symmetry.
(
    setup_test_env
    export LOG_TAG="test15"
    source "$LIB"
    log ERROR "non-tty auto"
    sleep 0.6
    mock_lines=$(wc -l < "$NOTIFY_MOCK_FILE")
    check "auto+non-TTY fires notification" "1" "$mock_lines"
)

pass=$(cat "$PASS_FILE")
fail=$(cat "$FAIL_FILE")
echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
