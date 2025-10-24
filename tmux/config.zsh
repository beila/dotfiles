# Command timing for tmux status bar
# Record command start time when command begins
preexec() {
    # Create mapping file and timing file
    if [[ -n "$TMUX" ]]; then
        pane_id=$(tmux display-message -p "#{pane_id}")
        echo $$ >| /tmp/tmux-shell-pid-$pane_id
    fi
    echo $(date +%s) >| /tmp/tmux-cmd-start-$$
}

# Clean up timing file when command finishes
precmd() {
    rm -f /tmp/tmux-cmd-start-$$ 2>/dev/null
}

# Also clean up on shell exit
trap 'rm -f /tmp/tmux-cmd-start-$$ 2>/dev/null; if [[ -n "$TMUX" ]]; then pane_id=$(tmux display-message -p "#{pane_id}" 2>/dev/null); rm -f /tmp/tmux-shell-pid-$pane_id 2>/dev/null; fi' EXIT
