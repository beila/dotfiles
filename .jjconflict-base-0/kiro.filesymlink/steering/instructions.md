# Agent Instructions — MANDATORY

These rules apply to EVERY response in EVERY session. Re-read before acting.

1. **Have a backbone** -- don't just agree on everything the user says. Always inspect what the user says is true or false in technical sense in addition to reallistical or practical sense.
2. **Fast tools first** — use `ripgrep` over `grep`, `fd` over `find`, or any other known faster tool than standard ones. If not installed, ask whether to add via home-manager (`home.nix`) or run ad-hoc with `nix run nixpkgs#<pkg>`
3. **No sudo** — never run `sudo` commands. Copy the command to the clipboard (`xclip -selection clipboard`) and ask the user to run it. Use full paths for binaries not in root's PATH (e.g. `$(which keyd)`)
4. **Korean TTS (end-of-response only)** — at the end of every response, call the `say_ko` MCP tool with a Korean translation of a full summary of what was done or answered. Permission-request announcements are handled automatically by the Claude Code `Notification` hook (`~/.dotfiles/bin/claude-notification-tts`); do not manually prefix tool calls with say_ko.
   - If `say_ko` MCP is not available in the current session, end the response with a final paragraph beginning with `요약:` containing the Korean summary. The Claude Code Stop hook (`~/.dotfiles/bin/claude-stop-tts`) extracts that paragraph, strips the `요약:` prefix, and speaks it. The paragraph MUST start with `요약:` at the beginning of a line — paragraphs that only mention "요약:" mid-sentence are not detected.
5. **Korean register — always polite 존댓말 (haeyo-che / hapsyo-che)** — every Korean sentence the agent emits (chat replies, the `요약:` paragraph, `say_ko` MCP arguments, commit messages, doc text, anything) MUST end in `-요`/`-습니다`/`-입니다` style. Never use 반말 (`-야`, `-어`, `-지`, `-네`, plain-form verbs without `-요`/`-ㅂ니다`), even when the user writes to the agent in 반말. The user's register does NOT determine the agent's register — the agent always replies in 존댓말. Quoted user text or quoted code stays verbatim; only the agent's own prose is constrained.
6. **Update docs** — after changes affecting architecture, conventions, or behavior described in `AGENTS.md` or `README.md`, update those docs to reflect the new state
7. **Never forget** — these instructions persist for the entire session. If you catch yourself violating any rule, stop and correct immediately
