#!/usr/bin/env bash
set -euo pipefail

dotfiles_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/sync_repo_push_verification.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Test User"
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export LOG_REL_BASE="$test_root"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG
export SYNC_LOG_ROOT_KEEP=1
export XDG_STATE_HOME="$test_root/state"
export PUSH_TEST_REAL_GIT
PUSH_TEST_REAL_GIT=$(command -v git)

mkdir "$test_root/stubs"
printf '#!/bin/sh\nprintf "testhost\\n"\n' >"$test_root/stubs/hostnamectl"
cp "$test_root/stubs/hostnamectl" "$test_root/stubs/hostname"
cat >"$test_root/stubs/git" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$PUSH_TEST_TRACE"
forced=0
listing=0
for argument in "$@"; do
    case "$argument" in
        --force-with-lease=refs/heads/testhost/build:*) forced=1 ;;
        ls-remote) listing=1 ;;
    esac
done
if [ "$listing" -eq 1 ] && [ "${!#}" = refs/heads/testhost/build ]; then
    case "$PUSH_TEST_MODE" in
        verify-failed) exit 1 ;;
        verify-timeout) exec sleep 30 ;;
        wrong-ref)
            printf '%s\trefs/heads/other/build\n' "$PUSH_TEST_EXPECTED"
            exit 0
            ;;
    esac
fi
if [ "$forced" -eq 1 ]; then
    case "$PUSH_TEST_MODE" in
        rejected|wrong-ref)
            printf 'error: failed to push some refs\n' >&2
            exit 1
            ;;
        policy)
            printf 'remote: force updates are not allowed\n' >&2
            exit 1
            ;;
        normal) exec "$PUSH_TEST_REAL_GIT" "$@" ;;
    esac
    "$PUSH_TEST_REAL_GIT" "$@"
    if [ "$PUSH_TEST_MODE" = raced ]; then
        "$PUSH_TEST_REAL_GIT" --git-dir="$PUSH_TEST_REMOTE" \
            update-ref refs/heads/testhost/build "$PUSH_TEST_BEFORE"
    fi
    printf 'error: failed to push some refs\n' >&2
    exit 1
fi
exec "$PUSH_TEST_REAL_GIT" "$@"
STUB
chmod +x "$test_root/stubs/"*
export PATH="$test_root/stubs:$PATH"
export GIT_EXECUTABLE="$test_root/stubs/git"

source_repo="$test_root/source"
"$PUSH_TEST_REAL_GIT" init -q -b main "$source_repo"
printf 'before\n' >"$source_repo/file"
"$PUSH_TEST_REAL_GIT" -C "$source_repo" add file
"$PUSH_TEST_REAL_GIT" -C "$source_repo" commit -q -m before
export PUSH_TEST_BEFORE
PUSH_TEST_BEFORE=$("$PUSH_TEST_REAL_GIT" -C "$source_repo" rev-parse HEAD)
printf 'after\n' >"$source_repo/file"
"$PUSH_TEST_REAL_GIT" -C "$source_repo" commit -qam after
export PUSH_TEST_EXPECTED
PUSH_TEST_EXPECTED=$("$PUSH_TEST_REAL_GIT" -C "$source_repo" rev-parse HEAD)

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf 'PASS: %s\n' "$1"
    else
        printf 'FAIL: %s (expected %s, got %s)\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}

for mode in normal acknowledged-error rejected verify-failed verify-timeout raced wrong-ref policy; do
    checkout="$test_root/$mode"
    export PUSH_TEST_MODE="$mode"
    export PUSH_TEST_REMOTE="$test_root/$mode.git"
    export PUSH_TEST_TRACE="$test_root/$mode.trace"
    export LOG_ROOT="$test_root/logs/$mode"
    "$PUSH_TEST_REAL_GIT" init --bare -q "$PUSH_TEST_REMOTE"
    "$PUSH_TEST_REAL_GIT" -C "$source_repo" push -q "$PUSH_TEST_REMOTE" \
        "$PUSH_TEST_BEFORE:refs/heads/testhost/build"
    "$PUSH_TEST_REAL_GIT" clone -q --no-local "$source_repo" "$checkout"
    jj git init --colocate "$checkout" >/dev/null 2>&1
    jj -R "$checkout" bookmark delete main >/dev/null 2>&1
    jj -R "$checkout" bookmark create build -r @- >/dev/null 2>&1
    jj -R "$checkout" config set --repo sync.snapshot-url "$PUSH_TEST_REMOTE"
    jj -R "$checkout" config set --repo sync.repo-history false
    SYNC_REPO_CMD_TIMEOUT=1 bash "$dotfiles_root/script/sync_repo" "$checkout" \
        >"$test_root/$mode.out" 2>&1
    actual=$("$PUSH_TEST_REAL_GIT" --git-dir="$PUSH_TEST_REMOTE" rev-parse refs/heads/testhost/build)
    errors=$(rg -l 'OTHER-ERR force-push testhost/build' "$LOG_ROOT" | wc -l || true)
    verified=$(rg -l 'PUSH-VERIFIED testhost/build' "$LOG_ROOT" | wc -l || true)
    deletes=$(rg -c -- ' --delete refs/heads/testhost/build$' "$PUSH_TEST_TRACE" || true)
    reads=$(rg -c ' ls-remote --heads .* refs/heads/testhost/build$' "$PUSH_TEST_TRACE" || true)
    case "$mode" in
        normal|policy|acknowledged-error)
            check "$mode: the snapshot is stored" "$PUSH_TEST_EXPECTED" "$actual"
            check "$mode: no false push error" 0 "$errors"
            ;;
        rejected|raced|wrong-ref)
            check "$mode: the other remote value is preserved" "$PUSH_TEST_BEFORE" "$actual"
            check "$mode: the push error remains visible" 1 "$errors"
            ;;
        verify-failed|verify-timeout)
            check "$mode: unconfirmed success remains an error" 1 "$errors"
            ;;
    esac
    expected_reads=1
    [ "$mode" != normal ] || expected_reads=0
    check "$mode: bounded verification query count" "$expected_reads" "${reads:-0}"
    expected_verified=0
    [ "$mode" != acknowledged-error ] || expected_verified=1
    check "$mode: success requires a matching remote ref" "$expected_verified" "$verified"
    expected_deletes=0
    [ "$mode" != policy ] || expected_deletes=1
    check "$mode: only a policy rejection uses the delete fallback" "$expected_deletes" "${deletes:-0}"
done

[ "$fail" -eq 0 ]
