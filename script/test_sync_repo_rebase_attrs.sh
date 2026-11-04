#!/usr/bin/env bash
set -euo pipefail

dotfiles_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/sync_repo_rebase_attrs.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

export LOG_ROOT="$test_root/logs"
export LOG_REL_BASE="$test_root"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG
export SYNC_LOG_ROOT_KEEP=1
export XDG_STATE_HOME="$test_root/state"

mkdir -p "$test_root/bin"
for tool in claude kiro-cli ollama; do
    printf '#!/bin/sh\nexit 1\n' > "$test_root/bin/$tool"
    chmod +x "$test_root/bin/$tool"
done
export PATH="$test_root/bin:$PATH"

git init --bare -q -b main "$test_root/remote.git"
git init -q -b main "$test_root/seed"
(
    cd "$test_root/seed"
    git config user.name "Test User"
    git config user.email test@example.com
    printf 'events.txt merge=union\n' > .gitattributes
    printf 'base\n' > events.txt
    git add .
    git commit -qm base
    git remote add origin "$test_root/remote.git"
    git push -q origin main
)
git clone -q "$test_root/remote.git" "$test_root/local"
(
    cd "$test_root/local"
    jj git init --colocate >/dev/null 2>&1
    jj config set --repo user.name "Test User" >/dev/null 2>&1
    jj config set --repo user.email test@example.com >/dev/null 2>&1
    jj config set --repo sync.remote-bookmark main@origin
    jj config set --repo sync.repo-history false
    printf 'local-first\n' >> events.txt
    jj describe -m "first local event" >/dev/null 2>&1
    jj new >/dev/null 2>&1
    printf 'local-second\n' >> events.txt
    jj describe -m "second local event" >/dev/null 2>&1
    jj new >/dev/null 2>&1
    printf 'tip\n' > tip.txt
    jj describe -m "local tip" >/dev/null 2>&1
    jj new >/dev/null 2>&1
)
(
    cd "$test_root/seed"
    printf 'remote\n' >> events.txt
    git commit -qam "remote event"
    git push -q origin main
)

remote_before_sync=$(git --git-dir="$test_root/remote.git" rev-parse main)
bash "$dotfiles_root/script/sync_repo" "$test_root/local" > "$test_root/sync.out" 2>&1

fail=0
check() {
    if [ "$2" = "$3" ]; then
        printf 'PASS: %s\n' "$1"
    else
        printf 'FAIL: %s\n  expected: %s\n  actual: %s\n' "$1" "$2" "$3"
        fail=$((fail + 1))
    fi
}

remote_tip=$(git --git-dir="$test_root/remote.git" rev-parse main)
local_tip=$(cd "$test_root/local" && jj log -r @- --no-graph -T commit_id)
check "the rebased tip reaches the remote" "$local_tip" "$remote_tip"
check "all events survive the rebase" $'base\nlocal-first\nlocal-second\nremote' \
    "$(git --git-dir="$test_root/remote.git" show main:events.txt | sort)"
check "the unrelated tip change survives" tip \
    "$(git --git-dir="$test_root/remote.git" show main:tip.txt 2>/dev/null || true)"
check "the rebased history has no conflicts" "" \
    "$(cd "$test_root/local" && jj log -r "(${remote_before_sync}..@) & conflicts()" --no-graph -T 'change_id ++ "\n"')"

(
    cd "$test_root/seed"
    git pull -q --ff-only origin main
    printf 'events.txt merge=text\n' > .gitattributes
    git commit -qam "require manual text resolution"
    git push -q origin main
)
git clone -q "$test_root/remote.git" "$test_root/conflict-local"
(
    cd "$test_root/conflict-local"
    jj git init --colocate >/dev/null 2>&1
    jj config set --repo user.name "Test User" >/dev/null 2>&1
    jj config set --repo user.email test@example.com >/dev/null 2>&1
    jj config set --repo sync.remote-bookmark main@origin
    jj config set --repo sync.repo-history false
    printf 'conflicting local event\n' > events.txt
    jj describe -m "conflicting intermediate event" >/dev/null 2>&1
    jj new >/dev/null 2>&1
    printf 'shared final event\n' > events.txt
    jj describe -m "same final event as remote" >/dev/null 2>&1
    jj new >/dev/null 2>&1
)
(
    cd "$test_root/seed"
    printf 'shared final event\n' > events.txt
    git commit -qam "same final event as local"
    git push -q origin main
)
remote_before_conflict=$(git --git-dir="$test_root/remote.git" rev-parse main)
local_before_conflict=$(cd "$test_root/conflict-local" && jj log -r @- --no-graph -T commit_id)
bash "$dotfiles_root/script/sync_repo" "$test_root/conflict-local" > "$test_root/conflict-sync.out" 2>&1
check "an unresolved intermediate conflict does not reach the remote" "$remote_before_conflict" \
    "$(git --git-dir="$test_root/remote.git" rev-parse main)"
check "an unresolved intermediate conflict restores local history" "$local_before_conflict" \
    "$(cd "$test_root/conflict-local" && jj log -r @- --no-graph -T commit_id)"
check "a failed rebase leaves the working copy without conflicts" "" \
    "$(cd "$test_root/conflict-local" && jj log -r '@ & conflicts()' --no-graph -T change_id)"

if [ "$fail" -ne 0 ]; then
    cat "$test_root/sync.out"
    cat "$test_root/conflict-sync.out"
    rg 'REBASE-CONFLICT|RESOLVED-BY-ATTRS|ERROR' "$LOG_ROOT" || true
    exit 1
fi
