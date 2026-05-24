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

# Stub the AI commit-message providers so sync_repo's snapshot_at_to_push_rev
# doesn't pay claude / kiro-cli / ollama latency in the test loop. Without
# this, every scenario that has dirty working state (which is most of them)
# pays a 30s claude timeout when claude is sluggish, making the timeout-guard
# scenario impossible to bound tightly. commit-msg's chain falls through any
# stub that exits 1 and ends at a deterministic file-list message.
mkdir -p "$TMPDIR/stubs"
for tool in claude kiro-cli ollama; do
    cat >"$TMPDIR/stubs/$tool" <<'STUB'
#!/bin/sh
exit 1
STUB
    chmod +x "$TMPDIR/stubs/$tool"
done
export PATH="$TMPDIR/stubs:$PATH"

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
# Goal: verify sync_repo's timeout_cmd / classify_cmd plumbing fires when a
# network call hangs, AND that downstream behavior (SKIP-PUSH, no cascade
# OTHER-ERR) is correct under that failure mode.
#
# Earlier this was tested via a real SSH blackhole (127.0.0.1:1) plus a 30s
# wall-clock bound — but each timed-out call still costs ~ConnectTimeout(10s)
# + SYNC_REPO_CMD_TIMEOUT + kill-grace, and sync_repo makes ~6 ssh-bearing
# calls per run. Real-world wall time hovered 34-37s, tripping the bound on
# busy hosts. Replaced with a deterministic fake ssh that sleeps long past
# any timeout — every call hits SYNC_REPO_CMD_TIMEOUT exactly. Both `git` and
# `jj git fetch` honor $GIT_SSH_COMMAND in the versions we ship.
cat >"$TMPDIR/fake-ssh.sh" <<'FAKESSH'
#!/bin/bash
# Mock ssh for sync_repo's timeout-guard test.
# - `ssh -G ...` is git/jj's option probe; must return fast or the connection
#   never gets attempted.
# - All other invocations are real connection attempts; we sleep well past any
#   SYNC_REPO_CMD_TIMEOUT so timeout_cmd will reliably kill us.
# - `exec sleep` (not bare `sleep`) so SIGTERM from timeout(1) goes straight
#   to the sleep process. With a wrapping bash, bash holds the foreground job
#   open and timeout(1)'s SIGTERM is swallowed, forcing the kill-after-10
#   grace and inflating per-call wall time from 1s to 11s.
for a in "$@"; do
  case "$a" in
    -G) exit 0 ;;
  esac
done
exec sleep 60
FAKESSH
chmod +x "$TMPDIR/fake-ssh.sh"

setup_repo repoH "h.txt" "from H"
# Override the backup remote to an SSH URL — the fake ssh handles the actual
# connection, regardless of host. Use an .invalid TLD so no real DNS happens.
(
    cd "$TMPDIR/repoH"
    jj git remote set-url backup "ssh://git@blackhole.invalid/repo.git"
)
# Tight bound: with SYNC_REPO_CMD_TIMEOUT=1 and ~6 ssh calls, the run completes
# in ~6s on a typical machine. 15s gives generous headroom while still failing
# loudly if a regression makes the timeout guard ineffective.
start=$(date +%s)
SYNC_REPO_CMD_TIMEOUT=1 \
GIT_SSH_COMMAND="bash $TMPDIR/fake-ssh.sh" \
    bash "$SYNC_REPO" "$TMPDIR/repoH" >/dev/null 2>&1
elapsed=$(( $(date +%s) - start ))
if [ "$elapsed" -lt 15 ]; then
    echo "PASS: repoH completed in ${elapsed}s (< 15s)"
    pass=$((pass+1))
else
    echo "FAIL: repoH ran for ${elapsed}s (timeout guard ineffective)"
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
echo "=== Scenario 7: non-jj repo is silently skipped ==="
# sync_all blindly hands sync_repo every .git/.jj marker under $HOME, including
# Brazil-managed checkouts (~/devc/, ~/.toolbox/) and other plain-git repos.
# Those used to hit a git-only push flow that tried to push to whatever
# upstream the branch tracked — typically origin/mainline (CR-protected) or
# nothing at all — producing 14+ spurious "FAILED rc=N" lines per cycle in
# sync_all's SUMMARY notification, plus an unintended commit-msg LLM call per
# dirty checkout. The git-only path is now removed; sync_repo handles only jj
# repos. Non-jj repos should return 0 with no log file persisted (INFO-only
# runs are dropped by the logger's LOG_KEEP_THRESHOLD).
mkdir -p "$TMPDIR/repoPlainGit"
(
    cd "$TMPDIR/repoPlainGit"
    git init -q -b mainline
    git config user.email 'test@example.com'
    git config user.name  'Test User'
    # Set up the trap that the OLD git-only path would have fallen for: a
    # 'backup' remote with the branch tracking origin/mainline. This is the
    # production failure shape; the new behavior should ignore it entirely.
    git -C "$TMPDIR" init --bare -q -b mainline noop-backup.git 2>/dev/null
    git -C "$TMPDIR" init --bare -q -b mainline noop-origin.git 2>/dev/null
    git remote add origin "$TMPDIR/noop-origin.git"
    git remote add backup "$TMPDIR/noop-backup.git"
    echo "x" > f
    git add f
    git commit -q -m "init"
    git push -q --set-upstream origin mainline
    echo "dirty" > extra.txt
) >/dev/null 2>&1
# Capture log file count BEFORE the run so we can assert no new file was kept.
log_files_before=$(find "$LOG_ROOT" -name 'sync_repo.*repoPlainGit*' 2>/dev/null | wc -l)
bash "$SYNC_REPO" "$TMPDIR/repoPlainGit" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: sync_repo returned 0 for non-jj repo"
    pass=$((pass+1))
else
    echo "FAIL: sync_repo returned $rc for non-jj repo"
    fail=$((fail+1))
fi

# No log file should be persisted — the early-exit happens before log.sh is
# sourced, so no temp file is created and no finalize moves anything to disk.
log_files_after=$(find "$LOG_ROOT" -name 'sync_repo.*repoPlainGit*' 2>/dev/null | wc -l)
if [ "$log_files_after" = "$log_files_before" ]; then
    echo "PASS: no log file persisted for non-jj repo"
    pass=$((pass+1))
else
    echo "FAIL: log file appeared for non-jj repo (before=$log_files_before after=$log_files_after)"
    fail=$((fail+1))
fi

# The dirty 'extra.txt' must not be committed or pushed. The old git-only
# path would have add+commit+push'd it to origin/mainline (which would have
# failed with rc=1 for CR-protected mainline, and also unintentionally
# invoked commit-msg's LLM chain on the diff).
extra_committed=$(git -C "$TMPDIR/repoPlainGit" log --all --pretty=format:%H -- extra.txt 2>/dev/null | head -1)
if [ -z "$extra_committed" ]; then
    echo "PASS: dirty file was not committed (no auto-commit on non-jj path)"
    pass=$((pass+1))
else
    echo "FAIL: dirty file was committed: $extra_committed"
    fail=$((fail+1))
fi

# Crucially, the bare 'backup' remote must have received zero pushes — the
# old git-only path had a `$GIT push --verbose` that targeted the upstream,
# bypassing the backup remote entirely. Asserting the backup remote stays
# empty is the cleanest proof that the whole git-only flow is gone.
backup_refs=$(git -C "$TMPDIR/noop-backup.git" for-each-ref --format='%(refname)' 2>/dev/null)
if [ -z "$backup_refs" ]; then
    echo "PASS: backup bare remote received no pushes from non-jj repo"
    pass=$((pass+1))
else
    echo "FAIL: backup bare remote unexpectedly has refs: $backup_refs"
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
