# Start interactive Claude Code sessions at xhigh effort.
# Claude Code 2.1.316 ignores "effortLevel": "xhigh" in settings.json: a new
# session starts at medium. It accepts --effort xhigh. Thus add the flag here.
# Do not use CLAUDE_CODE_EFFORT_LEVEL in the settings env instead: it overrides
# --effort, the shell environment and /effort, so no session can change it.
# Scripts such as bin/commit-msg do not read this file and keep the default.
claude() {
    local arg
    for arg in "$@"; do
        # The first --effort wins, so an explicit choice must stay alone.
        if [[ $arg == --effort || $arg == --effort=* ]]; then
            command claude "$@"
            return
        fi
    done
    command claude --effort xhigh "$@"
}
