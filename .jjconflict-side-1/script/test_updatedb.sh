#!/usr/bin/env bash
# test_updatedb.sh — harness for script/updatedb.
#
# Exercises the happy path + every error branch using a fake `updatedb`
# binary injected via PATH. Logs are isolated to $TMPDIR.

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
UNDER_TEST="$DOTFILES_ROOT/script/updatedb"

TMPDIR=$(mktemp -d /tmp/test_updatedb.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_MACHINE_NAME="testhost"
export LOG_NOTIFY_MODE=never
export DOTFILES_ROOT
export HOME_OVERRIDE="$TMPDIR/home"   # used via HOME redirection below
export PATH="$TMPDIR/bin:$PATH"
mkdir -p "$TMPDIR/bin" "$HOME_OVERRIDE/.cache"

# Pass counters via file (subshells can't share variables).
PASS_FILE="$TMPDIR/pass"; FAIL_FILE="$TMPDIR/fail"
printf '0' > "$PASS_FILE"
printf '0' > "$FAIL_FILE"
_bump() {
    local f=$1 n
    n=$(cat "$f")
    printf '%d' $((n+1)) > "$f"
}
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$label" "$expected" "$actual"; _bump "$FAIL_FILE"
    fi
}
check_grep() {
    local label=$1 pattern=$2 file=$3
    if [ -f "$file" ] && grep -q "$pattern" "$file" 2>/dev/null; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s\n  missing /%s/ in %s\n  contents: %s\n' "$label" "$pattern" "$file" "$(cat "$file" 2>/dev/null | head -5)"; _bump "$FAIL_FILE"
    fi
}
check_nogrep() {
    local label=$1 pattern=$2 file=$3
    if [ ! -f "$file" ] || ! grep -q "$pattern" "$file" 2>/dev/null; then
        printf 'PASS: %s\n' "$label"; _bump "$PASS_FILE"
    else
        printf 'FAIL: %s (unexpected match of /%s/)\n' "$label" "$pattern"; _bump "$FAIL_FILE"
    fi
}

# Helpers: build a fake `updatedb` whose behaviour is dictated by the content
# of $TMPDIR/fake-behavior at call time. Letting the behavior vary per test
# without rewriting the binary.
cat > "$TMPDIR/bin/updatedb" <<'EOF'
#!/usr/bin/env bash
behavior=$(cat "$TEST_FAKE_BEHAVIOR" 2>/dev/null || echo ok)
case "$behavior" in
    ok)            exit 0 ;;
    slow)          sleep 3; exit 0 ;;
    disk-full)     echo "updatedb: No space left on device" >&2; exit 1 ;;
    permission)    echo "updatedb: Permission denied" >&2; exit 1 ;;
    readonly)      echo "updatedb: Read-only file system" >&2; exit 1 ;;
    other)         echo "updatedb: some unexpected failure" >&2; exit 5 ;;
    *)             exit 0 ;;
esac
EOF
chmod +x "$TMPDIR/bin/updatedb"
export TEST_FAKE_BEHAVIOR="$TMPDIR/fake-behavior"
set_fake_behavior() { echo "$1" > "$TEST_FAKE_BEHAVIOR"; }

# Run the script under test with HOME pointing at our temp home so the DB
# path and logs don't touch the real user. PATH is locked to our fake bin
# (+ minimal system paths) so the real `updatedb` on the system can't leak
# in when the test wants to simulate a missing binary.
# Extra env passed through via $@ before the `bash` command.
run_under_test() {
    env -i \
        HOME="$HOME_OVERRIDE" \
        PATH="$TMPDIR/bin:/usr/bin:/bin" \
        LOG_ROOT="$LOG_ROOT" LOG_REL_BASE="$LOG_REL_BASE" \
        LOG_MACHINE_NAME="$LOG_MACHINE_NAME" \
        LOG_NOTIFY_MODE="$LOG_NOTIFY_MODE" \
        DOTFILES_ROOT="$DOTFILES_ROOT" \
        TEST_FAKE_BEHAVIOR="$TEST_FAKE_BEHAVIOR" \
        "$@" \
        bash "$UNDER_TEST" >/dev/null 2>&1
    echo $?
}
# The log file for this tag today
log_file_for() {
    find "$LOG_ROOT" -type f -name "updatedb.*.log" 2>/dev/null | head -1
}
clear_logs() {
    rm -rf "$LOG_ROOT"
}

echo
echo "=== Test 1: happy path ==="
clear_logs
set_fake_behavior ok
rc=$(run_under_test)
check "exit 0 on success" "0" "$rc"
lf=$(log_file_for)
check "log file created" "yes" "$([ -f "$lf" ] && echo yes || echo no)"
check_grep "INFO line for success" '\[INFO\] updatedb ok' "$lf"

echo
echo "=== Test 2: slow updatedb -> WARN ==="
clear_logs
set_fake_behavior slow
# Override THRESHOLD to 1s so our 3s fake "slow" run trips the WARN path
# without making the test suite wait.
rc=$(run_under_test UPDATEDB_THRESHOLD=1)
check "exit 0 on slow success" "0" "$rc"
lf=$(log_file_for)
check_grep "WARN on slow run" '\[WARN\] slow updatedb' "$lf"
check_grep "mentions prunepaths in hint" 'prunepaths' "$lf"

echo
echo "=== Test 3: disk full -> ERROR ==="
clear_logs
set_fake_behavior disk-full
rc=$(run_under_test)
check "non-zero exit" "1" "$rc"
lf=$(log_file_for)
check_grep "ERROR identifies disk full" 'disk full' "$lf"
check_grep "names the target DB path" 'plocate.db' "$lf"

echo
echo "=== Test 4: permission denied -> ERROR ==="
clear_logs
set_fake_behavior permission
rc=$(run_under_test)
check "non-zero exit" "1" "$rc"
lf=$(log_file_for)
check_grep "ERROR identifies permission" 'permission denied' "$lf"

echo
echo "=== Test 5: read-only FS -> ERROR ==="
clear_logs
set_fake_behavior readonly
rc=$(run_under_test)
check "non-zero exit" "1" "$rc"
lf=$(log_file_for)
check_grep "ERROR identifies read-only" 'read-only' "$lf"

echo
echo "=== Test 6: other failure -> generic ERROR with exit code ==="
clear_logs
set_fake_behavior other
rc=$(run_under_test)
check "exit propagated" "5" "$rc"
lf=$(log_file_for)
check_grep "ERROR includes exit code" 'exit=5' "$lf"

echo
echo "=== Test 7: updatedb binary missing -> ERROR with install hint ==="
clear_logs
rm -f "$TMPDIR/bin/updatedb"
rc=$(run_under_test)
check "exit 1" "1" "$rc"
lf=$(log_file_for)
check_grep "tells the user how to install" 'apt install plocate\|nix-env' "$lf"
check_nogrep "does not say 'Success' or similar" 'ok: ' "$lf"

echo
echo "=== Test 8: cache dir unwritable -> ERROR ==="
clear_logs
# Recreate the fake updatedb that Test 7 deleted
cat > "$TMPDIR/bin/updatedb" <<'EOF'
#!/usr/bin/env bash
behavior=$(cat "$TEST_FAKE_BEHAVIOR" 2>/dev/null || echo ok)
case "$behavior" in
    ok) exit 0 ;;
    *)  exit 1 ;;
esac
EOF
chmod +x "$TMPDIR/bin/updatedb"
set_fake_behavior ok
# Remove the cache dir; make the parent unwritable so mkdir fails.
rm -rf "$HOME_OVERRIDE/.cache"
chmod 555 "$HOME_OVERRIDE"
rc=$(run_under_test)
chmod 755 "$HOME_OVERRIDE"   # restore so cleanup works
check "exit 1 when cache dir cannot be created" "1" "$rc"
lf=$(log_file_for)
check_grep "ERROR mentions cache dir path" "$HOME_OVERRIDE/.cache" "$lf"

pass=$(cat "$PASS_FILE")
fail=$(cat "$FAIL_FILE")
echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
