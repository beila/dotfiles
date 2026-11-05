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

for mode in remote-bookmark bookmarks; do
    seed="$test_root/immutable-seed-$mode"
    checkout="$test_root/immutable-local-$mode"
    remote="$test_root/immutable-remote-$mode.git"
    git init --bare -q -b main "$remote"
    jj git init --colocate "$seed" >/dev/null 2>&1
    (
        cd "$seed"
        jj config set --repo user.name "Test User"
        jj config set --repo user.email test@example.com
        printf 'base\n' > base.txt
        jj describe -m base >/dev/null 2>&1
        jj bookmark create main -r @ >/dev/null 2>&1
        jj git remote add origin "$remote"
        jj git push --remote origin --bookmark main >/dev/null
    )
    jj git clone --colocate "$remote" "$checkout" >/dev/null 2>&1
    (
        cd "$checkout"
        jj config set --repo user.name "Test User"
        jj config set --repo user.email test@example.com
        jj config set --repo "sync.$mode" main@origin
        printf 'upstream\n' > upstream.txt
        jj describe -m upstream >/dev/null 2>&1
        jj bookmark set main -r @ >/dev/null 2>&1
        jj bookmark create upstream -r @ >/dev/null 2>&1
        jj new >/dev/null 2>&1
        jj config set --repo 'revset-aliases."immutable_heads()"' 'bookmarks(exact:"upstream")'
    )
    (
        cd "$seed"
        jj new main >/dev/null 2>&1
        printf 'remote\n' > remote.txt
        jj describe -m remote >/dev/null 2>&1
        jj bookmark set main -r @ >/dev/null 2>&1
        jj git push --remote origin --bookmark main >/dev/null
    )
    immutable_before=$(jj --repository "$checkout" log -r upstream --no-graph -T commit_id)
    remote_before=$(git --git-dir="$remote" rev-parse main)
    bash "$dotfiles_root/script/sync_repo" "$checkout" > "$test_root/immutable-$mode.out" 2>&1
    check "$mode: an immutable rebase does not change the remote" "$remote_before" \
        "$(git --git-dir="$remote" rev-parse main)"
    check "$mode: an immutable commit is preserved" "$immutable_before" \
        "$(jj --repository "$checkout" log -r upstream --no-graph -T commit_id)"
    diagnostics=$(rg -l "REBASE-FAIL main .*Commit ${immutable_before:0:12} is immutable" "$LOG_ROOT" || true)
    check "$mode: the failure log names the immutable commit" true \
        "$([ -n "$diagnostics" ] && printf true)"
    check "$mode: the log retains the complete stderr" true \
        "$([ -n "$diagnostics" ] && rg -q 'This operation would rewrite 1 immutable commits' "$diagnostics" && printf true)"

    if [ "$mode" = bookmarks ]; then
        integration_description="DO NOT ABANDON: placeholder for merging mainline and ready branches"
        jj --repository "$checkout" describe -r @ -m "$integration_description" >/dev/null 2>&1
        jj --repository "$checkout" bookmark set main -r @ >/dev/null 2>&1
        integration_change=$(jj --repository "$checkout" log -r @ --no-graph -T change_id)
        jj --repository "$checkout" new >/dev/null 2>&1
        bash "$dotfiles_root/script/sync_repo" "$checkout" > "$test_root/integration.out" 2>&1
        integration_tip=$(jj --repository "$checkout" log -r main --no-graph -T commit_id)
        check "the integration commit reaches the remote" "$integration_tip" \
            "$(git --git-dir="$remote" rev-parse main)"
        check "the integration change ID is preserved" "$integration_change" \
            "$(jj --repository "$checkout" log -r main --no-graph -T change_id)"
        check "the integration commit has two parents" 2 \
            "$(jj --repository "$checkout" log -r main --no-graph -T 'parents.len()')"
        check "the integration commit remains empty" true \
            "$(jj --repository "$checkout" log -r main --no-graph -T empty)"
        check "the upstream parent is not rewritten" "$immutable_before" \
            "$(jj --repository "$checkout" log -r 'upstream & main-' --no-graph -T commit_id)"
        check "the merge preserves the upstream file" upstream \
            "$(git --git-dir="$remote" show main:upstream.txt)"
        check "the merge preserves the remote file" remote \
            "$(git --git-dir="$remote" show main:remote.txt)"
        check "the empty merge keeps its description" "$integration_description" \
            "$(jj --repository "$checkout" log -r main --no-graph -T 'description.first_line()')"
    fi
done

for mode in remote-bookmark bookmarks; do
    checkout="$test_root/import-local-$mode"
    remote="$test_root/import-remote-$mode.git"
    git init --bare -q -b main "$remote"
    jj git init --colocate "$checkout" >/dev/null 2>&1
    (
        cd "$checkout"
        jj config set --repo user.name "Test User"
        jj config set --repo user.email test@example.com
        jj config set --repo 'revset-aliases."immutable_heads()"' 'root()'
        jj config set --repo git.abandon-unreachable-commits true
        jj config set --repo "sync.$mode" main@origin
        printf 'base\n' > base.txt
        jj describe -m base >/dev/null 2>&1
        jj new -m "main placeholder" >/dev/null 2>&1
        jj bookmark create main -r @ >/dev/null 2>&1
        jj new -m "dependent build change" >/dev/null 2>&1
        printf 'build\n' > build.txt
        jj bookmark create build -r @ >/dev/null 2>&1
        jj git remote add origin "$remote"
        jj git push --remote origin --bookmark main --bookmark build >/dev/null 2>&1
        jj new main >/dev/null 2>&1
        jj describe -r main -m "rewritten main placeholder" >/dev/null 2>&1
    )
    if [ "$mode" = remote-bookmark ]; then
        git --git-dir="$remote" fetch -q --no-tags --no-write-fetch-head --force "$checkout" main:main
    fi
    visible_before=$(jj --repository "$checkout" log -r 'all()' --no-graph -T 'commit_id ++ "\n"' | sort)
    build_before=$(jj --repository "$checkout" log -r build --no-graph -T commit_id)
    remote_build_before=$(git --git-dir="$remote" rev-parse build)
    bash "$dotfiles_root/script/sync_repo" "$checkout" > "$test_root/import-$mode.out" 2>&1
    check "$mode: the rewritten main reaches the remote" \
        "$(jj --repository "$checkout" log -r main --no-graph -T commit_id)" \
        "$(git --git-dir="$remote" rev-parse main)"
    check "$mode: importing the updated ref preserves visible history" "$visible_before" \
        "$(jj --repository "$checkout" log -r 'all()' --no-graph -T 'commit_id ++ "\n"' | sort)"
    check "$mode: importing main preserves the local dependent branch" "$build_before" \
        "$(jj --repository "$checkout" log -r build --no-graph -T commit_id)"
    check "$mode: importing main preserves the remote dependent branch" "$remote_build_before" \
        "$(jj --repository "$checkout" log -r build@origin --no-graph -T commit_id)"
done

if [ "$fail" -ne 0 ]; then
    cat "$test_root/sync.out"
    cat "$test_root/conflict-sync.out"
    rg 'REBASE-CONFLICT|RESOLVED-BY-ATTRS|ERROR' "$LOG_ROOT" || true
    exit 1
fi
