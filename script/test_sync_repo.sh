#!/usr/bin/env bash
# Smoke test for script/sync_repo. Creates throwaway jj/git repos sharing a
# bare "backup" remote, drives sync_repo through:
#   - local-ahead: push path
#   - divergence (non-conflicting edits): merge+push path
#   - dead remote (127.0.0.1:1): timeout-guard exits in bounded time
# And asserts that the structured log contains the expected tags.
#
# Usage: bash script/test_sync_repo.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SYNC_REPO="$DOTFILES_ROOT/script/sync_repo"

TMPDIR=$(mktemp -d /tmp/sync_repo_test.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== test dir: $TMPDIR ==="

# Point the leveled logger at an isolated dir; avoid touching real ~/hjdocs/logs.
# LOG_NOTIFY_MODE=never so the test never fires real Telegram webhooks even if
# the bot is configured on this machine.
# LOG_KEEP_THRESHOLD=DEBUG so INFO-only runs (PUSH-OK, FAST-FORWARD, SKIP) and
# WARN-only runs (TIMEOUT, NETWORK-ERR) leave log files for grep_has assertions.
export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG

# Aggregate log file for assertions: find all per-machine logs.
find_log() {
    find "$LOG_ROOT" -name 'sync_repo.*.log' -print -quit 2>/dev/null
}

# Shared bare remote.
git -C "$TMPDIR" init --bare -q -b master remote.git

# setup_repo <dirname> <extra-content>
# Seeds a colocated jj/git repo with an initial commit on master that is pushed to
# the shared bare remote, then appends <extra-content> as an in-progress working change.
setup_repo() {
    local name=$1 extra_file=$2 extra_content=$3
    mkdir -p "$TMPDIR/$name"
    (
        cd "$TMPDIR/$name"
        jj git init --colocate
        jj git remote add backup "$TMPDIR/remote.git"
        jj config set --repo sync.bookmark master
        jj config set --repo user.email 'test@example.com'
        jj config set --repo user.name  'Test User'
        echo "initial" > README.md
        jj commit -m "initial"
        # After commit, @- is the initial commit. Create master there.
        jj bookmark create master -r @-
        jj git push --remote backup --bookmark master --allow-new
        # Add content to a distinct file so different repos can push without conflict.
        if [ -n "$extra_file" ]; then
            echo "$extra_content" > "$extra_file"
        fi
    ) >/dev/null 2>&1
}

pass=0
fail=0
check() {
    local label=$1 expected=$2 actual=$3
    if [ "$expected" = "$actual" ]; then
        echo "PASS: $label"
        pass=$((pass+1))
    else
        echo "FAIL: $label"
        echo "  expected: [$expected]"
        echo "  actual:   [$actual]"
        fail=$((fail+1))
    fi
}

run_sync() {
    bash "$SYNC_REPO" "$1" >/dev/null 2>&1
}

echo
echo "=== Scenario 1: local ahead of remote -> push ==="
setup_repo repoA "a.txt" "from A"
run_sync "$TMPDIR/repoA"
remote_head=$(git -C "$TMPDIR/remote.git" rev-parse master)
# Fetch into jj so our local view matches the remote
local_head=$(cd "$TMPDIR/repoA" && jj log -r master --no-graph -T 'commit_id')
check "remote advanced to local after push" "$local_head" "$remote_head"

echo
echo "=== Scenario 2: divergence -> rebase + push (different files -> no conflict) ==="
setup_repo repoB "b.txt" "from B"
setup_repo repoC "c.txt" "from C"
# repoB pushes first -> becomes remote tip
run_sync "$TMPDIR/repoB"
# repoC now has local divergence relative to remote (edits a different file)
run_sync "$TMPDIR/repoC"

remote_after=$(git -C "$TMPDIR/remote.git" rev-parse master)
local_after=$(cd "$TMPDIR/repoC" && jj log -r master --no-graph -T 'commit_id')
check "local and remote master match after rebase" "$local_after" "$remote_after"

# Verify the rebased commit has 1 parent (linear history, no merge commit)
parent_count=$(cd "$TMPDIR/repoC" && jj log -r master --no-graph -T 'parents.len()')
check "rebased commit has 1 parent (linear history)" "1" "$parent_count"

# Verify the description is the original c.txt change description (not "Merge ...")
rebased_desc=$(cd "$TMPDIR/repoC" && jj log -r master --no-graph -T 'description.first_line()')
case "$rebased_desc" in
    Merge*) echo "FAIL: rebased description starts with 'Merge' (got: '$rebased_desc')"; fail=$((fail+1)) ;;
    "")     echo "FAIL: rebased description is empty"; fail=$((fail+1)) ;;
    *)      echo "PASS: rebased description preserved (got: '$rebased_desc')"; pass=$((pass+1)) ;;
esac

echo
echo "=== Scenario 3: sync log contains expected tags ==="
grep_has() {
    local pattern=$1
    # Search across ALL log files under $LOG_ROOT
    if grep -rq "$pattern" "$LOG_ROOT" 2>/dev/null; then
        echo "PASS: log contains '$pattern'"
        pass=$((pass+1))
    else
        echo "FAIL: log missing '$pattern'"
        fail=$((fail+1))
    fi
}
grep_has "PUSH-OK"
grep_has "repoC.*rebased"

echo
echo "=== Scenario 4: command timeout guard ==="
# Simulate a hung remote by pointing a repo at a non-responding IP:port.
# Real networks might treat 127.0.0.1:1 differently across kernels, so we use
# a blackhole host-port with a short timeout.
setup_repo repoH "h.txt" "from H"
# Override the backup remote to a blackhole to force a hang.
# SYNC_REPO_CMD_TIMEOUT=3 so the test completes within a few seconds.
(
    cd "$TMPDIR/repoH"
    jj git remote set-url backup "ssh://git@127.0.0.1:1/repo.git"
)
start=$(date +%s)
SYNC_REPO_CMD_TIMEOUT=3 bash "$SYNC_REPO" "$TMPDIR/repoH" >/dev/null 2>&1
elapsed=$(( $(date +%s) - start ))
# The run MAY actually be fast if ssh fails connection-refused immediately;
# that's fine — the important property is "it didn't hang forever". So we
# bound by 30s rather than insisting on > 3s.
if [ "$elapsed" -lt 30 ]; then
    echo "PASS: repoH completed in ${elapsed}s (< 30s)"
    pass=$((pass+1))
else
    echo "FAIL: repoH ran for ${elapsed}s (hang not prevented)"
    fail=$((fail+1))
fi
# The log should mention either TIMEOUT or NETWORK-ERR for the failed ops.
if grep -rqE 'TIMEOUT|NETWORK-ERR' "$LOG_ROOT" 2>/dev/null; then
    echo "PASS: log recorded TIMEOUT or NETWORK-ERR"
    pass=$((pass+1))
else
    echo "FAIL: log has no TIMEOUT/NETWORK-ERR entry"
    fail=$((fail+1))
fi
# Regression: when push-del fails (network, concurrent push, etc.) the follow-up
# push MUST be skipped — proceeding would non-fast-forward and emit a bogus
# OTHER-ERR that masks the real delete failure. Assert both sides.
if grep -rq 'SKIP-PUSH' "$LOG_ROOT"/*/sync_repo.*repoH* 2>/dev/null; then
    echo "PASS: log recorded SKIP-PUSH after failed delete"
    pass=$((pass+1))
else
    echo "FAIL: log missing SKIP-PUSH (push should skip when delete fails)"
    fail=$((fail+1))
fi
# Regression: when Step 2's fetch fails (timeout / network), Step 2 push MUST
# be skipped. Otherwise stale ${CURRENT_BM}@backup leads to wrong-path pushes
# (e.g. mistaking an existing remote bookmark for new and trying full-history
# push, which fails on any no-description ancestor).
if grep -rqE 'SKIP-PUSH master: fetch failed' "$LOG_ROOT"/*/sync_repo.*repoH* 2>/dev/null; then
    echo "PASS: log recorded SKIP-PUSH master: fetch failed"
    pass=$((pass+1))
else
    echo "FAIL: log missing 'SKIP-PUSH master: fetch failed' (Step 2 should skip when fetch fails)"
    fail=$((fail+1))
fi
if grep -rqE 'OTHER-ERR.*non-fast-forward' "$LOG_ROOT"/*/sync_repo.*repoH* 2>/dev/null; then
    echo "FAIL: log has cascade non-fast-forward OTHER-ERR (delete failure should skip push)"
    fail=$((fail+1))
else
    echo "PASS: no cascade non-fast-forward OTHER-ERR after failed delete"
    pass=$((pass+1))
fi

echo
echo "=== Scenario 5: empty BACKUP_URL (git/jj remote drift) exits cleanly ==="
# Reproduce the drift: jj knows about 'backup' but git's remote get-url
# returns empty. This is unusual but has been observed in the wild for
# colocated repos where someone edited git config without jj noticing.
# Note: current jj validates remote URLs aggressively, making this drift
# hard to reproduce synthetically. The test asserts the defensive behavior
# (no ERROR logs, clean exit) rather than the specific log tag.
mkdir -p "$TMPDIR/repoNoBackup"
(
    cd "$TMPDIR/repoNoBackup"
    jj git init --colocate
    jj git remote add backup "$TMPDIR/remote.git"
    git config --unset-all remote.backup.url
    git config remote.backup.url ''
    echo x > f; jj commit -m "init"
) >/dev/null 2>&1
bash "$SYNC_REPO" "$TMPDIR/repoNoBackup" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: sync_repo returned 0 for empty BACKUP_URL"
    pass=$((pass+1))
else
    echo "FAIL: sync_repo returned $rc for empty BACKUP_URL"
    fail=$((fail+1))
fi
# Crucial: no ERROR from bogus push attempts in this scenario.
if grep -l '\[ERROR\]' "$LOG_ROOT"/*/sync_repo.repoNoBackup* 2>/dev/null | grep -q .; then
    echo "FAIL: log has ERROR entries for empty BACKUP_URL path (should not)"
    fail=$((fail+1))
else
    echo "PASS: no ERROR entries for empty BACKUP_URL path"
    pass=$((pass+1))
fi

echo
echo "=== Scenario 6: divergence with conflict -> REBASE-CONFLICT, no push ==="
# Fresh bare remote so prior scenarios' state doesn't interfere.
git -C "$TMPDIR" init --bare -q -b master conflict.git
# Build a base repo that has one shared commit and pushes it as master.
mkdir -p "$TMPDIR/conflict-base"
(
    cd "$TMPDIR/conflict-base"
    jj git init --colocate
    jj git remote add backup "$TMPDIR/conflict.git"
    jj config set --repo sync.bookmark master
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo "base content" > shared.txt
    jj commit -m "base"
    jj bookmark create master -r @-
    jj git push --remote backup --bookmark master --allow-new
) >/dev/null 2>&1
# Two repos sharing the same base commit_id, with conflicting working-copy edits.
cp -r "$TMPDIR/conflict-base" "$TMPDIR/repoX"
cp -r "$TMPDIR/conflict-base" "$TMPDIR/repoY"
echo "X content"           > "$TMPDIR/repoX/shared.txt"
echo "DIFFERENT Y content" > "$TMPDIR/repoY/shared.txt"

# repoX syncs first -> remote advances to repoX's commit
run_sync "$TMPDIR/repoX"
remote_after_x=$(git -C "$TMPDIR/conflict.git" rev-parse master)
local_x=$(cd "$TMPDIR/repoX" && jj log -r master --no-graph -T 'commit_id')
check "remote advanced to repoX's commit" "$local_x" "$remote_after_x"

# repoY syncs and detects rebase conflict -> remote MUST be unchanged
run_sync "$TMPDIR/repoY"
remote_after_y=$(git -C "$TMPDIR/conflict.git" rev-parse master)
check "remote unchanged after repoY conflict" "$remote_after_x" "$remote_after_y"

# repoY's master must NOT be a descendant of remote (rebase was blocked).
remote_in_local_y=$(cd "$TMPDIR/repoY" && jj log -r "$remote_after_x & ::master" --no-graph -T '"y"' 2>/dev/null)
check "remote NOT ancestor of repoY master (rebase blocked)" "" "$remote_in_local_y"

if grep -rqE 'REBASE-CONFLICT.*master' "$LOG_ROOT"/*/sync_repo.*repoY* 2>/dev/null; then
    echo "PASS: log recorded REBASE-CONFLICT for repoY"
    pass=$((pass+1))
else
    echo "FAIL: log missing REBASE-CONFLICT for repoY"
    fail=$((fail+1))
fi
if grep -rqE 'PUSH-OK master' "$LOG_ROOT"/*/sync_repo.*repoY* 2>/dev/null; then
    echo "FAIL: repoY logged PUSH-OK master despite conflict"
    fail=$((fail+1))
else
    echo "PASS: repoY did not log PUSH-OK master"
    pass=$((pass+1))
fi

echo
echo "=== Sample log file ==="
sample=$(find "$LOG_ROOT" -name '*.log' | head -1)
if [ -n "$sample" ]; then
    echo "--- $sample ---"
    cat "$sample"
else
    echo "(no log files produced)"
fi

echo
echo "=== Results: $pass passed, $fail failed ==="
[ $fail -eq 0 ]
