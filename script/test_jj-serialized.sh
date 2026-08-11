#!/usr/bin/env bash

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
WRAPPER="$ROOT/script/bin/jj-serialized"
TMPDIR=$(mktemp -d /tmp/jj_serialized_test.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/repo-a/.git" "$TMPDIR/repo-b/.git"
EVENTS="$TMPDIR/events"
: > "$EVENTS"

cat > "$TMPDIR/jj-real" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "--ignore-working-copy" ] &&
   [ "${2:-}" = "git" ] &&
   [ "${3:-}" = "root" ]; then
    printf '%s\n' "${TEST_GIT_ROOT:-$PWD/.git}"
    exit 0
fi
printf 'start:%s\n' "$TEST_ID" >> "$TEST_EVENTS"
sleep "${TEST_SLEEP:-0}"
printf 'end:%s\n' "$TEST_ID" >> "$TEST_EVENTS"
STUB
chmod +x "$TMPDIR/jj-real"

export JJ_REAL_EXECUTABLE="$TMPDIR/jj-real"
export JJ_FLOCK_EXECUTABLE
JJ_FLOCK_EXECUTABLE=$(command -v flock)
export JJ_TR_EXECUTABLE
JJ_TR_EXECUTABLE=$(command -v tr)
export TEST_EVENTS="$EVENTS"

pass=0
fail=0
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        printf 'PASS: %s\n' "$label"
        pass=$((pass+1))
    else
        printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' "$label" "$expected" "$actual"
        fail=$((fail+1))
    fi
}

wait_for_event() {
    local event=$1
    while ! grep -qx "$event" "$EVENTS"; do
        sleep 0.01
    done
}

TEST_GIT_ROOT="$TMPDIR/repo-a/.git" TEST_ID=one TEST_SLEEP=0.4 "$WRAPPER" hold &
first=$!
wait_for_event start:one
TEST_GIT_ROOT="$TMPDIR/repo-a/.git" TEST_ID=two TEST_SLEEP=0 "$WRAPPER" hold &
second=$!
wait "$first" "$second"
check "same repository is serialized" \
    "start:one end:one start:two end:two" \
    "$(tr '\n' ' ' < "$EVENTS" | sed 's/ $//')"

: > "$EVENTS"
TEST_GIT_ROOT="$TMPDIR/repo-a/.git" TEST_ID=one TEST_SLEEP=0.4 "$WRAPPER" hold &
first=$!
wait_for_event start:one
TEST_GIT_ROOT="$TMPDIR/repo-b/.git" TEST_ID=two TEST_SLEEP=0 "$WRAPPER" hold &
second=$!
wait "$first" "$second"
check "different repositories run concurrently" \
    "start:one start:two end:two end:one" \
    "$(tr '\n' ' ' < "$EVENTS" | sed 's/ $//')"

: > "$EVENTS"
TEST_GIT_ROOT="$TMPDIR/repo-a/.git" TEST_ID=one TEST_SLEEP=0.4 "$WRAPPER" hold &
first=$!
wait_for_event start:one
JJ_SERIALIZED_LOCK_HELD=1 TEST_GIT_ROOT="$TMPDIR/repo-a/.git" TEST_ID=two TEST_SLEEP=0 "$WRAPPER" hold
wait "$first"
check "sync_repo local-lock owner bypasses nested locking" \
    "start:one start:two end:two end:one" \
    "$(tr '\n' ' ' < "$EVENTS" | sed 's/ $//')"

: > "$EVENTS"
(
    cd "$TMPDIR" || exit
    TEST_ID=one TEST_SLEEP=0.4 "$WRAPPER" -R repo-a hold
) &
first=$!
wait_for_event start:one
TEST_GIT_ROOT="$TMPDIR/repo-a/.git" TEST_ID=two TEST_SLEEP=0 "$WRAPPER" hold &
second=$!
wait "$first" "$second"
check "-R target shares the repository lock" \
    "start:one end:one start:two end:two" \
    "$(tr '\n' ' ' < "$EVENTS" | sed 's/ $//')"

printf 'Results: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
