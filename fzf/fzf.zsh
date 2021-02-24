export FZF_CTRL_T_COMMAND="fasd -alR"
export FZF_ALT_C_COMMAND="fasd -dlR"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh \
    && bindkey '^E' fzf-cd-widget

local DIR=$(dirname $(readlink -f $0))
source ${DIR}/functions.sh/functions.sh
source ${DIR}/functions.sh/key-binding.zsh
