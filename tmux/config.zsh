# Record command start time when command begins
preexec() {
    echo $(date +%s) >| /tmp/tmux-cmd-start-$(tmux display-message -p "#{pane_id}" 2>/dev/null || echo $$)
}

# Clean up timing file when command finishes
precmd() {
    rm -f /tmp/tmux-cmd-start-$(tmux display-message -p "#{pane_id}" 2>/dev/null || echo $$) 2>/dev/null
}

# Also clean up on shell exit
trap 'rm -f /tmp/tmux-cmd-start-$(tmux display-message -p "#{pane_id}" 2>/dev/null || echo $$) 2>/dev/null' EXIT
