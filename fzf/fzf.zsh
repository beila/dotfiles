export FZF_CTRL_T_COMMAND='
    fasd -lR | xargs -r -I I eza --color=always -d "I" &&
    (
        git ls-files -z --cached &&     # Without && processes in () are not killed
        git ls-files -z --others ||
        fd --hidden --follow --print0 --strip-cwd-prefix
    ) 2> /dev/null |
        xargs -0 -r eza --color=always -d'
export FZF_CTRL_T_OPTS='--ansi --preview "
    test -f {} &&
        bat --style=numbers --color=always --line-range :500 {} ||
        eza -l {} ||
        ls -l --color {}"'

export FZF_ALT_C_COMMAND='
    (
        (
            git worktree list | cut -d" " -f1
            fasd -dlR
        ) | xargs --no-run-if-empty eza --color=always -d --sort=none
        (
            fd --hidden --follow --print0 --strip-cwd-prefix --type d   # &&
            # fd --print0 --one-file-system --type d . '"${HOME}"' &&
            # fd --print0 --one-file-system --type d . /
        ) | xargs -0 --no-run-if-empty eza --color=always -d --sort=none
    ) 2> /dev/null |
        # " +[^ ]*" part removes space and invisible colour code.
        # "->" part separates the targets of symbolic links which eza shows
        awk --field-separator " +[^ ]*->" "{print \$1}"'
export FZF_ALT_C_OPTS='--ansi --preview "
    (
        git -C {} diff --stat --color=always &&
            git -C {} log --oneline --graph --date=short --color=always --pretty=\"format:%C(auto)%cd %h%d %s\" ||
            eza -l {} ||
            ls -l --color {}
    ) 2> /dev/null"'

# The first printf removes the first \ from \\n.
# The second printf prints \n as a newline.
# Then fold wraps long lines
export FZF_CTRL_R_OPTS='--preview "fold -w${COLUMNS} <<< $(printf \"$(printf {})\")" --preview-window down:6'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

bindkey '^E' fzf-cd-widget

local DIR=$(dirname $(readlink -f $0))
source ${DIR}/functions.sh/functions.sh
source ${DIR}/functions.sh/key-binding.zsh
