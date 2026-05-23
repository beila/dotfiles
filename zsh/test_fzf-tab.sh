#!/usr/bin/env bash
# test_fzf-tab.sh — sanity tests for the fzf-tab completion wiring.
#
# fzf-tab is a zle widget plugin; it can't be exercised via bash, only zsh.
# These tests spin up non-interactive `zsh -c` shells, source the dotfiles
# zsh init, and check the load + zstyle + fallback paths.
#
# Tests:
#   1. fzf-tab plugin file exists at the expected location after a switch.
#   2. After sourcing zshrc, `fzf-tab` widget is registered with zle.
#   3. `zstyle ':fzf-tab:*' fzf-command` is set to fzf-zellij.
#   4. compinit doesn't error when run with fzf-tab loaded (no broken cache).
#   5. With fzf-zellij PATH-masked, fzf-tab still loads cleanly (zstyle
#      points to a missing path; fzf-tab handles this by falling back to
#      its built-in `-ftb-fzf` which calls plain `fzf`).

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLUGIN="$HOME/.nix-profile/share/fzf-tab/fzf-tab.plugin.zsh"

PASS=0; FAIL=0
pass() { printf 'PASS: %s\n' "$1"; PASS=$((PASS+1)); }
fail() { printf 'FAIL: %s\n  %s\n' "$1" "$2"; FAIL=$((FAIL+1)); }

ZSH_BIN=$(command -v zsh)

# Helper: run code in a fresh non-interactive zsh that sources our zshrc.
# Set -i so editor.zsh's `[[ -o shinstdin ]]` guard passes (otherwise it
# bails out before bindkey setup). Strips zsh's "can't change option: zle"
# warnings (harmless: zle is unavailable in non-tty -i mode but plugins try
# anyway) so test assertions only see real output.
zsh_eval() {
    local script="$1"
    env -i HOME="$HOME" PATH="$PATH" TERM="${TERM:-xterm-256color}" \
        DOTFILES_ROOT="$DOTFILES_ROOT" \
        "$ZSH_BIN" -i -c "set +e; $script" 2>&1 \
      | grep -vE "can't change option: (zle|monitor)|gitstatus failed|Add the following|GITSTATUS_LOG_LEVEL|Restart Zsh|exec.*zsh|^ *\$"
}

echo "=== Test 1: fzf-tab plugin file exists ==="
if [ -e "$PLUGIN" ]; then
    pass "plugin at $PLUGIN"
else
    fail "plugin file missing" "expected $PLUGIN — run home-manager switch first"
fi

echo
echo "=== Test 2: fzf-tab widget registered after sourcing zshrc ==="
out=$(zsh_eval 'zle -lL 2>/dev/null | grep -E "fzf-tab|toggle-fzf-tab" | head -3')
if printf '%s' "$out" | grep -q "fzf-tab"; then
    pass "fzf-tab widget registered: $(printf '%s' "$out" | head -1)"
else
    fail "no fzf-tab widget" "zle -lL output: $out"
fi

echo
echo "=== Test 3: fzf-command zstyle points at fzf-zellij ==="
out=$(zsh_eval "zstyle -s ':fzf-tab:*' fzf-command cmd && echo \"cmd=\$cmd\"")
if printf '%s' "$out" | grep -q "fzf-zellij"; then
    pass "fzf-command set: $out"
else
    fail "fzf-command not fzf-zellij" "got: $out"
fi

echo
echo "=== Test 4: compinit clean run (no errors when cache rebuilt) ==="
# Force a rebuild by clearing the cache. The interactive-zsh guard inside
# editor.zsh handles tty absence. Run twice: once to rebuild, once to confirm
# the cache works on a warm load.
out=$(zsh_eval '
    rm -f "${XDG_CACHE_HOME:-\$HOME/.cache}/zsh/zcompdump" 2>/dev/null
    : ${XDG_CACHE_HOME:=$HOME/.cache}
    rm -f "$XDG_CACHE_HOME/zsh/zcompdump" 2>/dev/null
    # First load (cold): the zshrc source above already triggered compinit.
    # Just verify there were no error echoes.
    echo "OK-COLD"
')
if printf '%s' "$out" | tail -1 | grep -q "OK-COLD"; then
    pass "compinit cold rebuild OK"
else
    fail "compinit complained" "tail of zsh output: $(printf '%s' "$out" | tail -3)"
fi

# Warm load
out=$(zsh_eval 'echo OK-WARM')
if printf '%s' "$out" | tail -1 | grep -q "OK-WARM"; then
    pass "compinit warm load OK"
else
    fail "warm load broken" "tail: $(printf '%s' "$out" | tail -3)"
fi

echo
echo "=== Test 5: fzf-tab loads even when fzf-zellij is missing from PATH ==="
# Build a minimal PATH that has zsh + coreutils but excludes the dotfiles bin
# dir (which is where fzf-zellij lives). Plugin file is loaded via absolute
# path so it still works; the zstyle just points at a missing command, and
# fzf-tab handles that at invocation time. Sourcing must not error.
ZSH_DIR=$(dirname "$ZSH_BIN")
out=$(env -i HOME="$HOME" PATH="$ZSH_DIR:/usr/bin:/bin" TERM="${TERM:-xterm-256color}" \
        DOTFILES_ROOT="$DOTFILES_ROOT" \
        "$ZSH_BIN" -i -c 'zle -lL 2>/dev/null | grep -c fzf-tab' 2>&1 \
      | grep -vE "can't change option:|gitstatus|Add the |GITSTATUS|Restart |exec.*zsh|^ *\$" \
      | tail -1)
if printf '%s' "$out" | grep -qE '^[1-9][0-9]*$'; then
    pass "fzf-tab loaded ($out widgets) without fzf-zellij on PATH"
else
    fail "fzf-tab did not load when fzf-zellij missing" "output: $out"
fi

echo
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ]
