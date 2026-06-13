# kiro — Context for AI Agent

`kiro.filesymlink/` — individual files symlinked into `~/.kiro/` by `script/bootstrap`.

## Agents (`agents/*.json`)

- `default.json` — MCP TTS server, `autoAllowReadonly`.
- `no-mcp.json` — no MCP servers; used by `bin/commit-msg` to avoid orphaned MCP processes.
- `builder.json` — local override of the AmazonBuilderCoreAIAgents `builder` agent: adds the TTS MCP server, narrowed `execute_bash` allowlist for read-only operations, and an `fs_write:*AGENTS.md` permission so Kiro can edit AGENTS.md without prompting.

## Settings

- `settings/cli.json` — default agent: `builder`; default model: `claude-opus-4.7`.

## Steering files

`~/.kiro/steering/` symlinks pull from two roots (bootstrap walks every `*.filesymlink/` it finds at `-maxdepth 3`):

- `kiro.filesymlink/steering/instructions.md` — canonical, always-loaded instruction set (Korean-TTS rule, no-sudo, fast-tools rule). Root AGENTS.md's "Agent Instructions" section just points here.
- `work-dotfiles/kiro.filesymlink/steering/amazon-builder-context-do-not-delete.md` — Amazon-internal SDE context (Brazil/CRUX/Apollo/…); kept in work-dotfiles so the public repo stays employer-agnostic.
- `work-dotfiles/kiro.filesymlink/steering/amazon-production-safety-do-not-delete.md` — AWS production-safety rules; same rationale.

## Global Claude instructions

`~/.claude/CLAUDE.md` is auto-loaded into every Claude Code session regardless of project. It just `@`-references the three steering files above. On machines without the work-dotfiles checkout, those `@`-references resolve to nothing — Claude Code handles missing referenced files quietly.

## TTS bin

- `kiro.filesymlink/bin/kiro-response` — TTS fallback for kiro chat output.
- `bin/mcp-tts` — MCP server exposing `say` / `say_ko` tools to Kiro/Claude. See `bin/AGENTS.md`.
