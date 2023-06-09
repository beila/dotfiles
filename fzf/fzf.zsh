export FZF_CTRL_T_COMMAND="fasd -alR;\
    git ls-files --cached 2> /dev/null;\
    git ls-files --others 2> /dev/null;\
    command find -L . -mindepth 1 \\( -path '*/\\.*' -o -fstype 'sysfs' -o -fstype 'devfs' -o -fstype 'devtmpfs' -o -fstype 'proc' \\) -prune \
    -o -type d -print 2> /dev/null | cut -b3-;\
    command find -L . -mindepth 1 \\( -path '*/\\.*' -o -fstype 'sysfs' -o -fstype 'devfs' -o -fstype 'devtmpfs' -o -fstype 'proc' \\) -prune \
    -o -type f -print \
    -o -type l -print 2> /dev/null | cut -b3-"
export FZF_CTRL_T_OPTS="--preview 'test -f {} && bat --style=numbers --color=always --line-range :500 {} || exa -l {} || ls -l --color {}'"
export FZF_ALT_C_COMMAND="fasd -dlR"
export FZF_ALT_C_OPTS="--preview 'exa -l {} || ls -l --color {}'"

# The first printf removes the first \ from \\n.
# The second printf prints \n as a newline.
# Then fold wraps long lines
export FZF_CTRL_R_OPTS='--preview "fold -w${COLUMNS} <<< $(printf \"$(printf {})\")" --preview-window down:6'

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh \
    && bindkey '^E' fzf-cd-widget

local DIR=$(dirname $(readlink -f $0))
source ${DIR}/functions.sh/functions.sh
source ${DIR}/functions.sh/key-binding.zsh
