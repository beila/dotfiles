#!/usr/bin/env bash
# Smoke test for script/sync_repo's diverged-bookmark handling.
# Creates throwaway repos pointing at a shared bare "remote", simulates
# divergence, runs sync_repo, and verifies expected outcomes.
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
export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_NOTIFY_MODE=never

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
echo "=== Scenario 2: divergence -> merge + push (different files -> no conflict) ==="
setup_repo repoB "b.txt" "from B"
setup_repo repoC "c.txt" "from C"
# repoB pushes first -> becomes remote tip
run_sync "$TMPDIR/repoB"
# repoC now has local divergence relative to remote (edits a different file)
run_sync "$TMPDIR/repoC"

remote_after=$(git -C "$TMPDIR/remote.git" rev-parse master)
local_after=$(cd "$TMPDIR/repoC" && jj log -r master --no-graph -T 'commit_id')
check "local and remote master match after merge" "$local_after" "$remote_after"

# Verify the merge has two parents and a description
parent_count=$(cd "$TMPDIR/repoC" && jj log -r master --no-graph -T 'parents.len()')
check "merge has 2 parents" "2" "$parent_count"

merge_desc=$(cd "$TMPDIR/repoC" && jj log -r master --no-graph -T 'description.first_line()')
case "$merge_desc" in
    Merge*into*master) echo "PASS: merge description starts with 'Merge ... into master'"; pass=$((pass+1)) ;;
    *) echo "FAIL: merge description was: '$merge_desc'"; fail=$((fail+1)) ;;
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
grep_has "repoC.*merged"

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
