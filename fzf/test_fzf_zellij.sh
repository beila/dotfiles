#!/usr/bin/env bash
# test_fzf_zellij.sh — requires running inside a zellij session
# Run: bash ~/.dotfiles/fzf/test_fzf_zellij.sh
set -uo pipefail

FZF_ZELLIJ="$(dirname "$0")/fzf-zellij"
pass=0; fail=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    echo "  ✓ $desc"
    ((pass++))
  else
    echo "  ✗ $desc: expected='$expected' actual='$actual'"
    ((fail++))
  fi
}

pane_ids() { zellij action list-panes 2>/dev/null | awk 'NR>1{print $1}'; }

cleanup() {
  local before="$1" leftover=0
  for p in $(pane_ids); do
    if ! echo "$before" | grep -qx "$p"; then
      ((leftover++))
      zellij action close-pane --pane-id "$p" 2>/dev/null || true
    fi
  done
  echo "$leftover"
}

before=$(pane_ids)

echo "basic:"
out=$(timeout 5 bash -c 'echo -e "apple\nbanana\ncherry" | '"$FZF_ZELLIJ"' -- --filter banana' 2>/dev/null)
check "piped input + filter returns match" "banana" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo "fallback:"
out=$(ZELLIJ= timeout 5 bash -c 'echo -e "one\ntwo" | '"$FZF_ZELLIJ"' -- --filter two' 2>/dev/null)
check "fallback when ZELLIJ unset" "two" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo "pipeline:"
out=$(timeout 5 bash -c 'echo -e "◆  abc 1h some description\n○  xyz 2h another" |
  '"$FZF_ZELLIJ"' -- --ansi --no-sort --reverse --filter "abc" |
  sed "s/\x1b\[[0-9;]*m//g" | grep -o "^[^a-z(]*[a-z]\{1,\}" | grep -o "[a-z]\{1,\}$" | head -1' 2>/dev/null)
check "pipeline extracts id" "abc" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo "nested:"
out=$(FZF_ZELLIJ=1 timeout 5 bash -c 'echo -e "apple\nbanana" | '"$FZF_ZELLIJ"' -- --filter apple' 2>/dev/null)
check "FZF_ZELLIJ=1 skips floating pane" "apple" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

out=$(FZF_ZELLIJ=1 timeout 5 bash -c 'echo -e "◆  abc 1h desc\n○  xyz 2h other" |
  '"$FZF_ZELLIJ"' -- --ansi --no-sort --reverse --filter "xyz" |
  sed "s/\x1b\[[0-9;]*m//g" | grep -o "^[^a-z(]*[a-z]\{1,\}" | grep -o "[a-z]\{1,\}$" | head -1' 2>/dev/null)
check "nested pipeline extracts id" "xyz" "$out"
check "no leftover panes" "0" "$(cleanup "$before")"

echo ""
echo "$((pass+fail)) tests: $pass passed, $fail failed"
exit "$fail"
