#!/usr/bin/env bash
# test_logrun-auto.sh — exercise zz-logrun-auto.zsh classifier and
# accept-line rewrite logic. Runs zsh in a subshell to source the widget
# in a clean state.
#
# Run with:  bash zsh/test_logrun-auto.sh

set -u

DOTFILES_ROOT=$(cd "$(dirname "$0")/.." && pwd)
WIDGET="$DOTFILES_ROOT/zsh/zz-logrun-auto.zsh"

if ! command -v zsh >/dev/null 2>&1; then
    echo "SKIP: zsh not installed" >&2
    exit 0
fi

# Drive the widget tests with a self-contained zsh script. We pass the
# widget path via env var (bash heredoc would interpolate $0 as bash).
WIDGET_PATH="$WIDGET" zsh -f <<'ZSH'
emulate -L zsh
source "$WIDGET_PATH" || { echo "FAIL: widget did not load"; exit 1 }

PASS=0; FAIL=0
_check() {
    local label=$1 expected=$2 actual=$3
    if [[ "$expected" == "$actual" ]]; then
        printf 'PASS: %s\n' "$label"; (( PASS++ ))
    else
        printf 'FAIL: %s\n  expected: [%s]\n  actual:   [%s]\n' \
            "$label" "$expected" "$actual"
        (( FAIL++ ))
    fi
}

# Mock zle so the widget can run outside a real zle context.
zle() { return 0 }

alias gst='git status'
gco() { :; }
my_long_func() { :; }
LOGRUN_AUTO_FUNCTIONS=(my_long_func)

# ---- classify: decision matrix ----
_classify() {
    BUFFER="$1"
    local _logrun_decision _logrun_first
    _logrun_classify
    print -r -- "$_logrun_decision"
}
_check "classify: external/ls"               "external"   "$(_classify 'ls -la')"
_check "classify: external/git"              "external"   "$(_classify 'git status')"
_check "classify: alias->external"           "external"   "$(_classify 'gst')"
_check "classify: function NOT in list"      "skip"       "$(_classify 'gco main')"
_check "classify: function IN list"          "function"   "$(_classify 'my_long_func')"
_check "classify: builtin cd"                "skip"       "$(_classify 'cd /tmp')"
_check "classify: builtin export"            "skip"       "$(_classify 'export FOO=bar')"
_check "classify: reserved for"              "skip"       "$(_classify 'for i in 1 2; do echo $i; done')"
# TUIs in the default skiplist (system-default fallback when nix isn't
# active: "less more ssh man top nano watch"). The home-manager-managed
# list at home-manager.configsymlink/home.nix is the source of truth on
# real shells; tests use the fallback so they don't depend on flake state.
_check "classify: TUI less"                  "skip"       "$(_classify 'less foo.txt')"
_check "classify: TUI ssh"                   "skip"       "$(_classify 'ssh host')"
_check "classify: TUI man"                   "skip"       "$(_classify 'man bash')"
_check "classify: logrun re-entry"           "skip"       "$(_classify 'logrun ls')"
_check "classify: NOLOG opt-out"             "skip"       "$(_classify 'NOLOG=1 sleep 30')"
_check "classify: empty buffer"              "skip"       "$(_classify '')"
_check "classify: whitespace buffer"         "skip"       "$(_classify '   ')"
_check "classify: unknown command"           "skip"       "$(_classify 'this-cmd-does-not-exist')"

# ---- accept-line rewrite ----
_rewrite() {
    BUFFER="$1"
    _logrun_auto_accept_line
    print -r -- "$BUFFER"
}
_check "rewrite: external"          "logrun --auto --no-zshrc -- ls -la"      "$(_rewrite 'ls -la')"
_check "rewrite: alias->external"   "logrun --auto --no-zshrc -- git status"  "$(_rewrite 'gst')"
_check "rewrite: function in list"  "logrun --auto -c my_long_func"           "$(_rewrite 'my_long_func')"
_check "rewrite: function not list" "gco main"                                "$(_rewrite 'gco main')"
_check "rewrite: TUI"               "less foo.txt"                            "$(_rewrite 'less foo.txt')"
_check "rewrite: builtin"           "cd /tmp"                                 "$(_rewrite 'cd /tmp')"
_check "rewrite: NOLOG"             "NOLOG=1 sleep 30"                        "$(_rewrite 'NOLOG=1 sleep 30')"

# ---- history hook captures original ----
BUFFER="ls -la"
_logrun_auto_accept_line
_check "history: orig captured"     "ls -la"                                  "$_logrun_orig_buffer"

# zshaddhistory hook resets the orig buffer to "" after consuming it.
_logrun_auto_zshaddhistory "ignored"
_check "history: orig cleared after hook"   ""                                "$_logrun_orig_buffer"

echo
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
ZSH
