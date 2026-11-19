#!/usr/bin/env bash
set -euo pipefail

script_dir=$(cd "$(dirname "$0")" && pwd)
export TEST_WRAPPER=${1:-"$script_dir/bin/jj-serialized"}
test_dir=$(mktemp -d /tmp/jj-serialized-pager.XXXXXXXX)
repo="$test_dir/repo"
export TEST_PAGER_DIR="$test_dir"
viewer=
cleanup() {
    touch "$test_dir/close"
    if [[ -n $viewer ]]; then wait "$viewer" || true; fi
    rm -rf "$test_dir"
}
trap cleanup EXIT

export JJ_CONFIG='' JJ_USER=Test JJ_EMAIL=test@example.org
export XDG_CONFIG_HOME="$test_dir/config" XDG_STATE_HOME="$test_dir/state"
unset JJ_SERIALIZED_LOCK_HELD JJ_SERIALIZED_READ_ONLY
export JJ_REAL_EXECUTABLE="$test_dir/native-jj" JJ_PAGER="$test_dir/pager"
cat > "$JJ_REAL_EXECUTABLE" <<'EOF'
#!/usr/bin/env bash
JJ_SERIALIZED_LOCK_HELD=1 exec jj "$@"
EOF
cat > "$JJ_PAGER" <<'EOF'
#!/usr/bin/env bash
set -eu
cat > "$TEST_PAGER_DIR/output"
touch "$TEST_PAGER_DIR/ready"
while [[ ! -e $TEST_PAGER_DIR/close ]]; do sleep 0.05; done
EOF
chmod +x "$JJ_REAL_EXECUTABLE" "$JJ_PAGER"

in_terminal() {
    local command
    printf -v command '%q ' "$@"
    SHELL=$BASH script -qec "exec $command" /dev/null </dev/null
}

"$JJ_REAL_EXECUTABLE" git init --colocate "$repo"
cd "$repo"
historical=$("$JJ_REAL_EXECUTABLE" --ignore-working-copy op log -G -n 1 -T id)
before=$("$JJ_REAL_EXECUTABLE" --ignore-working-copy log -G -r @ -T commit_id)
printf 'new content\n' > tracked
# Keep the pager open in a terminal while a second process adds a workspace.
in_terminal "$TEST_WRAPPER" log -r @ --no-graph -T commit_id tracked > "$test_dir/terminal" 2>&1 &
viewer=$!
for _ in {1..200}; do
    [[ -e $test_dir/ready ]] && break
    sleep 0.025
done
if [[ ! -e $test_dir/ready ]]; then
    cat "$test_dir/terminal" >&2
    echo 'FAIL: jj did not finish sending output to the pager' >&2
    exit 1
fi
snapshot=$("$JJ_REAL_EXECUTABLE" --ignore-working-copy --at-op=@ log --no-graph -r @ -T commit_id)
if [[ $snapshot == "$before" ]] || ! rg -Fq "$snapshot" "$test_dir/output"; then
    echo 'FAIL: the paged file history missed the working-copy change' >&2
    exit 1
fi
if ! timeout 3 "$TEST_WRAPPER" -R "$repo" workspace add "$test_dir/linked"; then
    echo 'FAIL: workspace add could not finish while the history pager was open' >&2
    exit 1
fi
test -d "$test_dir/linked/.jj"
kill -0 "$viewer"
touch "$test_dir/close"
wait "$viewer"
viewer=
echo 'PASS: workspace add finishes with the current file history still open in a pager'

export JJ_PAGER=cat
printf 'more content\n' >> tracked
assert_view() {
    local expected=$1
    shift
    in_terminal "$TEST_WRAPPER" "$@" --color=never > "$test_dir/view"
    if ! rg -Fq "$expected" "$test_dir/view"; then
        cat "$test_dir/view" >&2
        printf 'FAIL: expected %s in the output of jj %s\n' "$expected" "$*" >&2
        exit 1
    fi
}
assert_view "$before" log -R "$repo" --at-op "$historical" -G -r @ -T commit_id
cd "$test_dir"
assert_view "$snapshot" --repository=repo --ignore-working-copy log -G -r @ -T commit_id
echo 'PASS: historical views and --ignore-working-copy honor the selected snapshot'

assert_view 'more content' -R=repo diff --git
current=$("$JJ_REAL_EXECUTABLE" -R "$repo" --ignore-working-copy log -G -r @ -T commit_id)
assert_view "$current" -R repo -r @ -G -T commit_id
echo 'PASS: diff and the default log include edits in the selected repository'
