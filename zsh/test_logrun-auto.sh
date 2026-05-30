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

# Compound buffers route to `function` (logrun --auto -c) so the inner
# zsh parses the whole script body, including operators.
_check "classify: pipeline"                  "function"   "$(_classify 'ls | wc -l')"
_check "classify: sequence"                  "function"   "$(_classify 'ls; sleep 12; ls')"
_check "classify: AND-chain"                 "function"   "$(_classify 'make && ./run')"
_check "classify: OR-chain"                  "function"   "$(_classify 'make || echo failed')"
_check "classify: redirect"                  "function"   "$(_classify 'ls > /tmp/out')"
_check "classify: command substitution"      "function"   "$(_classify 'echo $(date)')"
_check "classify: backtick substitution"     "function"   "$(_classify 'echo \`date\`')"
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

# Self-referential alias (`ls='ls --color=auto'`) used to expand 8 times
# until the hop cap kicked in, repeating the flags. Must terminate at
# fixed point and inject the flags exactly once.
alias ls_self='ls_self --group-directories-first --color=auto'
_check "rewrite: self-referential alias once" \
    "logrun --auto --no-zshrc -- ls_self --group-directories-first --color=auto a*" \
    "$(_rewrite 'ls_self a*')"
unalias ls_self

# Compound buffer wraps via `-c` (the inner shell handles operators).
_check "rewrite: pipeline via -c"   "logrun --auto -c 'ls | wc -l'"           "$(_rewrite 'ls | wc -l')"
_check "rewrite: sequence via -c"   "logrun --auto -c 'ls; sleep 1; ls'"      "$(_rewrite 'ls; sleep 1; ls')"
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

# ---- end-to-end: widget rewrite + actually invoke the resulting logrun ----
# These cases run the rewritten BUFFER in the same shell and observe the
# real side effects (log file presence, banner, exit code). Locks down
# the integration between the widget and bin/logrun.

# Make sure logrun is on PATH for the eval calls below.
PATH="$DOTFILES/bin:$PATH"

_e2e_run() {
    # $1 = BUFFER to rewrite-and-run; remaining args are env vars to set.
    local input=$1; shift
    BUFFER="$input"
    _logrun_auto_accept_line
    local cmd="$BUFFER"
    eval "$@ $cmd" 2>&1
    return $?
}

# E2E #1: short external — invisible (no banner, no log left)
TMP=$(mktemp -d /tmp/test_logrun-auto.XXXXXX)
out=$(_e2e_run "echo hello-world" "build_dir=$TMP")
_check "e2e/short: stdout"          "hello-world"  "$out"
# (N) is zsh's per-glob NULL_GLOB qualifier — empty match expands to nothing
# instead of erroring. Cheaper and safer than `ls | wc -l`.
files=("$TMP"/*(N))
_check "e2e/short: no log retained" "0"            "${#files[@]}"
rm -rf "$TMP"

# E2E #2: line-threshold reveal — banner once, log retained
TMP=$(mktemp -d /tmp/test_logrun-auto.XXXXXX)
out=$(_e2e_run "seq 1 6" "build_dir=$TMP" "LOGRUN_AUTO_LINES=3")
banner=$(printf '%s\n' "$out" | grep -c '^Log: '; true)
_check "e2e/lines: 1 banner"        "1" "$banner"
logs=("$TMP"/log-*(N))
_check "e2e/lines: log retained"    "1" "${#logs[@]}"
rm -rf "$TMP"

# E2E #3: failing external — non-zero exit yields FAILED.txt + banner.
# Uses /usr/bin/env bash to run an external (zsh's `false` is a builtin
# so the widget would skip it; we want to exercise the failure branch
# of logrun --auto, which only runs for wrapped commands).
TMP=$(mktemp -d /tmp/test_logrun-auto.XXXXXX)
out=$(_e2e_run "/usr/bin/env bash -c 'exit 7'" "build_dir=$TMP")
rc=$?
_check "e2e/fail: rc preserved"     "7" "$rc"
failed=("$TMP"/*FAILED.txt(N))
_check "e2e/fail: FAILED file"      "1" "${#failed[@]}"
banner=$(printf '%s\n' "$out" | grep -c '^Log: '; true)
_check "e2e/fail: 1 banner"         "1" "$banner"
rm -rf "$TMP"

# E2E #4: builtin `false` is correctly skipped (NOT wrapped). Confirms
# the widget doesn't accidentally try to run builtins through logrun
# (which would lose builtin-only semantics like `cd`).
BUFFER="false"
_logrun_auto_accept_line
_check "e2e/builtin: not rewritten" "false" "$BUFFER"

# E2E #5: alias -> external still routes to fast path (`--no-zshrc`).
alias gst='git status'
TMP=$(mktemp -d /tmp/test_logrun-auto.XXXXXX)
BUFFER="gst"
_logrun_auto_accept_line
[[ "$BUFFER" == "logrun --auto --no-zshrc -- git status" ]] && ok=1 || ok=0
_check "e2e/alias: --no-zshrc form" "1" "$ok"
unalias gst
rm -rf "$TMP"

# E2E #6: NOLOG=1 prefix means the buffer is not rewritten.
BUFFER="NOLOG=1 echo unwrapped"
_logrun_auto_accept_line
_check "e2e/nolog: passthrough"     "NOLOG=1 echo unwrapped" "$BUFFER"

echo
echo "PASS: $PASS  FAIL: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
ZSH
