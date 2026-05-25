#!/usr/bin/env bash
# Smoke test for script/sync_repo. Creates throwaway jj/git repos sharing a
# bare remote, drives sync_repo through:
#   - local-ahead: bookmark push path
#   - divergence (non-conflicting edits): merge+push path
#   - dead remote (fake ssh): timeout-guard exits in bounded time
#   - no sync config: exits cleanly with NO-SYNC-CONFIG
#   - conflict divergence: REBASE-CONFLICT, no push
#   - non-jj repo: silent skip
# And asserts the snapshot-first ordering: per-host refs/heads/<MACHINE>/...
# always land on the snapshot URL even if the bookmark-sync step fails.
#
# Usage: bash script/test_sync_repo.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
SYNC_REPO="$DOTFILES_ROOT/script/sync_repo"

TMPDIR=$(mktemp -d /tmp/sync_repo_test.XXXXXX)
trap 'rm -rf "$TMPDIR"' EXIT

echo "=== test dir: $TMPDIR ==="

# Pin the logger to an isolated tempdir. SYNC_LOG_ROOT_KEEP=1 keeps sync_repo
# from unsetting it. LOG_KEEP_THRESHOLD=DEBUG so non-ERROR runs still write
# files for grep_has assertions. LOG_NOTIFY_MODE=never to skip Telegram.
export LOG_ROOT="$TMPDIR/logs"
export LOG_REL_BASE="$TMPDIR"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG
export SYNC_LOG_ROOT_KEEP=1

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

# Pretend hostname (used as the prefix for snapshot refs) is stable across the
# test so we can grep for a known string. Without this, the actual machine's
# hostname leaks into expected ref names.
export HOSTNAME=testhost
TESTHOST=testhost

# Aggregate log file for assertions: find all per-machine logs.
find_log() {
    find "$LOG_ROOT" -name 'sync_repo.*.log' -print -quit 2>/dev/null
}

# Shared bare remote.
git -C "$TMPDIR" init --bare -q -b master remote.git

# setup_repo <dirname> <extra-file> <extra-content>
# Seeds a colocated jj/git repo with an initial commit on master pushed to the
# shared bare remote, then appends <extra-content> as an in-progress working
# change. Configures both sync.remote-bookmark (drives bookmark sync) and
# sync.snapshot-url (drives per-host snapshot push) — the same bare remote
# serves both URLs in tests.
#
# `hostnamectl --pretty` is what sync_repo uses for $MACHINE_NAME; override
# via env so tests don't depend on real hostname. The fallback to
# `hostname -s` is what runs when hostnamectl is missing (most CI envs); we
# stub via PATH below so the result is predictable.
setup_repo() {
    local name=$1 extra_file=$2 extra_content=$3
    mkdir -p "$TMPDIR/$name"
    (
        cd "$TMPDIR/$name"
        jj git init --colocate
        jj git remote add backup "$TMPDIR/remote.git"
        jj config set --repo sync.remote-bookmark 'master@backup'
        jj config set --repo sync.snapshot-url "$TMPDIR/remote.git"
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

# Stub `hostname -s` (sync_repo's fallback when hostnamectl is unavailable)
# so $MACHINE_NAME is deterministic across test runs.
cat >"$TMPDIR/stubs/hostname" <<STUB
#!/bin/sh
echo "$TESTHOST"
STUB
chmod +x "$TMPDIR/stubs/hostname"
# Stub hostnamectl too — its --pretty output includes a literal newline that
# sync_repo greps out, but on machines where it's set we'd get the real name.
cat >"$TMPDIR/stubs/hostnamectl" <<'STUB'
#!/bin/sh
exit 1
STUB
chmod +x "$TMPDIR/stubs/hostnamectl"

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
echo "=== Scenario 1: local ahead of remote -> bookmark push + snapshot ==="
setup_repo repoA "a.txt" "from A"
run_sync "$TMPDIR/repoA"
remote_master=$(git -C "$TMPDIR/remote.git" rev-parse master)
local_at_minus=$(cd "$TMPDIR/repoA" && jj log -r "@-" --no-graph -T 'commit_id')
check "remote master advanced to local @- after push" "$local_at_minus" "$remote_master"

# Snapshot push must have landed: refs/heads/<TESTHOST>/default exists on
# the bare remote at the same commit as @-.
snapshot_ref=$(git -C "$TMPDIR/remote.git" rev-parse "refs/heads/${TESTHOST}/default" 2>/dev/null)
check "workspace snapshot pushed to <host>/default" "$local_at_minus" "$snapshot_ref"

# The hostname-prefixed snapshot refs must NOT be visible in jj's local
# bookmark/remote-bookmark view: pushing to a URL directly (not a configured
# remote) skips refs/remotes/* updates, so jj never imports them.
hostname_prefixed_in_jj=$(cd "$TMPDIR/repoA" && jj bookmark list --all-remotes -T 'name ++ "@" ++ remote ++ "\n"' 2>/dev/null | grep -E "^${TESTHOST}/" | wc -l | tr -d ' ')
check "jj view has no hostname-prefixed remote bookmarks" "0" "$hostname_prefixed_in_jj"

echo
echo "=== Scenario 2: divergence -> rebase + push (different files -> no conflict) ==="
setup_repo repoB "b.txt" "from B"
setup_repo repoC "c.txt" "from C"
# repoB pushes first -> becomes remote tip
run_sync "$TMPDIR/repoB"
# repoC now has local divergence relative to remote (edits a different file)
run_sync "$TMPDIR/repoC"

remote_after=$(git -C "$TMPDIR/remote.git" rev-parse master)
local_c_at_minus=$(cd "$TMPDIR/repoC" && jj log -r "@-" --no-graph -T 'commit_id')
check "local @- and remote master match after rebase" "$local_c_at_minus" "$remote_after"

# Verify the rebased commit has 1 parent (linear history, no merge commit)
parent_count=$(cd "$TMPDIR/repoC" && jj log -r "@-" --no-graph -T 'parents.len()')
check "rebased commit has 1 parent (linear history)" "1" "$parent_count"

# Verify the description is the original c.txt change description (not "Merge ...")
rebased_desc=$(cd "$TMPDIR/repoC" && jj log -r "@-" --no-graph -T 'description.first_line()')
case "$rebased_desc" in
    Merge*) echo "FAIL: rebased description starts with 'Merge' (got: '$rebased_desc')"; fail=$((fail+1)) ;;
    "")     echo "FAIL: rebased description is empty"; fail=$((fail+1)) ;;
    *)      echo "PASS: rebased description preserved (got: '$rebased_desc')"; pass=$((pass+1)) ;;
esac

echo
echo "=== Scenario 3: sync log contains expected tags ==="
grep_has() {
    local pattern=$1
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
# Replaced the real SSH blackhole approach with a deterministic fake ssh
# that sleeps long past any timeout — every call hits SYNC_REPO_CMD_TIMEOUT
# exactly. Both `git` and `jj git fetch` honor $GIT_SSH_COMMAND.
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
# Override BOTH config sources to ssh URLs the fake ssh handles. The .invalid
# TLD ensures no real DNS resolution. The bookmark fetch hits the `backup`
# remote (set via jj git remote add) — but our fake ssh handles whatever host
# the URL points at.
(
    cd "$TMPDIR/repoH"
    jj git remote set-url backup "ssh://git@blackhole.invalid/repo.git"
    jj config set --repo sync.snapshot-url "ssh://git@blackhole.invalid/repo.git"
)
# Tight bound: with SYNC_REPO_CMD_TIMEOUT=1 and ~6 ssh-bearing calls, the run
# completes in ~6s. 15s gives generous headroom while still failing loudly if
# a regression makes the timeout guard ineffective.
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
# Log should mention TIMEOUT or NETWORK-ERR for the failed ops.
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
# Regression: when bookmark fetch fails (timeout / network), the bookmark
# push MUST be skipped. Otherwise stale ${SYNC_BM}@${SYNC_REMOTE} leads to
# wrong-path pushes (e.g. mistaking an existing remote bookmark for new and
# trying full-history push, which fails on any no-description ancestor).
if grep -rqE 'SKIP-PUSH master: fetch failed' "$LOG_ROOT"/*/sync_repo.*repoH* 2>/dev/null; then
    echo "PASS: log recorded SKIP-PUSH master: fetch failed"
    pass=$((pass+1))
else
    echo "FAIL: log missing 'SKIP-PUSH master: fetch failed' (bookmark sync should skip when fetch fails)"
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
echo "=== Scenario 5: no sync config -> NO-SYNC-CONFIG, clean exit ==="
# Old test asserted defensive behavior on empty BACKUP_URL drift. The new
# script reads sync.remote-bookmark and sync.snapshot-url from jj config
# directly (no git/jj remote discovery), so the relevant defensive case is
# "user hasn't configured either key yet".
mkdir -p "$TMPDIR/repoNoConfig"
(
    cd "$TMPDIR/repoNoConfig"
    jj git init --colocate
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo x > f; jj commit -m "init"
) >/dev/null 2>&1
bash "$SYNC_REPO" "$TMPDIR/repoNoConfig" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "PASS: sync_repo returned 0 with no sync config"
    pass=$((pass+1))
else
    echo "FAIL: sync_repo returned $rc with no sync config"
    fail=$((fail+1))
fi
if grep -rq 'NO-SYNC-CONFIG' "$LOG_ROOT"/*/sync_repo.*repoNoConfig* 2>/dev/null; then
    echo "PASS: log recorded NO-SYNC-CONFIG"
    pass=$((pass+1))
else
    echo "FAIL: log missing NO-SYNC-CONFIG"
    fail=$((fail+1))
fi
if grep -l '\[ERROR\]' "$LOG_ROOT"/*/sync_repo.*repoNoConfig* 2>/dev/null | grep -q .; then
    echo "FAIL: log has ERROR entries for no-config path (should not)"
    fail=$((fail+1))
else
    echo "PASS: no ERROR entries for no-config path"
    pass=$((pass+1))
fi

echo
echo "=== Scenario 6: divergence with conflict -> REBASE-CONFLICT, no push ==="
# Fresh bare remote so prior scenarios' state doesn't interfere.
git -C "$TMPDIR" init --bare -q -b master conflict.git
mkdir -p "$TMPDIR/conflict-base"
(
    cd "$TMPDIR/conflict-base"
    jj git init --colocate
    jj git remote add backup "$TMPDIR/conflict.git"
    jj config set --repo sync.remote-bookmark 'master@backup'
    jj config set --repo sync.snapshot-url "$TMPDIR/conflict.git"
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
local_x=$(cd "$TMPDIR/repoX" && jj log -r "@-" --no-graph -T 'commit_id')
check "remote advanced to repoX's @-" "$local_x" "$remote_after_x"

# repoY syncs and detects rebase conflict -> remote MUST be unchanged
run_sync "$TMPDIR/repoY"
remote_after_y=$(git -C "$TMPDIR/conflict.git" rev-parse master)
check "remote unchanged after repoY conflict" "$remote_after_x" "$remote_after_y"

# repoY's @- must NOT be a descendant of remote (rebase was blocked).
remote_in_local_y=$(cd "$TMPDIR/repoY" && jj log -r "$remote_after_x & ::@-" --no-graph -T '"y"' 2>/dev/null)
check "remote NOT ancestor of repoY @- (rebase blocked)" "" "$remote_in_local_y"

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

# Critical for the snapshot-first ordering: even though repoY's bookmark sync
# bailed out on conflict, the per-host SNAPSHOT must have landed on the
# server (it ran BEFORE the bookmark sync, so the conflict didn't gate it).
# The snapshot ref reflects repoY's local @-.
local_y_at_minus=$(cd "$TMPDIR/repoY" && jj log -r "@-" --no-graph -T 'commit_id')
y_snapshot=$(git -C "$TMPDIR/conflict.git" rev-parse "refs/heads/${TESTHOST}/default" 2>/dev/null)
check "repoY snapshot landed despite conflict (snapshot-first guarantee)" "$local_y_at_minus" "$y_snapshot"

echo
echo "=== Scenario 7: non-jj repo is silently skipped ==="
# sync_all blindly hands sync_repo every .git/.jj marker under $HOME, including
# Brazil-managed checkouts (~/devc/, ~/.toolbox/) and other plain-git repos.
# sync_repo's `jj root || exit 0` early-out drops these before any logging
# infra is sourced.
mkdir -p "$TMPDIR/repoPlainGit"
(
    cd "$TMPDIR/repoPlainGit"
    git init -q -b mainline
    git config user.email 'test@example.com'
    git config user.name  'Test User'
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
log_files_after=$(find "$LOG_ROOT" -name 'sync_repo.*repoPlainGit*' 2>/dev/null | wc -l)
if [ "$log_files_after" = "$log_files_before" ]; then
    echo "PASS: no log file persisted for non-jj repo"
    pass=$((pass+1))
else
    echo "FAIL: log file appeared for non-jj repo (before=$log_files_before after=$log_files_after)"
    fail=$((fail+1))
fi
extra_committed=$(git -C "$TMPDIR/repoPlainGit" log --all --pretty=format:%H -- extra.txt 2>/dev/null | head -1)
if [ -z "$extra_committed" ]; then
    echo "PASS: dirty file was not committed (no auto-commit on non-jj path)"
    pass=$((pass+1))
else
    echo "FAIL: dirty file was committed: $extra_committed"
    fail=$((fail+1))
fi
backup_refs=$(git -C "$TMPDIR/noop-backup.git" for-each-ref --format='%(refname)' 2>/dev/null)
if [ -z "$backup_refs" ]; then
    echo "PASS: backup bare remote received no pushes from non-jj repo"
    pass=$((pass+1))
else
    echo "FAIL: backup bare remote unexpectedly has refs: $backup_refs"
    fail=$((fail+1))
fi

echo
echo "=== Scenario 8: snapshot URL only (no remote-bookmark) ==="
# User configures only sync.snapshot-url; bookmark sync flow is a no-op.
mkdir -p "$TMPDIR/repoSnapOnly"
(
    cd "$TMPDIR/repoSnapOnly"
    jj git init --colocate
    jj config set --repo sync.snapshot-url "$TMPDIR/remote.git"
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo s > snap.txt
    jj commit -m "snapshot only"
) >/dev/null 2>&1
run_sync "$TMPDIR/repoSnapOnly"
local_so=$(cd "$TMPDIR/repoSnapOnly" && jj log -r "@-" --no-graph -T 'commit_id')
snap_pushed=$(git -C "$TMPDIR/remote.git" rev-parse "refs/heads/${TESTHOST}/default" 2>/dev/null)
check "snapshot-only: workspace snapshot landed" "$local_so" "$snap_pushed"
if grep -rqE 'FETCH-OK|PUSH-OK master' "$LOG_ROOT"/*/sync_repo.*repoSnapOnly* 2>/dev/null; then
    echo "FAIL: snapshot-only flow ran the bookmark-sync path"
    fail=$((fail+1))
else
    echo "PASS: snapshot-only flow skipped bookmark sync"
    pass=$((pass+1))
fi

echo
echo "=== Scenario 9: remote-bookmark only (no snapshot URL) ==="
mkdir -p "$TMPDIR/repoBmOnly"
(
    cd "$TMPDIR/repoBmOnly"
    jj git init --colocate
    jj git remote add backup "$TMPDIR/remote.git"
    jj config set --repo sync.remote-bookmark 'master@backup'
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo b > bm.txt
    jj commit -m "bookmark only"
    jj bookmark create master -r @-
) >/dev/null 2>&1
# Capture the snapshot-ref state BEFORE this run; this repo's MACHINE/default
# snapshot must NOT change (no snapshot URL set).
snap_before=$(git -C "$TMPDIR/remote.git" rev-parse "refs/heads/${TESTHOST}/default" 2>/dev/null || echo MISSING)
run_sync "$TMPDIR/repoBmOnly"
remote_master_after=$(git -C "$TMPDIR/remote.git" rev-parse master)
local_bo=$(cd "$TMPDIR/repoBmOnly" && jj log -r "@-" --no-graph -T 'commit_id')
check "bookmark-only: remote master advanced to local @-" "$local_bo" "$remote_master_after"
snap_after=$(git -C "$TMPDIR/remote.git" rev-parse "refs/heads/${TESTHOST}/default" 2>/dev/null || echo MISSING)
check "bookmark-only: snapshot ref unchanged (no snapshot URL set)" "$snap_before" "$snap_after"

echo
echo "=== Scenario 10: non-default workspace skips local-bookmark snapshots ==="
# Multi-workspace repo: the default workspace's local bookmarks (master)
# are shared via the .jj store. A non-default workspace running sync_repo
# should push its own workspace snapshot under <host>/<wsname>, but NOT
# re-push <host>/master — that's the default workspace's job.
mkdir -p "$TMPDIR/repoMultiWs"
(
    cd "$TMPDIR/repoMultiWs"
    jj git init --colocate
    jj git remote add backup "$TMPDIR/remote.git"
    jj config set --repo sync.remote-bookmark 'master@backup'
    jj config set --repo sync.snapshot-url "$TMPDIR/remote.git"
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo init > README.md
    jj commit -m "initial"
    jj bookmark create master -r @-
    jj git push --remote backup --bookmark master --allow-new
    # Add a second workspace alongside the default one.
    jj workspace add "$TMPDIR/repoMultiWs-second"
) >/dev/null 2>&1

# Wipe any leftover testhost/master from previous scenarios on the shared
# remote, so the "did this run push it?" assertion is clean.
git -C "$TMPDIR/remote.git" update-ref -d "refs/heads/${TESTHOST}/master" 2>/dev/null || true

# Run sync_repo from the SECOND workspace (non-default). It should push
# its own workspace snapshot but NOT testhost/master.
echo "second" > "$TMPDIR/repoMultiWs-second/notes.txt"
run_sync "$TMPDIR/repoMultiWs-second"

# Workspace snapshot for the second workspace must land.
second_at_minus=$(cd "$TMPDIR/repoMultiWs-second" && jj log -r "@-" --no-graph -T 'commit_id')
second_snap=$(git -C "$TMPDIR/remote.git" rev-parse "refs/heads/${TESTHOST}/repoMultiWs-second" 2>/dev/null)
check "non-default: workspace snapshot pushed under <host>/<wsname>" "$second_at_minus" "$second_snap"

# But the local-bookmark snapshot (master) must NOT be pushed by the non-
# default workspace — that's the default workspace's responsibility.
master_snap_after=$(git -C "$TMPDIR/remote.git" rev-parse --verify "refs/heads/${TESTHOST}/master" 2>/dev/null || echo MISSING)
check "non-default: <host>/master NOT pushed (gated to default workspace)" "MISSING" "$master_snap_after"

# Sanity: running sync_repo from the DEFAULT workspace DOES push <host>/master.
echo "first" > "$TMPDIR/repoMultiWs/notes.txt"
run_sync "$TMPDIR/repoMultiWs"
default_master_snap=$(git -C "$TMPDIR/remote.git" rev-parse --verify "refs/heads/${TESTHOST}/master" 2>/dev/null || echo MISSING)
local_master=$(cd "$TMPDIR/repoMultiWs" && jj log -r master --no-graph -T 'commit_id')
check "default: <host>/master pushed" "$local_master" "$default_master_snap"

echo
echo "=== Scenario 11: malformed sync.remote-bookmark -> ERROR + exit ==="
mkdir -p "$TMPDIR/repoBadBm"
(
    cd "$TMPDIR/repoBadBm"
    jj git init --colocate
    jj config set --repo sync.remote-bookmark 'no-at-sign'
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo x > f; jj commit -m "init"
) >/dev/null 2>&1
bash "$SYNC_REPO" "$TMPDIR/repoBadBm" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "PASS: sync_repo returned $rc for malformed sync.remote-bookmark"
    pass=$((pass+1))
else
    echo "FAIL: sync_repo returned 0 for malformed config (should reject)"
    fail=$((fail+1))
fi
if grep -rq 'BAD-CONFIG' "$LOG_ROOT"/*/sync_repo.*repoBadBm* 2>/dev/null; then
    echo "PASS: log recorded BAD-CONFIG for malformed value"
    pass=$((pass+1))
else
    echo "FAIL: log missing BAD-CONFIG for malformed value"
    fail=$((fail+1))
fi

echo
echo "=== Scenario 12: large file refused by jj snapshot -> ERROR + name in log ==="
# Simulate a >5MiB file that jj refuses to snapshot. The user needs to
# know — those files silently bypass the whole sync.
mkdir -p "$TMPDIR/repoBigFile"
(
    cd "$TMPDIR/repoBigFile"
    jj git init --colocate
    jj git remote add backup "$TMPDIR/remote.git"
    jj config set --repo sync.remote-bookmark 'master@backup'
    jj config set --repo sync.snapshot-url "$TMPDIR/remote.git"
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo "init" > README.md
    jj commit -m "initial"
    jj bookmark create master -r @-
    jj git push --remote backup --bookmark master --allow-new
    # Drop a >5MiB file that jj's default snapshot.max-new-file-size won't
    # accept (5MiB hard default).
    head -c 6000000 /dev/zero | tr '\0' 'x' > toobig.txt
) >/dev/null 2>&1

bash "$SYNC_REPO" "$TMPDIR/repoBigFile" >/dev/null 2>&1
if grep -rqE 'REFUSED-SNAPSHOT.*toobig\.txt' "$LOG_ROOT"/*/sync_repo.*repoBigFile* 2>/dev/null; then
    echo "PASS: log recorded REFUSED-SNAPSHOT with file name"
    pass=$((pass+1))
else
    echo "FAIL: log missing REFUSED-SNAPSHOT for toobig.txt"
    fail=$((fail+1))
fi
# Sanity: a clean repo without big files should NOT emit REFUSED-SNAPSHOT.
mkdir -p "$TMPDIR/repoCleanForRefusal"
(
    cd "$TMPDIR/repoCleanForRefusal"
    jj git init --colocate
    jj git remote add backup "$TMPDIR/remote.git"
    jj config set --repo sync.remote-bookmark 'master@backup'
    jj config set --repo sync.snapshot-url "$TMPDIR/remote.git"
    jj config set --repo user.email 'test@example.com'
    jj config set --repo user.name  'Test User'
    echo init > README.md
    jj commit -m "initial"
    jj bookmark create master -r @-
    jj git push --remote backup --bookmark master --allow-new
) >/dev/null 2>&1
bash "$SYNC_REPO" "$TMPDIR/repoCleanForRefusal" >/dev/null 2>&1
if grep -rqE 'REFUSED-SNAPSHOT' "$LOG_ROOT"/*/sync_repo.*repoCleanForRefusal* 2>/dev/null; then
    echo "FAIL: clean repo logged REFUSED-SNAPSHOT (should not)"
    fail=$((fail+1))
else
    echo "PASS: clean repo did not log REFUSED-SNAPSHOT"
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
