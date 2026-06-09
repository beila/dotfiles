# Dotfiles Workstation Setup — Context for AI Agent

## Agent Instructions

See `kiro.filesymlink/steering/instructions.md` for the canonical, always-loaded instruction set.

## TODO List

### High impact
- [ ] make copilot key work as super (current `keyd/thinkpad.conf` config exists but doesn't actually work in practice — needs investigation)
  - it works with hold, but not with tap
- [ ] skip commands in skip list even when running with nix run, npx, uvx. When TUI command is detected with nix run, npx, uvx, add the correct package to the skip list.

### Medium impact
- [ ] make focused window more noticeable but not ugly (currently red `focusedBorderColor` line)
  - options: pick a subtler border colour, or `borderWidth = 0` + picom shadow as the focus indicator
  - picom adds GPU/process overhead; only adopt if the visual win is worth it
  - no border on the tiled window when there's only one tiled
- [ ] share fzf config between shell (`fzf/functions.sh/functions.sh`) and nvim (`fzf.lua`)
  - fzf command-line parameters (including preview commands) are duplicated between the two
  - goal: single source of truth for shared fzf options/previews
  - direction: whichever is simpler (e.g. shared config file, shell script that both source, or generated opts)
  - 양쪽에서 어떤 단축키를 뭐에 쓰는지 먼저 정리해봐야겠다
- [ ] review each nvim plugin and cleanup/modernise
- [ ] switch nix neovim module to `hm-generated.lua` approach
  - better: `xdg.configFile."nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;` + restore own `init.lua` with `require 'hm-generated'` at top
  - benefit: nix stops overwriting `init.lua`, `myinit.lua` can be merged back into `init.lua`, simpler config chain
  - see home-manager news 2026-01-25 and PR #8586/#8606
  - files: `home-manager.configsymlink/nvim.nix`, `nvim.configsymlink/myinit.lua`, `nvim.configsymlink/.gitignore`
- [ ] fzf/functions.sh sets list width depending on the contents
- [ ] fingerprint login + sudo (https://learn.omacom.io/2/the-omarchy-manual/77/fingerprint-fido2-authentication)
- [ ] use zmx-select locally instead of zellij
  - should switch between machines without blocking, and between sessions as easily as zellij session manager
  - bring back something like fzf-zellij
- [ ] xdg-open fails to open html files due to container issue
- [x] detect if I'm in a meeting before `say` actually says something — `say` now checks `pw-dump` for a `Stream/Input/Audio` from zoom/teams/meet/webex/slack/chime/discord (regex via `$SAY_MEETING_APP_REGEX`, bypass via `SAY_NO_MEETING_CHECK=1`). Works even when you're muted in the call. See `bin/AGENTS.md`.

### Low impact
- [ ] no vertical gap between ghostty windows
- [ ] random voice for `say-en`/`say-ko`; same voice within one parent process (parent pid mod # voices?)
- [ ] super-c in visual block mode of neovide
- [ ] add temperature in sysmon
- [ ] bidirectional auto-suggestion for `LOGRUN_AUTO_FUNCTIONS` tuning:
  - wrapped function finished under threshold AND `t_total - t_in_cmd > 200ms` → suggest removing from list (it's adding shell-startup overhead for nothing)
  - unwrapped function exceeded threshold → suggest adding to list (its output should be captured)
  - dedup once per shell session per name (assoc array in the widget)

## Repo conventions

See `README.md` for the symlink-suffix convention (`*.symlink`, `*.configsymlink`, `*.filesymlink`) and bootstrap flow.

## Architecture index

Detailed design lives in per-directory `AGENTS.md`. Pick the one closest to your task.

| Directory | Topic |
|-----------|-------|
| `home-manager.configsymlink/` | Home Manager flake, schedule.nix (cross-backend periodic jobs), gnome.nix, nvim.nix, xmonad.nix, neovide.nix, zmx.nix, system-deps.sh. |
| `xwindow/` | xmonad.hs, audio/brightness/battery OSDs, hangul-osd, weather/sysmon genmons, random-lockscreen, monitor setup. |
| `keyd/` | Key remapping (keyd configs, input-remapper, universal Super+C/V copy/paste). |
| `nvim.configsymlink/` | Per-language LSP/DAP, plugins, fzf-lua grep dialog, autoformat, treesitter. |
| `fzf/` | `fzf.zsh`, `fzf-zellij` (adaptive sizing, layout-aware ctrl-/), `functions.sh/` jj-first dispatchers, key bindings. |
| `zsh/` | zsh config (zprezto-free), functions, fzf-tab, logrun-auto widget. |
| `jj.configsymlink/` | jj config (revset/template aliases), `empty()`/`diff_lines()` gotchas. |
| `zellij.configsymlink/` | Keybindings; kitty keyboard protocol workaround. |
| `ghostty.configsymlink/` | Legacy ctrl-code keybinds, terminfo. |
| `script/` | `sync_all` / `sync_repo`, `updatedb`, `flake-update`, `battery-notify`, `print-hp`. |
| `script/logger/` | `log.sh` (level + retention + dedup), notification backends, Telegram setup. |
| `bin/` | `logrun`, `commit-msg`, `say`/`say-en`/`say-ko` TTS, Claude Code hooks, `vpn-up`/`vpn-watch`, `zellij-cycle`, `zmx-select`, `notify-webhook`, `mcp-tts`. |
| `kiro.filesymlink/` | Kiro/Claude agents, `settings/cli.json`, MCP TTS server, steering files, global `~/.claude/CLAUDE.md`. |
| `private-dotfiles/` | Companion repo (gitignored). See its own AGENTS.md. |
| `work-dotfiles/` | Companion repo (gitignored). See its own AGENTS.md. |

## Cross-cutting notes

- **User on LDAP** — can't `chsh`, so `$SHELL` is bash; zsh is started via `exec` from `.bashrc`. Affects every shell-feature decision.
- **`apt` collision with the JDK's Annotation Processing Tool** — `home-manager.configsymlink/system-deps.sh` checks dnf/yum first.
- **linuxbrew's `dbus-run-session` has a broken config** — `gnome.nix` is conditionally skipped when `/usr/bin/dconf` is absent.
- **Hosts without per-user systemd** — when nix systemd ≥256 can't run (cgroup v1 hosts that can't be rebooted with `systemd.unified_cgroup_hierarchy=1`), `dotfiles.schedule` provides a cron backend instead. See `home-manager.configsymlink/AGENTS.md`.
- **Private/work dotfiles** (`private-dotfiles/`, `work-dotfiles/`) — gitignored sibling jj/git repos, resolved at flake eval time via `builtins.getEnv "HOME"` (requires `home-manager switch --impure`). Auto-loaded `*.nix` modules and auto-sourced `*.zsh`. `script/bootstrap`'s `*.filesymlink` walk also picks up files at `-maxdepth 3`. Both fall back to empty when absent. See each repo's own AGENTS.md.
