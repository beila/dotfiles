export FZF_CTRL_T_COMMAND='
    fasd -flR |
        sed "s:^${HOME}:~:"
    git ls-files --cached 2> /dev/null
    git ls-files --others 2> /dev/null ||
        find -L . -mindepth 1 -not -path "*/.git/*" 2> /dev/null |
        cut -b3-'
export FZF_CTRL_T_OPTS='--preview "
    file=$(sed "s:^~:${HOME}:" <<< {})
    test -f "$file" &&
        bat --style=numbers --color=always --line-range :500 "$file" ||
        exa -l "$file" ||
        ls -l --color "$file""'

export FZF_ALT_C_COMMAND='
    fasd -dlR
    find -L . -mindepth 1 -type d -not -path "*/.git/*" 2> /dev/null |
        cut -b3-'
export FZF_ALT_C_OPTS='--preview "
    exa -l {} ||
        ls -l --color $file"'

# The first printf removes the first \ from \\n.
# The second printf prints \n as a newline.
# Then fold wraps long lines
export FZF_CTRL_R_OPTS='--preview "fold -w${COLUMNS} <<< $(printf \"$(printf {})\")" --preview-window down:5'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh

bindkey '^E' fzf-cd-widget

local DIR=$(dirname $(readlink -f $0))
source ${DIR}/functions.sh/functions.sh
source ${DIR}/functions.sh/key-binding.zsh
