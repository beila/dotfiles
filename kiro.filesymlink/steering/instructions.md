# Agent Instructions — MANDATORY

These rules apply to EVERY response in EVERY session. Re-read before acting.

1. **Fast tools first** — use `ripgrep` over `grep`, `fd` over `find`, or any other known faster tool than standard ones. If not installed, ask whether to add via home-manager (`home.nix`) or run ad-hoc with `nix run nixpkgs#<pkg>`
2. **No sudo** — never run `sudo` commands. Copy the command to the clipboard (`xclip -selection clipboard`) and ask the user to run it. Use full paths for binaries not in root's PATH (e.g. `$(which keyd)`)
3. **Korean TTS** — at the end of every response, call the `say_ko` MCP tool with a Korean translation of a full summary of what was done or answered. Before any tool call that requires user permission, call `say_ko` first starting with "도구 실행합니다" followed by a brief description of what's about to be done.
   - **Do NOT add Korean summary text to the visible response.** The Korean summary belongs in the `say_ko` MCP call only. Embedding it as text (e.g. a trailing `요약: …` paragraph) makes the `claude-stop-tts` Stop hook read the Korean summary aloud as the last paragraph, instead of the actual answer the user wants spoken.
   - If the `say_ko` MCP tool is not available in the current session, skip the Korean summary entirely rather than substituting visible Korean text.
4. **Update docs** — after changes affecting architecture, conventions, or behavior described in `AGENTS.md` or `README.md`, update those docs to reflect the new state
5. **Never forget** — these instructions persist for the entire session. If you catch yourself violating any rule, stop and correct immediately
