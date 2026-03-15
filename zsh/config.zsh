# Notify when long-running commands finish
preexec() {
    _cmd_start=$(date +%s)
}

precmd() {
    if [[ -n "$_cmd_start" ]]; then
        local duration=$(( $(date +%s) - _cmd_start ))
        unset _cmd_start
        if [[ $duration -gt 10 ]]; then
            say_done
        fi
    fi
}
