# zz-logrun-auto.zsh — automatically wrap interactive prompt commands in
# `logrun --auto` so long-running or chatty commands get a log file
# (visible only when threshold is crossed) while short commands run as if
# bare. The "zz-" prefix makes this file load last in the alphabetical
# zsh glob, so our `accept-line` override sits OUTSIDE the wrappers
# installed by zsh-syntax-highlighting / zsh-autosuggestions.
#
# See AGENTS.md "automatically use logrun" TODO for full requirements.

# Re-source guard: our widget would call itself if installed twice.
(( ${+functions[_logrun_auto_accept_line]} )) && return 0

# ----------------------------------------------------------------- config

# TUI skiplist: UI tools whose terminal handling breaks under any
# stdout pipe. Defined canonically in home-manager (see
# home-manager.configsymlink/home.nix sessionVariables) so the list
# tracks what's actually installed on this machine. The fallback below
# only runs when home-manager hasn't been activated yet (fresh clone)
# and lists the system-default TUIs every base distro ships with.
if [[ -z "${LOGRUN_TUI_SKIPLIST-}" ]]; then
    export LOGRUN_TUI_SKIPLIST="less more ssh man top nano watch"
fi

# Functions opt-in for wrapping. Default empty — most user functions
# (l, c, p, o, jj wrappers, git helpers) are short. Long-running
# wrappers like j/n/jr/nijr/sync-* should be added by the user.
typeset -ga LOGRUN_AUTO_FUNCTIONS=( "${LOGRUN_AUTO_FUNCTIONS[@]:-}" )

# Per-shell session memo: warned about which functions for the
# bidirectional auto-suggestion ("add to / remove from list"). Prevents
# spamming the same hint every prompt.
typeset -gA _logrun_warned

# ----------------------------------------------------------------- helpers

# Strip a leading `NAME=value` env-prefix run from a command string.
# Returns the residual command string (or the input unchanged).
_logrun_strip_env_prefix() {
    local s="$1"
    while [[ "$s" == [a-zA-Z_][a-zA-Z0-9_]*=* ]]; do
        # Drop one VAR=VALUE token. Quoted values complicate this; for
        # the common case of NOLOG=1 / FOO=bar we just split on the
        # first whitespace.
        s="${s#* }"
    done
    print -r -- "$s"
}

# Walk one level of alias expansion. Returns 0 if expansion happened
# (and rewrites BUFFER to the expansion); 1 otherwise. Bounded by the
# caller via a hop counter.
_logrun_expand_alias() {
    local buf="${BUFFER-}"
    # Split on first run of whitespace; handles spaces and tabs.
    local first="${buf%%[[:space:]]*}"
    local rest=""
    if [[ "$buf" = *[[:space:]]* ]]; then
        rest="${buf#*[[:space:]]}"
    fi
    local expansion="${aliases[$first]-}"
    [[ -z "$expansion" ]] && return 1
    if [[ -n "$rest" ]]; then
        BUFFER="${expansion} ${rest}"
    else
        BUFFER="${expansion}"
    fi
    return 0
}

# Decide what to do with the current $BUFFER. Sets `_logrun_decision`
# to one of: skip / external / function. Sets `_logrun_first` to the
# resolved first word.
_logrun_classify() {
    _logrun_decision="skip"
    _logrun_first=""

    local buf="${BUFFER-}"
    # Empty/whitespace-only buffer → let zsh handle it.
    [[ -z "${buf//[[:space:]]/}" ]] && return

    # NOLOG=1 ... → opt-out.
    if [[ "$buf" == NOLOG=* ]] || [[ "$buf" == *' NOLOG='* ]]; then
        return
    fi

    # First word, post-alias-expansion (capped at 8 hops to stop runaway
    # mutual aliases).
    local hops=0
    while (( hops < 8 )) && _logrun_expand_alias; do
        (( hops++ ))
    done

    local first="${BUFFER%%[[:space:]]*}"
    [[ -z "$first" ]] && return
    _logrun_first="$first"

    # Reentrancy / explicit logrun call → never wrap again.
    [[ "$first" == "logrun" ]] && return
    [[ -n "${LOGRUN_PID-}" ]] && return

    # TUI skiplist match.
    local tui
    for tui in ${=LOGRUN_TUI_SKIPLIST}; do
        [[ "$first" == "$tui" ]] && return
    done

    # whence -w: tells us if it's a builtin / reserved / function /
    # command / alias. We want to skip builtins, reserved words (for,
    # while, if, ...) and `cd` (which is a builtin but also commonly
    # overridden as a function — either way wrapping it would fork a
    # subshell and lose the cwd change).
    local kind
    kind="${$(whence -w -- "$first" 2>/dev/null)##*: }"
    case "$kind" in
        builtin|reserved|none|"") return ;;
        function)
            # Opt-in only for functions in LOGRUN_AUTO_FUNCTIONS.
            local fn
            for fn in "${LOGRUN_AUTO_FUNCTIONS[@]}"; do
                [[ "$first" == "$fn" ]] && { _logrun_decision="function"; return ; }
            done
            return
            ;;
        command|alias)
            # Resolved external (or alias-to-external after expansion).
            _logrun_decision="external"
            return
            ;;
    esac
}

# ----------------------------------------------------------------- widget

# Save original buffer so we can restore it for history before zsh
# parses the rewritten one (zshaddhistory hook).
typeset -g _logrun_orig_buffer=""

_logrun_auto_accept_line() {
    _logrun_orig_buffer="$BUFFER"
    local _logrun_decision _logrun_first
    _logrun_classify

    case "$_logrun_decision" in
        external)
            # Externals: the widget already pre-expanded any aliases, so
            # $BUFFER is now a plain "binary arg arg ..." line. Use the
            # fast path (`--no-zshrc`) to avoid 800ms of zshrc replay.
            BUFFER="logrun --auto --no-zshrc -- ${BUFFER}"
            ;;
        function)
            # Functions need zsh -ic (or eval inside the widget) so that
            # user functions resolve. Use logrun -c with the original
            # buffer.
            local q
            q="${(q)_logrun_orig_buffer}"
            BUFFER="logrun --auto -c ${q}"
            ;;
        skip|*) ;;
    esac

    zle .accept-line
}

# History hook: restore the user-typed buffer so ↑ recalls the original,
# not "logrun --auto …".
_logrun_auto_zshaddhistory() {
    if [[ -n "$_logrun_orig_buffer" ]]; then
        # The arg is the line zsh would record. Replace it.
        print -sr -- "$_logrun_orig_buffer"
        _logrun_orig_buffer=""
        return 1   # tell zsh: skip default history append (we did it).
    fi
    return 0
}

# ----------------------------------------------------------------- install
# Only wire the widget / history hook into an interactive zle session.
# Function definitions above are unconditional so non-interactive
# sourcing (tests, sub-shells) can exercise the classifier.
if [[ -o interactive ]]; then
    zle -N accept-line _logrun_auto_accept_line

    autoload -Uz add-zsh-hook
    add-zsh-hook -d zshaddhistory _logrun_auto_zshaddhistory 2>/dev/null
    add-zsh-hook zshaddhistory _logrun_auto_zshaddhistory
fi
