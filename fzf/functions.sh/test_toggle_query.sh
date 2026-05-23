#!/usr/bin/env zsh
# Test: fzf toggle functions preserve query and focus
# Run: zsh fzf/functions.sh/test_toggle_query.sh
# Requires: run from ~/.dotfiles (jj repo)

set -uo pipefail

pass=0 fail=0
assert() {
  if [[ "$3" == *"$2"* ]]; then
    echo "  ✓ $1"; ((pass++))
  else
    echo "  ✗ $1"; echo "    expected: $2"; echo "    got: $3"; ((fail++))
  fi
}
assert_not() {
  if [[ "$3" != *"$2"* ]]; then
    echo "  ✓ $1"; ((pass++))
  else
    echo "  ✗ $1"; echo "    unexpected: $2"; echo "    got: $3"; ((fail++))
  fi
}

source "${0:a:h}/functions.sh"

# Mock fzf — write args to temp file (survives pipes/subshells)
_args_file=$(mktemp)
trap "rm -f $_args_file" EXIT
fzf() { echo "$*" > "$_args_file"; }
fzf_down() { fzf "$@"; }
_jj_log_fzf() { fzf "$@"; }
capture() { echo -n '' > "$_args_file"; "$@" 2>/dev/null; cat "$_args_file"; }

echo "_jh:"
out=$(capture _jh)
assert_not "no args: no --query" "--query" "$out"
out=$(capture _jh "" "myquery")
assert "with query: --query" "--query myquery" "$out"
assert "become passes {q}" "{q}" "$out"

echo "_jhh:"
out=$(capture _jhh)
assert_not "no args: no --query" "--query" "$out"
out=$(capture _jhh "" "myquery")
assert "with query: --query" "--query myquery" "$out"
assert "become passes {q}" "{q}" "$out"

echo "_jb:"
out=$(capture _jb)
assert_not "no args: no --query" "--query" "$out"
assert_not "no args: no result:pos" "result:pos" "$out"
out=$(capture _jb "3" "myquery")
assert "with query: --query" "--query myquery" "$out"
assert "with pos: result:pos(4)" "result:pos(4)" "$out"
assert "become passes {n} {q}" "{n} {q}" "$out"

echo "_jbb:"
out=$(capture _jbb)
assert_not "no args: no --query" "--query" "$out"
out=$(capture _jbb "3" "myquery")
assert "with query: --query" "--query myquery" "$out"
assert "with pos: result:pos(4)" "result:pos(4)" "$out"
assert "become passes {n} {q}" "{n} {q}" "$out"

echo "_jyy:"
out=$(capture _jyy)
assert_not "no args: no --query" "--query" "$out"
out=$(capture _jyy "3" "myquery")
assert "with query: --query" "--query myquery" "$out"
assert "with pos: result:pos(4)" "result:pos(4)" "$out"
assert "become passes {n} {q}" "{n} {q}" "$out"

echo "_jy:"
out=$(capture _jy)
assert_not "no args: no --query" "--query" "$out"
out=$(capture _jy "3" "myquery")
assert "with query: --query" "--query myquery" "$out"
assert "with pos: result:pos(4)" "result:pos(4)" "$out"
assert "become passes {n} {q}" "{n} {q}" "$out"

echo "change ID extraction:"
extract() { echo "$1" | eval "${_jj_change_id//\{\}/\$(cat)}"; }
assert "single char ID" "t" "$(extract '@  t 24s ago (empty)')"
assert "multi char ID" "lkm" "$(extract '◆  lkm 2h ago desc')"
assert "empty on no match" "" "$(extract '~')"

echo "_jh ctrl-o (insert new revision):"
out=$(capture _jh)
assert "has ctrl-o binding" "ctrl-o:" "$out"
assert "ctrl-o runs jj new --no-edit --after" "jj new --no-edit --after" "$out"
assert "ctrl-o reloads on success" "reload" "$out"
assert "ctrl-o shows error on failure" "change-header" "$out"
assert "header mentions ctrl-o" "ctrl-o" "$out"

echo "_jhh ctrl-o (insert new revision):"
out=$(capture _jhh)
assert "has ctrl-o binding" "ctrl-o:" "$out"
assert "ctrl-o runs jj new --no-edit --after" "jj new --no-edit --after" "$out"
assert "ctrl-o reloads on success" "reload" "$out"
assert "ctrl-o shows error on failure" "change-header" "$out"
assert "header mentions ctrl-o" "ctrl-o" "$out"

echo "_gy / _gyy post-extraction (recovery toggle: ctrl-y swaps after accidental keypress):"
# Override fzf to ALSO emit a chosen "selected line" on stdout, simulating what
# the post-pipeline of the dispatcher will see. Each scenario picks the line
# representing what the toggled-to function would actually emit.
EMIT_LINE=""
fzf() { echo "$*" > "$_args_file"; [[ -n "$EMIT_LINE" ]] && printf '%s\n' "$EMIT_LINE"; }
fzf_down() { fzf "$@"; }
_jj_log_fzf() { fzf "$@"; }
# Stub the leaf functions so we test only the dispatcher's outer post-pipeline.
# A real toggle goes _jy -> become(_jyy) -> _jj_log_fzf prints a change ID;
# from _gy's perspective that is just stdin, regardless of which leaf wrote it.
_jy()    { printf '%s\n' "$EMIT_LINE"; }
_jyy()   { printf '%s\n' "$EMIT_LINE"; }
_git_y() { printf '%s\n' "$EMIT_LINE"; }
_git_yy(){ printf '%s\n' "$EMIT_LINE"; }
is_in_jj_repo() { return 0; }
is_in_git_repo(){ return 1; }

# Natural exit of _jy: op-log line ends with hex op ID
EMIT_LINE="1 minute ago jj git push --remote backup --bookmark main a2c1e1ac0660"
assert "_gy natural: extracts hex op ID from op-log line" "a2c1e1ac0660" "$(_gy)"

# Natural exit of _jyy: _jj_log_fzf already produced a single change ID
EMIT_LINE="mptlxvr"
assert "_gyy natural: passes change ID through" "mptlxvr" "$(_gyy)"

# Recovery case A: user typed ^G^Y (=> _gy), realised mistake, ctrl-y -> _jyy.
# _jyy via _jj_log_fzf emits a single change ID. Dispatcher must NOT mangle it.
EMIT_LINE="mptlxvr"
got=$(_gy)
assert "_gy after ctrl-y to _jyy: returns the change ID, not empty/mangled" "mptlxvr" "$got"
assert_not "_gy after toggle: not a hex op id" "a2c1e1ac0660" "$got"

# Recovery case B: user typed ^GY (=> _gyy), realised mistake, ctrl-y -> _jy.
# _jy emits the raw fzf-selected op-log line (no inner extraction). Dispatcher
# must extract the trailing hex op ID.
EMIT_LINE="2 hours ago jj git fetch --all-remotes 6d8b8b9d73c0"
got=$(_gyy)
assert "_gyy after ctrl-y to _jy: extracts hex op ID from raw line" "6d8b8b9d73c0" "$got"

# ANSI-stripped raw line (real op log has color)
EMIT_LINE=$'\x1b[33m2h\x1b[0m ago \x1b[32mjj op restore\x1b[0m \x1b[2;90mc824cb3cc197\x1b[0m'
got=$(_gyy)
assert "_gyy: strips ANSI before extracting op ID" "c824cb3cc197" "$got"

# Empty input (user cancelled fzf)
EMIT_LINE=""
got=$(_gy)
assert "_gy: empty input -> empty output (no extraction noise)" "" "$got"

echo
echo "_gy / _gyy real-pipeline toggle (no leaf stubs — exercises _jj_log_fzf tail):"
# Re-source so the real _jy / _jyy / _jj_log_fzf bodies are live again.
source "${0:a:h}/functions.sh"
is_in_jj_repo() { return 0; }
is_in_git_repo(){ return 1; }
# Only stub fzf_down so the chosen line travels through every real downstream
# stage (any extractor inside _jj_log_fzf, the leaf, and the dispatcher).
EMIT_LINE=""
fzf_down() { [[ -n "$EMIT_LINE" ]] && printf '%s\n' "$EMIT_LINE"; }
# Avoid running the real `jj` for these scenarios — the leaf functions only
# need their post-pipeline behaviour exercised.
jj() { :; }

# Recovery B (real pipeline): _jyy was up, ctrl-y swapped to _jy.
# The line emitted is what _jy (no inner extractor) would write: a raw op-log
# line. Inside _jyy this still flows through _jj_log_fzf's letter-extracting
# tail, which mauls it to "minutes" unless the dispatcher's extractor is
# robust to that.
EMIT_LINE="2 minutes ago jj git fetch --all-remotes 6d8b8b9d73c0"
got=$(_gyy)
assert "_gyy after ctrl-y -> _jy (real pipeline): hex op ID, not 'minutes'" "6d8b8b9d73c0" "$got"
assert_not "_gyy after toggle: not the word 'minutes'" "minutes" "$got"

# Recovery A (real pipeline): _jy was up, ctrl-y swapped to _jyy.
# _jyy emits a bare change ID; _jy has no inner extractor any more, so the
# dispatcher's extractor sees a single token directly.
EMIT_LINE="mptlxvr"
got=$(_gy)
assert "_gy after ctrl-y -> _jyy (real pipeline): change ID preserved" "mptlxvr" "$got"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
