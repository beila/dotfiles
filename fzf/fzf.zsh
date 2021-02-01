echo '================================fzf'
export FZF_ALT_C_COMMAND="dirs; command find -L . -mindepth 1 \\( -path '*/\\.*' -o -fstype 'sysfs' -o -fstype 'devfs' -o -fstype 'devtmpfs' -o -fstype 'proc' \\) -prune -o -type d -print 2> /dev/null | cut -b3-"

[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh && bindkey '^E' fzf-cd-widget
