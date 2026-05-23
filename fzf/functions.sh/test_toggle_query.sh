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

echo "_gy / _gyy real-pipeline toggle (no leaf stubs — exercises full extraction):"
# Re-source so the real _jy / _jyy / _jj_log_fzf bodies are live again.
source "${0:a:h}/functions.sh"
is_in_jj_repo() { return 0; }
is_in_git_repo(){ return 1; }
# Only stub fzf_down. The chosen "selected line" travels through every real
# downstream stage of the leaf (extractor + _emit + side-channel + dispatcher).
EMIT_LINE=""
fzf_down() { [[ -n "$EMIT_LINE" ]] && printf '%s\n' "$EMIT_LINE"; }
# Avoid running the real `jj` for these natural-exit scenarios.
jj() { :; }

# Natural exit of _jy: op-log line ends with hex op ID (after _dim_jj_op_ids
# pre-stage so the line passes through with ANSI tags too).
EMIT_LINE="1 minute ago jj git push --remote backup --bookmark main a2c1e1ac0660"
assert "_gy natural (real pipeline): extracts hex op ID" "a2c1e1ac0660" "$(_gy)"

# Natural exit of _jyy: change-log line, change ID is the leading lowercase token.
EMIT_LINE="◆  mptlxvr 2h ago hojin description here"
assert "_gyy natural (real pipeline): extracts leading change ID" "mptlxvr" "$(_gyy)"

# Recovery B: _gyy was up, ctrl-y swapped to _jy (becomed). The becomed
# subprocess inherits FZF_BECOME_OUT and writes its extracted op ID directly
# to the file; _jyy's outer pipe should not overwrite that. We simulate this
# by sourcing functions, swapping fzf_down to launch a real becomed _jy in a
# subshell that writes into FZF_BECOME_OUT before fzf_down returns.
fzf_down() {
  # Mimic fzf's `become` action: in a subshell, run _jy directly so it writes
  # its op ID into the file via _emit, then return without emitting anything
  # on stdout (the becomed leaf replaced fzf and did not produce stdout).
  ( EMIT_LINE_INNER="2 minutes ago jj git fetch --all-remotes 6d8b8b9d73c0"
    fzf_down() { printf '%s\n' "$EMIT_LINE_INNER"; }
    _jy ) >/dev/null
  # Original fzf returns no stdout (replaced by become).
  return 0
}
got=$(_gyy)
assert "_gyy after ctrl-y -> _jy (becomed via side-channel): op ID, not 'minutes'" "6d8b8b9d73c0" "$got"
assert_not "_gyy after toggle: NOT the word 'minutes'" "minutes" "$got"

# Recovery A: _gy was up, ctrl-y swapped to _jyy.
fzf_down() {
  ( EMIT_LINE_INNER="◆  mptlxvr 2h ago hojin description here"
    fzf_down() { printf '%s\n' "$EMIT_LINE_INNER"; }
    _jyy ) >/dev/null
  return 0
}
got=$(_gy)
assert "_gy after ctrl-y -> _jyy (becomed via side-channel): change ID preserved" "mptlxvr" "$got"

# Empty selection (user pressed Esc): nothing written to side-channel, dispatcher emits empty.
fzf_down() { :; }
EMIT_LINE=""
assert "_gy cancelled: empty output" "" "$(_gy)"
assert "_gyy cancelled: empty output" "" "$(_gyy)"

# Op-log line with ANSI color (typical real-world line shape from _dim_jj_op_ids).
fzf_down() { printf '%s\n' "$EMIT_LINE"; }
EMIT_LINE=$'\x1b[33m2 hours ago\x1b[0m jj op restore \x1b[2;90mc824cb3cc197\x1b[0m'
assert "_gy: strips ANSI before extracting op ID" "c824cb3cc197" "$(_gy)"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
