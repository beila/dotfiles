#!/usr/bin/env bash

# shellcheck disable=SC2016
set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
ZSH_BIN=$(command -v zsh)
TEST_ROOT=$(mktemp -d /tmp/test-repo-history.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT

PASS=0
FAIL=0

pass() {
    printf 'PASS: %s\n' "$1"
    PASS=$((PASS + 1))
}

fail() {
    printf 'FAIL: %s\n  %s\n' "$1" "$2"
    FAIL=$((FAIL + 1))
}

mkdir -p \
    "$TEST_ROOT/main/.jj/repo" \
    "$TEST_ROOT/main/sub" \
    "$TEST_ROOT/linked/.jj" \
    "$TEST_ROOT/linked/sub" \
    "$TEST_ROOT/outside" \
    "$TEST_ROOT/state"
printf '%s' '../../main/.jj/repo' > "$TEST_ROOT/linked/.jj/repo"

run_zsh() {
    env -i \
        HOME="$HOME" \
        PATH="$PATH" \
        DOTFILES_ROOT="$DOTFILES_ROOT" \
        REPO_HISTORY_STATE_DIR="$TEST_ROOT/state" \
        TEST_ROOT="$TEST_ROOT" \
        "$ZSH_BIN" -f -c '
            source "$DOTFILES_ROOT/zsh/repo-history/00-core.zsh"
            source "$DOTFILES_ROOT/zsh/repo-history/10-fzf.zsh"
            eval "$1"
        ' zsh "$1"
}

printf '%s\n' '=== Test 1: sourcing is lazy ==='
out=$(run_zsh 'print -r -- "${_repo_history_repo_dir:-unset}"; [[ ! -e "$REPO_HISTORY_STATE_DIR/repos" ]]')
if [ "$out" = "unset" ]; then
    pass "source performs no repository or state initialization"
else
    fail "source initialized repository state" "got: $out"
fi

printf '%s\n' '=== Test 2: linked workspaces share repository identity ==='
out=$(run_zsh '
    cd "$TEST_ROOT/main/sub"
    _repo_history_resolve
    main_repo=$_repo_history_repo_dir
    main_file=$_repo_history_file
    cd "$TEST_ROOT/linked/sub"
    _repo_history_resolve
    print -rl -- "$main_repo" "$_repo_history_repo_dir" "$main_file" "$_repo_history_file"
')
line1=$(printf '%s\n' "$out" | sed -n '1p')
line2=$(printf '%s\n' "$out" | sed -n '2p')
line3=$(printf '%s\n' "$out" | sed -n '3p')
line4=$(printf '%s\n' "$out" | sed -n '4p')
if [ "$line1" = "$line2" ] && [ "$line3" = "$line4" ]; then
    pass "main and linked jj workspaces share one history file"
else
    fail "workspace identities differ" "got: $out"
fi

printf '%s\n' '=== Test 3: outside a jj workspace has no repository scope ==='
out=$(run_zsh 'cd "$TEST_ROOT/outside"; _repo_history_resolve; print -r -- $?')
if [ "$out" = "1" ]; then
    pass "outside directory resolves to global-only history"
else
    fail "outside directory resolved as repository" "status: $out"
fi

printf '%s\n' '=== Test 4: logrun original command is recorded ==='
out=$(run_zsh '
    cd "$TEST_ROOT/linked/sub"
    _logrun_orig_buffer="tool $TEST_ROOT/linked/pkg"
    _repo_history_zshaddhistory "logrun --auto -- tool"
    _repo_history_resolve
    while IFS= read -r -d $'\''\0'\'' epoch &&
          IFS= read -r -d $'\''\0'\'' root &&
          IFS= read -r -d $'\''\0'\'' cwd &&
          IFS= read -r -d $'\''\0'\'' command; do
      print -rl -- "$root" "$cwd" "$command"
    done < "$_repo_history_file"
')
expected=$'tool '"$TEST_ROOT"'/linked/pkg'
recorded=$(printf '%s\n' "$out" | tail -n 1)
if [ "$recorded" = "$expected" ]; then
    pass "repository history records the typed command, not logrun wrapper"
else
    fail "wrong command recorded" "expected [$expected], got [$recorded]"
fi

printf '%s\n' '=== Test 5: workspace paths adapt with path boundaries ==='
out=$(run_zsh '
    old="$TEST_ROOT/linked"
    new="$TEST_ROOT/main"
    _repo_history_adapt_command "$old" "$new" \
      "tool --root=$old/pkg \"$old\" ${old}-suffix /prefix${old}/nested"
    print -r -- "$REPLY"
')
expected="tool --root=$TEST_ROOT/main/pkg \"$TEST_ROOT/main\" $TEST_ROOT/linked-suffix /prefix$TEST_ROOT/linked/nested"
if [ "$out" = "$expected" ]; then
    pass "exact workspace-root paths adapt without substring corruption"
else
    fail "path adaptation mismatch" "expected [$expected], got [$out]"
fi

printf '%s\n' '=== Test 6: repository candidates are newest-first and deduplicated ==='
out=$(run_zsh '
    cd "$TEST_ROOT/main"
    _repo_history_zshaddhistory "first"
    _repo_history_zshaddhistory $'\''multi\nline'\''
    _repo_history_zshaddhistory "first"
    output="$TEST_ROOT/candidates"
    _repo_history_write_repo_candidates "$output"
    while IFS= read -r -d $'\''\0'\'' item; do
      print -r -- "${item#*$'\''\t'\''}"
      print -r -- "---"
    done < "$output"
')
if [ "$(printf '%s\n' "$out" | rg -c '^first$')" = "1" ] &&
   printf '%s\n' "$out" | rg -q $'^multi$' &&
   printf '%s\n' "$out" | rg -q $'^line$'; then
    pass "repository candidates preserve multiline commands and remove duplicates"
else
    fail "candidate generation mismatch" "got: $out"
fi

printf '%s\n' '=== Test 7: global candidates have exact NUL framing ==='
run_zsh '
    builtin printf "%s\t%s\000" \
      3 $'\''multi\nline\n'\'' \
      2 $'\''single\n'\'' \
      1 $'\''single\n'\'' |
      _repo_history_filter_global_candidates >| "$TEST_ROOT/global-candidates"
'
printf 'g:3\tmulti\nline\0g:2\tsingle\0' > "$TEST_ROOT/global-expected"
if cmp -s "$TEST_ROOT/global-expected" "$TEST_ROOT/global-candidates"; then
    pass "global candidates emit one separator and preserve multiline commands"
else
    fail "global candidate framing or newline normalization failed" \
        "got: $(od -An -tx1 < "$TEST_ROOT/global-candidates")"
fi

printf '%s\n' '=== Test 8: selection supports multiline and multi-select ==='
out=$(run_zsh '
    selected="$TEST_ROOT/selected"
    print -rN -- $'\''r:1\tfirst\nline'\'' $'\''r:2\tsecond'\'' >| "$selected"
    BUFFER=""
    CURSOR=0
    LBUFFER=""
    _repo_history_apply_selection "$selected"
    print -r -- "$BUFFER"
    print -r -- "cursor=$CURSOR"
')
expected=$'first\nline\nsecond'
buffer=$(printf '%s\n' "$out" | sed '$d')
cursor=$(printf '%s\n' "$out" | tail -n 1)
if [ "$buffer" = "$expected" ] && [ "$cursor" = "cursor=17" ]; then
    pass "selected commands are inserted without execution"
else
    fail "selection application mismatch" "got: $out"
fi

printf '%s\n' '=== Test 9: scope action toggles and reloads NUL input ==='
printf '%s\n' repo > "$TEST_ROOT/scope"
printf 'global-entry\0' > "$TEST_ROOT/global-input"
printf 'repo-entry\0' > "$TEST_ROOT/repo-input"
sh "$DOTFILES_ROOT/zsh/repo-history/fzf-action" toggle "$TEST_ROOT/scope"
out=$(sh "$DOTFILES_ROOT/zsh/repo-history/fzf-action" list \
    "$TEST_ROOT/scope" "$TEST_ROOT/global-input" "$TEST_ROOT/repo-input" |
    od -An -c)
if [ "$(cat "$TEST_ROOT/scope")" = "global" ] &&
   printf '%s' "$out" | rg -q 'g.*l.*o.*b.*a.*l.*-.*e.*n.*t.*r.*y'; then
    pass "Ctrl-R helper switches scope and candidate source"
else
    fail "scope helper mismatch" "scope=$(cat "$TEST_ROOT/scope"), output=$out"
fi

printf '%s\n' '=== Test 10: widget inserts an adapted repository command ==='
printf '%s\n' \
    '#!/bin/sh' \
    "perl -0 -ne 'print; exit'" > "$TEST_ROOT/fake-fzf"
chmod +x "$TEST_ROOT/fake-fzf"
out=$(run_zsh '
    REPO_HISTORY_STATE_DIR="$TEST_ROOT/widget-state"
    _repo_history_clear_resolution
    _repo_history_ready_files=()
    cd "$TEST_ROOT/main"
    _repo_history_zshaddhistory "tool $TEST_ROOT/main/pkg"
    cd "$TEST_ROOT/linked"
    _repo_history_scope=repo
    __fzf_defaults() { :; }
    __fzfcmd() { print -r -- "$TEST_ROOT/fake-fzf"; }
    zle() { :; }
    BUFFER=""
    CURSOR=0
    LBUFFER=""
    fzf-history-widget
    print -r -- "$BUFFER"
')
expected="tool $TEST_ROOT/linked/pkg"
if [ "$out" = "$expected" ]; then
    pass "repository picker displays and inserts the current-workspace path"
else
    fail "widget inserted the wrong command" "expected [$expected], got [$out]"
fi

printf '%s\n' '=== Test 11: real fzf accepts the generated scope binding ==='
printf '%s\n' repo > "$TEST_ROOT/scope"
binding=$(run_zsh '
    _repo_history_toggle_binding \
      "$TEST_ROOT/scope" \
      "$TEST_ROOT/global-input" \
      "$TEST_ROOT/repo-input"
    print -r -- "$REPLY"
')
if printf 'repo-entry\0' |
   fzf --read0 --print0 --sync --bind "$binding" --filter=repo-entry \
       > "$TEST_ROOT/fzf-binding-output"; then
    fzf_status=0
else
    fzf_status=$?
fi
out=$(od -An -c < "$TEST_ROOT/fzf-binding-output")
if [ "$fzf_status" -eq 0 ] &&
   printf '%s' "$out" | rg -q 'r.*e.*p.*o.*-.*e.*n.*t.*r.*y'; then
    pass "fzf parses the toggle, reload, prompt, and header actions"
else
    fail "fzf rejected the scope binding" "status=$fzf_status, output=$out"
fi

printf '%s\n' '=== Results ==='
printf '%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
