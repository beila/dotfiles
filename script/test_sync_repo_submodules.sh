#!/usr/bin/env bash
set -euo pipefail

dotfiles_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/sync_repo_submodules.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Test User"
export GIT_AUTHOR_EMAIL=test@example.com
export GIT_COMMITTER_NAME="$GIT_AUTHOR_NAME"
export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
export LOG_ROOT="$test_root/logs"
export LOG_REL_BASE="$test_root"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG
export SYNC_LOG_ROOT_KEEP=1
export XDG_STATE_HOME="$test_root/state"

submodule_path=tests/integration-tests/webassembly
child="$test_root/child"
source_repo="$test_root/source"
git init -q -b main "$child"
git -C "$child" commit -q --allow-empty -m "initial submodule"
child_before=$(git -C "$child" rev-parse HEAD)
git -C "$child" commit -q --allow-empty -m "updated submodule"
child_after=$(git -C "$child" rev-parse HEAD)

git init -q -b main "$source_repo"
git -C "$source_repo" config -f .gitmodules "submodule.$submodule_path.path" "$submodule_path"
git -C "$source_repo" config -f .gitmodules "submodule.$submodule_path.url" "$child"
git -C "$source_repo" add .gitmodules
git -C "$source_repo" update-index --add --cacheinfo "160000,$child_before,$submodule_path"
git -C "$source_repo" commit -q -m "initial parent"
git -C "$source_repo" checkout -q -b bitt
git -C "$source_repo" update-index --cacheinfo "160000,$child_after,$submodule_path"
git -C "$source_repo" commit -q -m "updated parent"
expected=$(git -C "$source_repo" rev-parse bitt)

make_checkout() {
    local checkout=$1
    git clone -q --no-local --single-branch -b main "$source_repo" "$checkout"
    git -C "$checkout" -c protocol.file.allow=always submodule update --init >/dev/null 2>&1
    jj git init --colocate "$checkout" >/dev/null 2>&1
    jj -R "$checkout" config set --repo user.name "$GIT_AUTHOR_NAME" >/dev/null 2>&1
    jj -R "$checkout" config set --repo user.email "$GIT_AUTHOR_EMAIL" >/dev/null 2>&1
    jj -R "$checkout" config set --repo 'revset-aliases."immutable_heads()"' 'root()'
    rm -rf "$checkout/.git/modules/$submodule_path"
}

# Confirm that the fixture triggers the reported Git error.
baseline="$test_root/baseline"
make_checkout "$baseline"
if git --git-dir="$baseline/.git" fetch --no-tags --no-write-fetch-head \
    --no-auto-maintenance "$source_repo" refs/heads/bitt >"$test_root/baseline.out" 2>&1; then
    printf 'FAIL: the missing submodule did not reproduce the fetch failure\n'
    exit 1
fi
if ! rg -q "Could not access submodule '$submodule_path'" "$test_root/baseline.out"; then
    cat "$test_root/baseline.out"
    printf 'FAIL: the fixture failed for a different reason\n'
    exit 1
fi
printf 'PASS: reproduced the missing-submodule fetch error\n'

fail=0
for mode in remote-bookmark bookmarks; do
    for recursion in default true; do
        checkout="$test_root/$mode-$recursion"
        export LOG_ROOT="$test_root/logs/$mode-$recursion"
        make_checkout "$checkout"
        jj -R "$checkout" config set --repo "sync.$mode" bitt@origin
        if [ "$recursion" = true ]; then
            git -C "$checkout" config fetch.recurseSubmodules true
        fi
        status=0
        bash "$dotfiles_root/script/sync_repo" "$checkout" \
            >"$test_root/$mode-$recursion.out" 2>&1 || status=$?
        actual=$(git --git-dir="$checkout/.git" rev-parse --verify refs/remotes/origin/bitt 2>/dev/null || true)
        if [ "$status" -eq 0 ] && [ "$actual" = "$expected" ] \
            && rg -q 'FETCH-OK bitt@origin' "$LOG_ROOT" \
            && ! rg -q 'ERROR|CRITICAL' "$LOG_ROOT"; then
            printf 'PASS: %s fetches the parent with recursion=%s\n' "$mode" "$recursion"
        else
            printf 'FAIL: %s with recursion=%s returned %s; tracking ref=%s\n' \
                "$mode" "$recursion" "$status" "$actual"
            cat "$test_root/$mode-$recursion.out"
            rg -n 'ERROR|Could not access submodule' "$LOG_ROOT" || true
            fail=$((fail + 1))
        fi
    done
done

[ "$fail" -eq 0 ]
