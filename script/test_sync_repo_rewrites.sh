#!/usr/bin/env bash
set -euo pipefail

dotfiles_root=$(cd "$(dirname "$0")/.." && pwd)
test_root=$(mktemp -d /tmp/sync_repo_rewrites.XXXXXX)
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

for scenario in empty-ancestor changed-ancestor empty-tip; do
    checkout="$test_root/$scenario"
    remote="$test_root/$scenario.git"
    git init --bare -q -b main "$remote"
    jj git init --colocate "$checkout" >/dev/null 2>&1
    (
        cd "$checkout"
        jj config set --repo user.name "Test User"
        jj config set --repo user.email test@example.com
        jj config set --repo 'revset-aliases."immutable_heads()"' 'root()'
        jj config set --repo sync.bookmarks main@origin
        printf 'shared.txt merge=text\n' > .gitattributes
        printf 'base\n' > shared.txt
        jj describe -m base >/dev/null 2>&1
        jj bookmark create base -r @ >/dev/null 2>&1

        jj new base -m "first branch" >/dev/null 2>&1
        printf 'remote\n' > shared.txt
        jj bookmark create first -r @ >/dev/null 2>&1
        jj new base -m "second branch" >/dev/null 2>&1
        printf 'second\n' > second.txt
        jj bookmark create second -r @ >/dev/null 2>&1
        jj new first second -m "intermediate merge" >/dev/null 2>&1
        if [ "$scenario" = changed-ancestor ]; then
            printf 'merge-only\n' > shared.txt
        fi
        jj bookmark create intermediate -r @ >/dev/null 2>&1
        if [ "$scenario" != empty-tip ]; then
            jj new -m "integration tip" >/dev/null 2>&1
        fi
        jj bookmark create main -r @ >/dev/null 2>&1
        jj git remote add origin "$remote"
        jj git push --remote origin --bookmark main >/dev/null 2>&1

        jj edit first >/dev/null 2>&1
        printf 'local\n' > shared.txt
        jj log -r @ --no-graph -T commit_id >/dev/null
        if [ "$scenario" = empty-tip ]; then
            jj new first second -m "independent merge" >/dev/null 2>&1
            jj bookmark set main -r @ --allow-backwards >/dev/null 2>&1
        else
            jj rebase -r main -d first -d second >/dev/null 2>&1
            jj edit main >/dev/null 2>&1
        fi
        jj new >/dev/null 2>&1
    )

    local_before=$(jj -R "$checkout" log -r main --no-graph -T commit_id)
    remote_before=$(git --git-dir="$remote" rev-parse main)
    obsolete_merge=$(git --git-dir="$remote" rev-parse main^)
    bash "$dotfiles_root/script/sync_repo" "$checkout" > "$test_root/$scenario.out" 2>&1
    remote_after=$(git --git-dir="$remote" rev-parse main)

    if [ "$scenario" = empty-ancestor ]; then
        check "an obsolete empty merge permits the rewritten tip" "$local_before" "$remote_after"
        check "the local edit reaches the remote" local \
            "$(git --git-dir="$remote" show main:shared.txt)"
        check "the second branch remains in the merge" second \
            "$(git --git-dir="$remote" show main:second.txt)"
        check "the obsolete merge stays outside the published ancestry" "" \
            "$(jj -R "$checkout" log -r "${obsolete_merge} & ::main@origin" --no-graph -T commit_id)"
        check "the rewrite is recognized" true \
            "$(rg -q "REWRITTEN main@origin" "$LOG_ROOT" && printf true)"
    else
        check "$scenario: unproven remote history is preserved" "$remote_before" "$remote_after"
        check "$scenario: the local bookmark is preserved" "$local_before" \
            "$(jj -R "$checkout" log -r main --no-graph -T commit_id)"
        check "$scenario: the conflict is reported" true \
            "$(rg -q -g "*${scenario}*.log" 'REBASE-CONFLICT main' "$LOG_ROOT" && printf true)"
    fi
done

[ "$fail" -eq 0 ]
