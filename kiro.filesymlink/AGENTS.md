# kiro — Context for AI Agent

`~/.dotfiles/kiro.filesymlink/` — individual files symlinked into `~/.kiro/`.

## Agents (`agents/*.json`)

- `default.json` — MCP TTS server, `autoAllowReadonly`.
- `no-mcp.json` — no MCP servers; used by `bin/commit-msg` to avoid orphaned MCP processes.
- `builder.json` — local override of the AmazonBuilderCoreAIAgents `builder` agent: adds the TTS MCP server, narrowed `execute_bash` allowlist for read-only operations, and an `fs_write:*AGENTS.md` permission so Kiro can edit AGENTS.md without prompting.

## Settings

- `settings/cli.json` — default agent: `builder`; default model: `claude-opus-4.7`.

## Bin (under `kiro.filesymlink/bin/`, also used at `bin/`)

- `kiro.filesymlink/bin/kiro-response` — TTS fallback.
- `bin/mcp-tts` — MCP server for `say` / `say_ko` tools, kills previous playback via `setsid` + `kill -PGID`.
- `bin/test_mcp_tts.sh` — `bash bin/test_mcp_tts.sh`.

## Steering files

`~/.kiro/steering/` symlinks pull from two roots (bootstrap walks every `*.filesymlink/` it finds at `-maxdepth 3`):

- `~/.dotfiles/kiro.filesymlink/steering/instructions.md` — canonical, always-loaded instruction set (Korean-TTS rule, sudo-disallow, fast-tools rules). The root AGENTS.md's "Agent Instructions" section just points here.
- `~/.dotfiles/work-dotfiles/kiro.filesymlink/steering/amazon-builder-context-do-not-delete.md` — Amazon-internal SDE context (Brazil/CRUX/Apollo/…); kept in work-dotfiles so the public repo stays employer-agnostic.
- `~/.dotfiles/work-dotfiles/kiro.filesymlink/steering/amazon-production-safety-do-not-delete.md` — AWS production-safety rules; same rationale.

## Global Claude instructions

`~/.claude/CLAUDE.md` is auto-loaded into every Claude Code session regardless of project. It just `@`-references the three steering files above (one from this repo + two from `work-dotfiles/`). On machines without the work-dotfiles checkout, the two `@`-references resolve to nothing — Claude Code handles missing referenced files quietly.

## Known issues

- **kiro-cli** can't receive prompts as command-line arguments (hangs on large input) — use stdin piping.
- **kiro-cli `--agent default`** spawns MCP servers that become orphaned on exit — use `--agent no-mcp` for scripted use.
