# ctrl-/: cycle preview layouts. Pipe-separated states rotate; empty entry
# reverts to the original (--preview-window or fzf default). Sequence:
#   horizontal (initial) → vertical (down,50%) → hidden → horizontal → ...
# Lives in FZF_DEFAULT_OPTS so the binding is shared by:
#   - dispatcher widgets via fzf_down() (_jh, _jb, _gf, ...)
#   - built-in widgets via fzf-zellij (Ctrl-T, Alt-C, Ctrl-R, Ctrl-E)
#   - any other plain fzf invocation
# Keeping it here (single source of truth) means callers' own
# --preview-window settings (e.g. right:70% in _jb) survive the cycle —
# the empty rotation entry restores whatever each caller originally set.
export FZF_DEFAULT_OPTS='--bind "ctrl-n:preview-half-page-down" --bind "ctrl-p:preview-half-page-up" --bind "ctrl-/:change-preview-window(down,50%|hidden|)"'

# TODO fasd used to have files listed, but zoxide does not. I need list of files most likely to be used. Maybe locate?
# Emit plain paths (NUL-separated for safety with weird filenames), one
# per line for fzf. Earlier version piped through `xargs ls --color=always
# -d` which prefixed each row with `ls -l`-style metadata; that left the
# floating-pane list column showing only perms+date and clipping names.
export FZF_CTRL_T_COMMAND='
    {
        git ls-files --cached 2>/dev/null
        git ls-files --others 2>/dev/null
        if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
            fd --hidden --follow --strip-cwd-prefix 2>/dev/null
        fi
    } | awk "!d[\$0]++"'

# Preview: bat for files, eza/ls -1 -F for directories. Names-first so the
# narrow preview pane doesn't truncate them. Single-line: fzf-zellij
# forwards the preview string into a bash subshell, and zsh's outer quote
# layer eats `\<newline>` continuations before they reach fzf — keep
# everything on one line with `;` and `||` separators.
export FZF_CTRL_T_OPTS='--preview "if [ -d {} ]; then command -v eza >/dev/null 2>&1 && eza --color=always --icons=auto -1 -F --group-directories-first {} || ls -1 -F --color=always {}; elif [ -f {} ]; then bat --style=numbers --color=always --line-range :500 {} 2>/dev/null || cat {} 2>/dev/null || file {}; fi 2>/dev/null"'

# Emit plain paths (one per line). Earlier version piped each path through
# `xargs ls -l` which produced `drwxr-xr-x ... <path>` rows; that worked
# fine inline but inside the floating zellij pane the narrow list column
# showed only metadata and clipped the names entirely. With raw paths fzf
# can match/display them directly and we keep the preview pane for the
# actual content listing.
export FZF_ALT_C_COMMAND='
    (
        dirs -lp
        git worktree list 2>/dev/null | cut -d" " -f1
        zoxide query --list 2>/dev/null
        fd --hidden --follow --type d --strip-cwd-prefix 2>/dev/null
    ) | awk "!d[\$0]++"'

# Preview: names-first listing of the selected directory. eza if available
# (icons + group-directories-first), otherwise `ls -1 -F`. Keeps the full
# preview width for filenames instead of dedicating most of it to perm /
# size / date columns. Single-line for the same reason as FZF_CTRL_T_OPTS.
export FZF_ALT_C_OPTS='--preview "command -v eza >/dev/null 2>&1 && eza --color=always --icons=auto -1 -F --group-directories-first {} || ls -1 -F --color=always {}"'

# The first printf removes the first \ from \\n.
# The second printf prints \n as a newline.
# Then fold wraps long lines
export FZF_CTRL_R_OPTS='--preview "fold -w${COLUMNS} <<< $(printf \"$(printf {})\")" --preview-window down:6'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

local DIR=$(dirname $(readlink -f $0))
source ${DIR}/functions.sh/functions.sh

source <(fzf --zsh)

# Override fzf's __fzfcmd() so the built-in widgets (Ctrl-T file picker, Alt-C
# cd picker, Ctrl-R history) launch through fzf-zellij when inside a zellij
# session, matching the floating-pane UX of our other widgets (_gh, _jb, file
# browser).
#
# The decision lives HERE rather than inside fzf-zellij so reading the
# widget call chain stays simple — `Ctrl-T → fzf-file-widget → __fzfcmd`
# and the branch is right at the call site:
#   - Inside zellij + not nested: fzf-zellij (floating pane).
#   - Outside zellij OR nested (FZF_ZELLIJ=1 from a `become` toggle): plain fzf.
#
# Use $DOTFILES_ROOT (exported from zshenv) rather than the local $DIR
# because $DIR goes out of scope once this file finishes sourcing, while
# __fzfcmd is called later when the user hits Ctrl-T / Ctrl-R / Alt-C.
__fzfcmd() {
    if [[ -n ${ZELLIJ:-} ]] && [[ -z ${FZF_ZELLIJ:-} ]]; then
        echo "${DOTFILES_ROOT:-$HOME/.dotfiles}/fzf/fzf-zellij"
    else
        echo fzf
    fi
}

source ${DIR}/functions.sh/key-binding.zsh
bindkey -M viins '^E' fzf-cd-widget
bindkey -M vicmd '^E' fzf-cd-widget
