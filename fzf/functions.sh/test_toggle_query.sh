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

echo "_jh / _jhh / _jyy / _jy pass --accept-nth so fzf does the extraction:"
# Re-source so the real bodies are live; mock fzf_down to capture args.
source "${0:a:h}/functions.sh"
fzf_down() { echo "$*" > "$_args_file"; }
_jj_log_fzf() { fzf_down "$@"; }
out=$(capture _jh);   assert "_jh has --accept-nth=2"   "--accept-nth=2"  "$out"
out=$(capture _jhh);  assert "_jhh has --accept-nth=2"  "--accept-nth=2"  "$out"
out=$(capture _jyy);  assert "_jyy has --accept-nth=2"  "--accept-nth=2"  "$out"
out=$(capture _jy);   assert "_jy has --accept-nth=-1"  "--accept-nth=-1" "$out"

echo
echo "_gh / _gy / _gyy real-fzf end-to-end (uses the real fzf binary in filter mode):"
# Re-source again so any stubs from the previous block are gone.
source "${0:a:h}/functions.sh"
is_in_jj_repo() { return 0; }
is_in_git_repo(){ return 1; }
# Stub jj to emit FZF_LINE on `jj log` / `jj operation log` calls; ignore
# everything else (any positional args, color flags, templates).
jj() {
  case "${1:-}" in
    --quiet) shift ;;
  esac
  case "${1:-}" in
    log|operation) printf '%s\n' "$FZF_LINE" ;;
    *) : ;;
  esac
}
# Use real fzf. Empty filter matches every line, fzf -1 auto-selects, the
# leaf's --accept-nth extracts the right field.
fzf_down() {
  command fzf --ansi -1 --filter '' "$@" 2>/dev/null
}

FZF_LINE="◆  mptlxvr 2h ago hojin description"
assert "_gh natural (real fzf): leading change ID extracted" "mptlxvr" "$(_gh)"
assert "_gyy natural (real fzf): leading change ID extracted" "mptlxvr" "$(_gyy)"

FZF_LINE="2 minutes ago jj git fetch --all-remotes 6d8b8b9d73c0"
assert "_gy natural (real fzf): trailing hex op ID extracted" "6d8b8b9d73c0" "$(_gy)"

# Op log line with ANSI codes (real _dim_jj_op_ids output)
FZF_LINE=$'\x1b[33m2 hours ago\x1b[0m jj op restore \x1b[2;90mc824cb3cc197\x1b[0m'
got=$(_gy)
assert "_gy strips ANSI from op ID via --accept-nth" "c824cb3cc197" "$got"
assert_not "_gy output has no ANSI codes" $'\x1b[' "$got"

# The original failing case: simulate the _jyy -> _jy toggle by running _jy
# directly with an op log line. Output must be the op ID, NOT "minutes".
FZF_LINE="2 minutes ago jj git fetch --all-remotes 6d8b8b9d73c0"
got=$(_gy)
assert "_jy on op log (toggle target): op ID, NOT 'minutes'" "6d8b8b9d73c0" "$got"
assert_not "_jy output: NOT 'minutes'" "minutes" "$got"

# Cancellation: filter that matches nothing → fzf prints nothing → dispatcher empty
fzf_down() { command fzf --ansi -1 --filter 'no-match-zzz' "$@" 2>/dev/null </dev/null; }
assert "_gy cancelled: empty output" "" "$(_gy)"
assert "_gyy cancelled: empty output" "" "$(_gyy)"

echo
echo "ctrl-/ preview-layout cycle (single source of truth in FZF_DEFAULT_OPTS):"
# fzf.zsh exports the cycle binding; fzf_down() must NOT also bind ctrl-/
# (that would either duplicate, or — if we ever swapped one for the other —
# create a divergence between dispatcher widgets and built-in widgets).
fzf_zsh="${0:a:h}/../fzf.zsh"
fns="${0:a:h}/functions.sh"
assert "fzf.zsh: ctrl-/ binds change-preview-window" \
  "ctrl-/:change-preview-window" "$(grep -h ctrl-/ "$fzf_zsh")"
assert "fzf.zsh: cycle includes vertical (down,50%)" \
  "down,50%" "$(grep -h ctrl-/ "$fzf_zsh")"
assert "fzf.zsh: cycle includes hidden state" \
  "hidden" "$(grep -h ctrl-/ "$fzf_zsh")"
assert_not "functions.sh: no toggle-preview (replaced by cycle)" \
  "ctrl-/:toggle-preview" "$(cat "$fns")"
assert_not "functions.sh: no redundant ctrl-/ binding" \
  "ctrl-/:" "$(cat "$fns")"

echo
echo "$pass passed, $fail failed"
(( fail == 0 ))
