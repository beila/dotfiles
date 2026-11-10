#!/usr/bin/env bash
set -euo pipefail

dotfiles_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/sync_repo_interruptions.XXXXXX)
sync_pid=
hook_pid=
cleanup() {
    if [ -n "$hook_pid" ]; then
        kill -TERM "$hook_pid" 2>/dev/null || true
    fi
    if [ -n "$sync_pid" ]; then
        kill -TERM "$sync_pid" 2>/dev/null || true
        wait "$sync_pid" 2>/dev/null || true
    fi
    rm -rf "$test_root"
}
trap cleanup EXIT

export LOG_ROOT="$test_root/logs"
export LOG_REL_BASE="$test_root"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=ERROR
export SYNC_LOG_ROOT_KEEP=1
export XDG_STATE_HOME="$test_root/state"

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf 'PASS: %s\n' "$1"
    else
        printf 'FAIL: %s\n  expected: %s\n  actual: %s\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}

for signal in TERM HUP; do
    repo="$test_root/$signal"
    jj git init --colocate "$repo" >/dev/null 2>&1
    # Expand the hook variables in the child shell.
    # shellcheck disable=SC2016
    jj -R "$repo" config set --repo sync.pre-snapshot \
        'printf "%s\n" "$$" > "$TEST_SYNC_HOOK_MARKER"; exec sleep 30'
    export TEST_SYNC_HOOK_MARKER="$test_root/$signal.ready"
    bash "$dotfiles_root/script/sync_repo" "$repo" >"$test_root/$signal.out" 2>&1 &
    sync_pid=$!

    for _ in {1..100}; do
        [ -s "$TEST_SYNC_HOOK_MARKER" ] && break
        sleep 0.05
    done
    if [ ! -s "$TEST_SYNC_HOOK_MARKER" ]; then
        cat "$test_root/$signal.out"
        printf 'FAIL: %s hook did not start\n' "$signal"
        exit 1
    fi
    hook_pid=$(cat "$TEST_SYNC_HOOK_MARKER")
    kill -s "$signal" "$sync_pid"
    # End the foreground command so Bash can handle its pending signal.
    kill -TERM "$hook_pid" 2>/dev/null || true
    hook_pid=
    rc=0
    wait "$sync_pid" || rc=$?
    sync_pid=

    expected_rc=143
    [ "$signal" = HUP ] && expected_rc=129
    check "$signal preserves the signal exit status" "$expected_rc" "$rc"
    check "$signal retains the interruption and phase" true \
        "$(rg -q "\\[ERROR\\].* INTERRUPTED signal=$signal phase=pre-snapshot rc=$expected_rc" "$LOG_ROOT" && printf true)"
    check "$signal retains earlier diagnostic messages" true \
        "$(rg -q -g "*${signal}*.log" '\[INFO\].* START' "$LOG_ROOT" && printf true)"

    git_root=$(jj --ignore-working-copy -R "$repo" git root)
    lock_key=$(printf '%s' "$git_root" | tr / _)
    check "$signal releases the job lock" true \
        "$(flock -n "/tmp/sync_repo_job_${lock_key}.lock" true && printf true)"
    check "$signal releases the local lock" true \
        "$(flock -n "/tmp/sync_repo_${lock_key}.lock" true && printf true)"
done

repo="$test_root/normal"
jj git init --colocate "$repo" >/dev/null 2>&1
rc=0
bash "$dotfiles_root/script/sync_repo" "$repo" >"$test_root/normal.out" 2>&1 || rc=$?
check "normal run succeeds" 0 "$rc"
check "normal run does not retain an ERROR log" "" \
    "$(rg --files "$LOG_ROOT" -g '*normal*.log')"

if [ "$fail" -gt 0 ]; then
    cat "$test_root"/*.out
    rg -n . "$LOG_ROOT" || true
fi
printf 'Results: %s failed\n' "$fail"
[ "$fail" -eq 0 ]
