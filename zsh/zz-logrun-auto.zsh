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
# stdout pipe. Two layers, merged at classification time:
#
#   $LOGRUN_TUI_SKIPLIST          machine-default, set in
#                                 home-manager.configsymlink/home.nix
#                                 (tracks what's installed via nix).
#   $LOGRUN_TUI_SKIPLIST_FILE     user delta, default
#                                 ~/.dotfiles/bin/logrun-tui-skiplist
#                                 — committed to the dotfiles repo with
#                                 .gitattributes `merge=union` so
#                                 cross-machine appends auto-merge.
#                                 logrun --auto auto-appends to it; the
#                                 widget reads it via _logrun_user_skiplist
#                                 (mtime-cached so no per-prompt I/O).
#
# Fallback below seeds $LOGRUN_TUI_SKIPLIST with the universal-distro TUIs
# when home-manager hasn't been activated yet (fresh clone).
if [[ -z "${LOGRUN_TUI_SKIPLIST-}" ]]; then
    export LOGRUN_TUI_SKIPLIST="less more ssh man top nano watch"
fi

# zstat from zsh/stat: mtime probe without forking. Falls through to
# stat(1) below when zstat isn't loadable.
zmodload -F zsh/stat b:zstat 2>/dev/null

# Memoised reader for the user-skiplist file. Cache key: file mtime.
typeset -g _logrun_user_skiplist_cache=""
typeset -g _logrun_user_skiplist_mtime=""
_logrun_user_skiplist() {
    local f="${LOGRUN_TUI_SKIPLIST_FILE:-$HOME/.dotfiles/bin/logrun-tui-skiplist}"
    if [[ ! -f "$f" ]]; then
        _logrun_user_skiplist_cache=""
        _logrun_user_skiplist_mtime=""
        print -r -- ""
        return
    fi
    local mt
    mt=$(zstat +mtime "$f" 2>/dev/null) || mt=$(stat -c %Y "$f" 2>/dev/null)
    if [[ "$mt" == "$_logrun_user_skiplist_mtime" ]]; then
        print -r -- "$_logrun_user_skiplist_cache"
        return
    fi
    _logrun_user_skiplist_mtime="$mt"
    _logrun_user_skiplist_cache=$(grep -v '^#' "$f" 2>/dev/null | tr '\n' ' ')
    print -r -- "$_logrun_user_skiplist_cache"
}

# Functions opt-in for wrapping. Pre-populated with the wrapper-style
# functions in zsh/functions/ that shell out to long-running tools (nix
# develop chains, rsync, docker run); short utility functions (l, c, p,
# o, jj wrappers, git helpers) are intentionally absent so they stay
# fast. Append to this list (don't overwrite) from private-dotfiles to
# add machine- or work-specific entries:
#     LOGRUN_AUTO_FUNCTIONS+=( my_long_func )
typeset -ga LOGRUN_AUTO_FUNCTIONS
LOGRUN_AUTO_FUNCTIONS=(
    j n ji ni jr njr nijr
    sync-rsync sync-ssh
    docker_here docker_here_t docker_here_with_t
    "${LOGRUN_AUTO_FUNCTIONS[@]:-}"
)

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
# caller via a hop counter and by an "already-expanded" tracker that
# matches zsh's own no-loop semantics.
#
# Self-referential aliases (e.g. `ls='ls --color=auto'`) must substitute
# exactly once — so the flags get injected — and then stop. Without the
# tracker, we'd re-expand `ls` on every iteration and accumulate
# `--color=auto` 8 times.
typeset -gA _logrun_alias_seen
_logrun_expand_alias() {
    local buf="${BUFFER-}"
    local first="${buf%%[[:space:]]*}"
    [[ -n "${_logrun_alias_seen[$first]-}" ]] && return 1
    local expansion="${aliases[$first]-}"
    [[ -z "$expansion" ]] && return 1
    _logrun_alias_seen[$first]=1
    local rest=""
    if [[ "$buf" = *[[:space:]]* ]]; then
        rest="${buf#*[[:space:]]}"
    fi
    if [[ -n "$rest" ]]; then
        BUFFER="${expansion} ${rest}"
    else
        BUFFER="${expansion}"
    fi
    return 0
}

# Scan a buffer for shell metacharacters that are NOT inside single or
# double quotes and NOT preceded by a backslash. Used to decide whether
# to route the whole buffer through `logrun --auto -c` (real shell
# parser) rather than treating it as a simple `cmd args...` invocation.
#
# Tracked metachars: ; | & < > ` newline, plus the digraph "$(".
# We don't try to be a full lexer — we only need to distinguish "the
# user typed a real shell operator" from "they typed `bat 'foo;bar'`".
_logrun_has_unquoted_metachar() {
    # Don't combine these into one `local` statement: zsh evaluates
    # right-hand-sides left-to-right but the parameter substitution
    # `${#s}` reads the OLD value of $s (before this `local`'s
    # assignment to s takes effect), giving 0. Splitting the assignment
    # makes len reflect the just-set s.
    local s="$1"
    local i=1 ch state="" len=${#s}
    while (( i <= len )); do
        ch="${s[i]}"
        case "$state" in
            "")
                case "$ch" in
                    \\) (( i += 2 )); continue ;;       # escaped char — skip pair
                    \') state=sq ;;
                    \") state=dq ;;
                    ';'|'|'|'&'|'<'|'>'|'`'|$'\n') return 0 ;;
                    '$')
                        # "$(" is command substitution; "$x", "$1", etc. are not.
                        (( i + 1 <= len )) && [[ "${s[i+1]}" == '(' ]] && return 0
                        ;;
                esac
                ;;
            sq) [[ "$ch" == \' ]] && state="" ;;
            dq)
                case "$ch" in
                    \\) (( i += 2 )); continue ;;
                    \") state="" ;;
                esac
                ;;
        esac
        (( i++ ))
    done
    return 1
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

    # Compound commands (pipelines, &&/||, redirects, command-substitution,
    # sequences, multi-line) can't be classified by their first word and
    # must run through a real shell parser. Route the whole buffer
    # through `logrun --auto -c` (slow path: zsh -ic) so every shell
    # operator works exactly as the user typed it. Skip alias
    # pre-expansion in this case — the inner shell does its own.
    if _logrun_has_unquoted_metachar "$buf"; then
        _logrun_decision="function"
        _logrun_first="${buf%%[[:space:]]*}"
        return
    fi

    # First word, post-alias-expansion. The hop cap is a safety net; the
    # real termination comes from _logrun_alias_seen (one substitution
    # per alias name, mirroring zsh's own no-loop behavior).
    _logrun_alias_seen=()
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

    # TUI skiplist match — env-var (machine default) ∪ user file (auto-managed).
    local tui
    for tui in ${=LOGRUN_TUI_SKIPLIST} ${=$(_logrun_user_skiplist)}; do
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
