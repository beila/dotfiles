# Start interactive Claude Code sessions at xhigh effort.
# Claude Code 2.1.316 ignores "effortLevel": "xhigh" in settings.json: a new
# session starts at medium. It accepts --effort xhigh. Thus add the flag here.
# The last --effort wins, so an --effort on the command line and /effort still
# change it. Do not set CLAUDE_CODE_EFFORT_LEVEL in the settings env instead: it
# overrides --effort, and a session that loads it keeps it after its removal.
# Scripts such as bin/commit-msg do not read this file and keep the default.
claude() {
    command claude --effort xhigh "$@"
}
