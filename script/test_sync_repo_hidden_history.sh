#!/usr/bin/env bash
set -euo pipefail

dotfiles_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/sync_repo_hidden_history.XXXXXX)
trap 'rm -rf "$test_root"' EXIT

export LOG_ROOT="$test_root/logs"
export LOG_REL_BASE="$test_root"
export LOG_NOTIFY_MODE=never
export LOG_KEEP_THRESHOLD=DEBUG
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

for mode in remote-bookmark bookmarks; do
    checkout="$test_root/local-$mode"
    remote="$test_root/remote-$mode.git"
    git init --bare -q -b main "$remote"
    jj git init --colocate "$checkout" >/dev/null 2>&1
    (
        cd "$checkout"
        jj config set --repo user.name "Test User"
        jj config set --repo user.email test@example.com
        jj config set --repo 'revset-aliases."immutable_heads()"' 'root()'
        jj config set --repo "sync.$mode" main@origin
        printf 'shared.txt merge=text\n' > .gitattributes
        printf 'base\n' > shared.txt
        jj describe -m base >/dev/null 2>&1
        jj new -m "shared change" >/dev/null 2>&1
        printf 'remote\n' > shared.txt
        jj bookmark create main -r @ >/dev/null 2>&1
        original=$(jj log -r @ --no-graph -T commit_id)
        jj new -m "remote-only descendant" >/dev/null 2>&1
        printf 'remote-only\n' > remote.txt
        jj bookmark set main -r @ >/dev/null 2>&1
        jj git remote add origin "$remote"
        jj git push --remote origin --bookmark main >/dev/null 2>&1
        jj edit "$original" >/dev/null 2>&1
        printf 'local\n' > shared.txt
        jj describe -m "local replacement" >/dev/null 2>&1
        unused_descendant=$(jj log -r main --no-graph -T commit_id)
        jj bookmark set main -r @ --allow-backwards >/dev/null 2>&1
        jj new >/dev/null 2>&1
        jj abandon "$unused_descendant" >/dev/null 2>&1
        jj abandon -r '::main@origin ~ ::@' >/dev/null 2>&1
    )
    visible_before=$(jj -R "$checkout" log -r 'all()' --no-graph -T 'commit_id ++ "\n"' | sort)
    local_before=$(jj -R "$checkout" log -r main --no-graph -T commit_id)
    working_before=$(jj -R "$checkout" log -r @ --no-graph -T commit_id)
    remote_before=$(git --git-dir="$remote" rev-parse main)
    check "$mode: the abandoned remote version starts hidden" "" \
        "$(jj -R "$checkout" log -r 'divergent()' --no-graph -T change_id)"

    for attempt in first second; do
        bash "$dotfiles_root/script/sync_repo" "$checkout" > "$test_root/$mode-$attempt.out" 2>&1
        check "$mode: the $attempt failed probe preserves visible history" "$visible_before" \
            "$(jj -R "$checkout" log -r 'all()' --no-graph -T 'commit_id ++ "\n"' | sort)"
        check "$mode: the $attempt failed probe preserves the bookmark" "$local_before" \
            "$(jj -R "$checkout" log -r main --no-graph -T commit_id)"
        check "$mode: the $attempt failed probe preserves the working copy" "$working_before" \
            "$(jj -R "$checkout" log -r @ --no-graph -T commit_id)"
        check "$mode: the $attempt failed probe preserves the remote" "$remote_before" \
            "$(git --git-dir="$remote" rev-parse main)"
    done
    check "$mode: the merge conflict is reported" true \
        "$(rg -q 'REBASE-CONFLICT main' "$LOG_ROOT" && printf true)"
done

[ "$fail" -eq 0 ]
