# Notify when long-running commands finish
autoload -Uz add-zsh-hook

_cmd_timer_preexec() {
    _cmd_start=$(date +%s)
}

_cmd_timer_precmd() {
    if [[ -n "$_cmd_start" ]]; then
        local duration=$(( $(date +%s) - _cmd_start ))
        unset _cmd_start
        if [[ $duration -gt 10 ]]; then
            say_done & disown
        fi
    fi
}

add-zsh-hook -d preexec _cmd_timer_preexec
add-zsh-hook -d precmd _cmd_timer_precmd
add-zsh-hook preexec _cmd_timer_preexec
add-zsh-hook precmd _cmd_timer_precmd
