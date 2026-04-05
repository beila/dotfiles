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

echo "_jh ctrl-o (insert new revision):"
out=$(capture _jh)
assert "has ctrl-o binding" "ctrl-o:" "$out"
assert "ctrl-o runs jj new --before" "jj new --before" "$out"
assert "ctrl-o reloads after insert" "reload" "$out"

echo "_jhh ctrl-o (insert new revision):"
out=$(capture _jhh)
assert "has ctrl-o binding" "ctrl-o:" "$out"
assert "ctrl-o runs jj new --before" "jj new --before" "$out"
assert "ctrl-o reloads after insert" "reload" "$out"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
