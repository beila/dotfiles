# Notify when long-running commands finish
autoload -Uz add-zsh-hook

_cmd_timer_preexec() {
    _cmd_start=$(date +%s)
}

_cmd_timer_precmd() {
    if [[ -n "$_cmd_start" ]]; then
        local duration=$(( $(date +%s) - _cmd_start ))
        unset _cmd_start
        if [[ $duration -gt 10 ]] && [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]]; then
            # Keep backend diagnostics out of the next prompt.
            (say_done </dev/null >/dev/null 2>&1 &)
        fi
    fi
}

add-zsh-hook -d preexec _cmd_timer_preexec
add-zsh-hook -d precmd _cmd_timer_precmd
add-zsh-hook preexec _cmd_timer_preexec
add-zsh-hook precmd _cmd_timer_precmd
