#!/usr/bin/env bash

set -eu

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
FILTER="$DOTFILES_ROOT/script/bin/generalize-paths"
TEST_HOME="/home/example"

check() {
    local name=$1 input=$2 expected=$3 actual
    actual=$(printf '%s\n' "$input" | HOME="$TEST_HOME" "$FILTER")
    if [ "$actual" != "$expected" ]; then
        printf 'FAIL: %s\nexpected: %s\nactual:   %s\n' "$name" "$expected" "$actual" >&2
        exit 1
    fi
    printf 'PASS: %s\n' "$name"
}

check "absolute home becomes standard placeholder" \
    "/prefix $TEST_HOME/project suffix" \
    '/prefix $HOME/project suffix'
check "existing placeholder stays unchanged" \
    '$HOME/project' \
    '$HOME/project'
check "legacy placeholder is normalized" \
    '$HOME/project' \
    '$HOME/project'
check "unrelated absolute path stays unchanged" \
    '/Users/other/project' \
    '/Users/other/project'
check "multiple home paths are generalized" \
    "$TEST_HOME/a:$TEST_HOME/b" \
    '$HOME/a:$HOME/b'

if printf 'x\n' | env -u HOME "$FILTER" >/dev/null 2>&1; then
    printf 'FAIL: unset HOME should fail\n' >&2
    exit 1
fi
printf 'PASS: unset HOME fails\n'

TMP_TEST=$(mktemp -d)
trap 'rm -rf "$TMP_TEST"' EXIT
printf 'prefix\0%s\n' "$TEST_HOME" > "$TMP_TEST/input"
HOME="$TEST_HOME" "$FILTER" < "$TMP_TEST/input" > "$TMP_TEST/output"
if ! cmp -s "$TMP_TEST/input" "$TMP_TEST/output"; then
    printf 'FAIL: binary input should pass through unchanged\n' >&2
    exit 1
fi
printf 'PASS: binary input passes through unchanged\n'
