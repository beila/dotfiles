local ls=$(which eza &> /dev/null && echo eza || echo ls)

export FZF_DEFAULT_OPTS='--bind "ctrl-n:preview-half-page-down" --bind "ctrl-p:preview-half-page-up"'

# TODO fasd used to have files listed, but zoxide does not. I need list of files most likely to be used. Maybe locate?
export FZF_CTRL_T_COMMAND='
    #fasd -lR | xargs -r -I I '$ls' --color=always -d "I" &&
    (
        git ls-files -z --cached &&     # Without && processes in () are not killed
        git ls-files -z --others ||
        fd --hidden --follow --print0 --strip-cwd-prefix
    ) 2> /dev/null |
        xargs -0 -r '$ls' --color=always -d'
export FZF_CTRL_T_OPTS='--ansi --preview "
    test -f {} &&
        bat --style=numbers --color=always --line-range :500 {} ||
        '$ls' -l {}"'

export FZF_ALT_C_COMMAND='
    (
        (
            dirs -lp
            git worktree list | cut -d" " -f1
            zoxide query --list
        ) | xargs --no-run-if-empty '$ls' --color=always -d --sort=none
        (
            fd --hidden --follow --print0 --strip-cwd-prefix --type d   # &&
            # fd --print0 --one-file-system --type d . '"${HOME}"' &&
            # fd --print0 --one-file-system --type d . /
        ) | xargs -0 --no-run-if-empty '$ls' --color=always -d --sort=none
    ) |# 2> /dev/null |
        # " +[^ ]*" part removes space and invisible colour code.
        # "->" part separates the targets of symbolic links which eza shows
        awk -F " +[^ ]*->" "{print \$1}" |
        #sed "s:$(pwd)/::" |
        #sed "s:$(pwd):.:" |
        #sed "s:$HOME:~:" |
        awk "!d[\$0]++"
                '

export FZF_ALT_C_OPTS='--ansi -d"'$HOME/'" --with-nth 2 --preview "
    (
        git -C {} diff --stat --color=always -- .
            #git -C {} log --oneline --graph --date=short --color=always --pretty=\"format:%C(auto)%cd %h%d %s\" ||
            '$ls' --color=always -l {}
    ) 2> /dev/null"'

# The first printf removes the first \ from \\n.
# The second printf prints \n as a newline.
# Then fold wraps long lines
export FZF_CTRL_R_OPTS='--preview "fold -w${COLUMNS} <<< $(printf \"$(printf {})\")" --preview-window down:6'

echo FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFf
[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

bindkey '^E' fzf-cd-widget

local DIR=$(dirname $(readlink -f $0))
source ${DIR}/functions.sh/functions.sh
source ${DIR}/functions.sh/key-binding.zsh
