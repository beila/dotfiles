#!/usr/bin/env bash
# test_fzf_widgets.sh — verify the override of fzf's __fzfcmd routes the
# built-in zsh widgets (Ctrl-T / Alt-C / Ctrl-R) through fzf-zellij.
#
# This is a non-interactive smoke test. The widgets themselves are zle
# functions and can't be invoked headlessly, but we can:
#   1. Verify __fzfcmd is overridden after fzf.zsh sources.
#   2. Verify it returns the absolute path to fzf-zellij.
#   3. Verify fzf-zellij itself falls back to plain fzf when ZELLIJ is unset.

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZSH_BIN=$(command -v zsh)

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n  %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

# Run code in a fresh non-interactive zsh that sources our zshrc. Strips
# ANSI colour codes (gitstatus error etc.) and noise lines that don't
# affect functionality but contaminate stdout in non-tty zsh.
zsh_eval() {
    local script="$1"
    env -i HOME="$HOME" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
        DOTFILES_ROOT="$DOTFILES_ROOT" \
        "$ZSH_BIN" -i -c "set +e; $script" 2>&1 \
      | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
      | grep -vE "can't change option:|gitstatus failed|Add the |GITSTATUS|Restart Zsh|exec zsh|^ *\$"
}

echo "=== Test 1: __fzfcmd is defined as a function ==="
out=$(zsh_eval 'whence -w __fzfcmd 2>/dev/null')
if printf '%s' "$out" | grep -q "function"; then
    pass "__fzfcmd is a function"
else
    fail "__fzfcmd not registered as function" "got: $out"
fi

echo
echo "=== Test 2a: __fzfcmd returns fzf-zellij when inside zellij ==="
out=$(zsh_eval 'ZELLIJ=fake-id; unset FZF_ZELLIJ; __fzfcmd')
expected="$DOTFILES_ROOT/fzf/fzf-zellij"
if [ "$out" = "$expected" ]; then
    pass "__fzfcmd → $out (ZELLIJ set, FZF_ZELLIJ unset)"
else
    fail "__fzfcmd in zellij returned wrong path" "expected [$expected], got [$out]"
fi

echo
echo "=== Test 2b: __fzfcmd returns plain fzf when ZELLIJ unset ==="
out=$(zsh_eval 'unset ZELLIJ FZF_ZELLIJ; __fzfcmd')
if [ "$out" = "fzf" ]; then
    pass "__fzfcmd → fzf (outside zellij)"
else
    fail "__fzfcmd outside zellij returned wrong" "expected [fzf], got [$out]"
fi

echo
echo "=== Test 2c: __fzfcmd returns plain fzf when nested (FZF_ZELLIJ=1) ==="
out=$(zsh_eval 'ZELLIJ=fake-id; FZF_ZELLIJ=1; __fzfcmd')
if [ "$out" = "fzf" ]; then
    pass "__fzfcmd → fzf (nested via FZF_ZELLIJ=1)"
else
    fail "__fzfcmd nested returned wrong" "expected [fzf], got [$out]"
fi

echo
echo "=== Test 3: fzf-zellij path resolves to an executable file ==="
fzf_zellij="$DOTFILES_ROOT/fzf/fzf-zellij"
if [ -x "$fzf_zellij" ]; then
    pass "executable at $fzf_zellij"
else
    fail "not executable" "expected $fzf_zellij to be -x"
fi

echo
echo "=== Test 4: fzf-zellij falls back to plain fzf when ZELLIJ unset ==="
# Probe the fallback branch: outside zellij the script should exec plain
# fzf. We pipe an empty list and pass --filter so fzf exits without a tty,
# then check the script returns 0 (no candidates filtered to anything).
# Real fzf returns 1 when no match; that's success for our purposes since
# it shows the binary itself ran rather than zellij hanging.
# Use a tiny input + filter to confirm the full pipeline works.
out=$(env -u ZELLIJ "$fzf_zellij" --filter=needle <<< $'haystack\nneedlehay' 2>&1)
if [ "$out" = "needlehay" ]; then
    pass "fzf-zellij --filter works outside zellij"
else
    fail "fzf-zellij fallback didn't filter correctly" "got: $out"
fi

echo
echo "=== Test 5: fzf-zellij also passes through when FZF_ZELLIJ=1 (nested) ==="
out=$(FZF_ZELLIJ=1 ZELLIJ=fake-id "$fzf_zellij" --filter=foo <<< $'foo\nbar\nfoofoo' 2>&1)
expected=$'foo\nfoofoo'
if [ "$out" = "$expected" ]; then
    pass "fzf-zellij passes through with FZF_ZELLIJ=1"
else
    fail "FZF_ZELLIJ=1 nested fallback broken" "got: $out"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
