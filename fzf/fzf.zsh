export FZF_CTRL_T_COMMAND="fasd -alR"
export FZF_ALT_C_COMMAND="fasd -dlR"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh \
    && bindkey '^E' fzf-cd-widget
