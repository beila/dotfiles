# Agent Instructions — MANDATORY

These rules apply to EVERY response in EVERY session. Re-read before acting.

1. **Fast tools first** — use `ripgrep` over `grep`, `fd` over `find`, or any other known faster tool than standard ones. If not installed, ask whether to add via home-manager (`home.nix`) or run ad-hoc with `nix run nixpkgs#<pkg>`
2. **No sudo** — never run `sudo` commands. Copy the command to the clipboard (`xclip -selection clipboard`) and ask the user to run it. Use full paths for binaries not in root's PATH (e.g. `$(which keyd)`)
3. **Korean TTS (end-of-response only)** — at the end of every response, call the `say_ko` MCP tool with a Korean translation of a full summary of what was done or answered. Permission-request announcements are handled automatically by the Claude Code `Notification` hook (`~/.dotfiles/bin/claude-notification-tts`); do not manually prefix tool calls with say_ko.
   - If `say_ko` MCP is not available in the current session, end the response with a final paragraph beginning with `요약:` containing the Korean summary. The Claude Code Stop hook (`~/.dotfiles/bin/claude-stop-tts`) extracts that paragraph, strips the `요약:` prefix, and speaks it. The paragraph MUST start with `요약:` at the beginning of a line — paragraphs that only mention "요약:" mid-sentence are not detected.
4. **Update docs** — after changes affecting architecture, conventions, or behavior described in `AGENTS.md` or `README.md`, update those docs to reflect the new state
5. **Never forget** — these instructions persist for the entire session. If you catch yourself violating any rule, stop and correct immediately
