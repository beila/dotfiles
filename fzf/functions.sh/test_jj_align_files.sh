#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

check_alignment() {
    local name=$1 input=$2 expected=$3
    printf '%b' "$input" > "$tmp/input"
    printf '%b' "$expected" > "$tmp/expected"
    gawk -f "$root/jj-align-files.awk" "$tmp/input" > "$tmp/actual"
    if ! diff -u "$tmp/expected" "$tmp/actual"; then
        printf 'FAIL: %s\n' "$name" >&2
        exit 1
    fi

    TEST_GRAPH_INPUT="$tmp/input" zsh -c '
        source "$1/functions.sh"
        JJ_FZF_OPERATION=test-operation
        jj() { cat "$TEST_GRAPH_INPUT"; }
        reload=$(_jj_log_reload "fzf_oneline ++ fzf_files_suffix" "all()")
        eval "${reload[8,-2]}"
    ' _ "$root" > "$tmp/reloaded"
    diff -u "$tmp/expected" "$tmp/reloaded"
    printf 'PASS: %s\n' "$name"
}

check_alignment 'merge junction keeps its graph columns' \
    '│ ○ │  change\n│ ├─╯  M first.txt\tchange\tfirst.txt\tcommit\n│ │   M second.txt\tchange\tsecond.txt\tcommit\n' \
    '│ ○ │  change\n│ ├─╯   M first.txt\tchange\tfirst.txt\tcommit\n│ │   M second.txt\tchange\tsecond.txt\tcommit\n'

check_alignment 'fork and elision keep their graph columns' \
    '│ │ ├─╮  A a\tid\ta\thash\n│ ├───╯  D b\tid\tb\thash\n│ ~  R c\tid\tc\thash\n╰─┬─╮  M d\tid\td\thash\n' \
    '│ │ ├─╮   A a\tid\ta\thash\n│ ├───╯   D b\tid\tb\thash\n│ ~   R c\tid\tc\thash\n╰─┬─╮   M d\tid\td\thash\n'

check_alignment 'file names and ANSI colours remain unchanged' \
    '│  \033[38;5;6mM dir/│ file\033[39m\t\033[35mid\033[0m\tdir/│ file\thash\n│ │   A dir/├─╮ name\tid\tdir/├─╮ name\thash\n' \
    '│   \033[38;5;6mM dir/│ file\033[39m\t\033[35mid\033[0m\tdir/│ file\thash\n│ │   A dir/├─╮ name\tid\tdir/├─╮ name\thash\n'

check_alignment 'commit, connector, and graphless rows remain unchanged' \
    '│ ○ │  description │ text\tid\t\thash\n│ ├─╯\n    M final.txt\tid\tfinal.txt\thash\n' \
    '│ ○ │  description │ text\tid\t\thash\n│ ├─╯\n    M final.txt\tid\tfinal.txt\thash\n'

# Check saved history without a worktree snapshot.
if [[ -d "$root/../../.jj" ]]; then
    JJ_SERIALIZED_READ_ONLY=1 jj --repository "$root/../.." --ignore-working-copy \
        --at-operation @ --no-pager log --color=never --limit 80 \
        -r 'merges() | parents(merges())' -T 'fzf_oneline ++ fzf_files_suffix' \
        > "$tmp/history"
    gawk -f "$root/jj-align-files.awk" "$tmp/history" > "$tmp/aligned"
    graph_prefix='^[ │─╭╮╯╰├┤┬┴┼~]*[│─╭╮╯╰├┤┬┴┼~]'
    rg -o "$graph_prefix" "$tmp/history" > "$tmp/graph-before"
    rg -o "$graph_prefix" "$tmp/aligned" > "$tmp/graph-after"
    diff -u "$tmp/graph-before" "$tmp/graph-after"
    cut -f2- "$tmp/history" > "$tmp/fields-before"
    cut -f2- "$tmp/aligned" > "$tmp/fields-after"
    diff -u "$tmp/fields-before" "$tmp/fields-after"
    printf 'PASS: real jj history keeps graph columns and selection fields\n'
fi

printf 'jj file graph alignment tests passed\n'
