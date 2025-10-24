# Record command start time with shell PID
preexec() {
    echo $(date +%s) >| /tmp/tmux-cmd-start-$$
}

# Clean up timing file when command finishes  
precmd() {
    rm -f /tmp/tmux-cmd-start-$$ 2>/dev/null
}
# Command timing for tmux status bar
# Record command start time when command begins
preexec() {
    echo $(date +%s) >| /tmp/tmux-cmd-start-$$
}

# Clean up timing file when command finishes
precmd() {
    rm -f /tmp/tmux-cmd-start-$$ 2>/dev/null
}

# Also clean up on shell exit
trap 'rm -f /tmp/tmux-cmd-start-$$ 2>/dev/null' EXIT
