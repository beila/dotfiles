# kiro — Context for AI Agent

`kiro.filesymlink/` — individual files symlinked into `~/.kiro/` by `script/bootstrap`.

## Agents (`agents/*.json`)

- `default.json` — MCP TTS server, `autoAllowReadonly`.
- `no-mcp.json` — no MCP servers; used by `bin/commit-msg` to avoid orphaned MCP processes.
- `builder.json` — local override of the AmazonBuilderCoreAIAgents `builder` agent: adds the TTS MCP server, narrowed `execute_bash` allowlist for read-only operations, and an `fs_write:*AGENTS.md` permission so Kiro can edit AGENTS.md without prompting.

## Settings

- `settings/cli.json` — default agent: `builder`; default model: `claude-opus-5`.

## Skills (`skills/`)

Shared-skill symlinks: each entry points repo-relatively at `../../../.agents/skills/<name>` (the cross-tool skill store used by Claude via `claude.symlink/skills`). Bootstrap's `*.filesymlink` walk materializes them per-file under `~/.kiro/skills/<name>/…` (it follows symlinks with `find -L`). `~/.kiro/skills/artifactory-design` is NOT ours — it's installed/managed by artifactory-mcp (`.managed-by-artifactory-mcp` marker); leave it alone.

## Steering files

`~/.kiro/steering/` symlinks pull from two roots (bootstrap walks every `*.filesymlink/` it finds at `-maxdepth 3`):

- `kiro.filesymlink/steering/instructions.md` — canonical, always-loaded instruction set (Korean-TTS rule, no-sudo, fast-tools rule). Root AGENTS.md's "Agent Instructions" section just points here.
- `work-dotfiles/kiro.filesymlink/steering/amazon-builder-context-do-not-delete.md` — Amazon-internal SDE context (Brazil/CRUX/Apollo/…); kept in work-dotfiles so the public repo stays employer-agnostic.
- `work-dotfiles/kiro.filesymlink/steering/amazon-production-safety-do-not-delete.md` — AWS production-safety rules; same rationale.

## Global Claude instructions

`~/.claude/CLAUDE.md` is auto-loaded into every Claude Code session regardless of project. It just `@`-references the three steering files above. On machines without the work-dotfiles checkout, those `@`-references resolve to nothing — Claude Code handles missing referenced files quietly.

## Global Codex instructions

`~/.codex` is a symlink to `private-dotfiles/codex.symlink/` (same pattern as `~/.claude` → `private-dotfiles/claude.symlink/`). Inside it, `AGENTS.md` — Codex's global instruction file, auto-loaded every session — is a repo-relative symlink to `kiro.filesymlink/steering/instructions.md`, so Kiro, Claude, and Codex all load the same canonical instruction set. Codex has no `say_ko` MCP or Stop-hook TTS; the rule-4 fallback (`요약:` paragraph) still applies but is text-only there. See `private-dotfiles/AGENTS.md` for what is tracked vs gitignored in `codex.symlink/`.

## TTS bin

- `kiro.filesymlink/bin/kiro-response` — TTS fallback for kiro chat output.
- `bin/mcp-tts` — MCP server exposing `say` / `say_ko` tools to Kiro/Claude. See `bin/AGENTS.md`.
