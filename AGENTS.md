# Dotfiles Workstation Setup — Context for AI Agent

## Agent Instructions

See `kiro.filesymlink/steering/instructions.md` for the canonical, always-loaded instruction set.

## TODO List

### High impact
- [ ] 한글 입력 상태를 화면에 잘 보이게 표시
  - 영어일 땐 안 보이고 한글일 때만 보여도 될 듯
- [ ] neovide 한글 폰트를 ghostty에서 쓰는 것과 같은 걸로 바꾸자
  - 영문 폰트는 그대로 유지
- [ ] a (n)vim command to change the extension of the current file and set filetype and everything

### Medium impact
- [ ] make focused window more noticeable but not ugly (currently red `focusedBorderColor` line)
  - options: pick a subtler border colour, or `borderWidth = 0` + picom shadow as the focus indicator
  - picom adds GPU/process overhead; only adopt if the visual win is worth it
  - no border on the tiled window when there's only one tiled
- [ ] share fzf config between shell (`fzf/functions.sh/functions.sh`) and nvim (`fzf.lua`)
  - fzf command-line parameters (including preview commands) are duplicated between the two
  - goal: single source of truth for shared fzf options/previews
  - direction: whichever is simpler (e.g. shared config file, shell script that both source, or generated opts)
- [ ] review each nvim plugin and cleanup/modernise
- [ ] switch nix neovim module to `hm-generated.lua` approach
  - better: `xdg.configFile."nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;` + restore own `init.lua` with `require 'hm-generated'` at top
  - benefit: nix stops overwriting `init.lua`, `myinit.lua` can be merged back into `init.lua`, simpler config chain
  - see home-manager news 2026-01-25 and PR #8586/#8606
  - files: `home-manager.configsymlink/nvim.nix`, `nvim.configsymlink/myinit.lua`, `nvim.configsymlink/.gitignore`
- [ ] fzf/functions.sh sets list width depending on the contents
- [ ] Check if I can log in with fingerprint https://learn.omacom.io/2/the-omarchy-manual/77/fingerprint-fido2-authentication
- [ ] Check if I can sudo with security key https://learn.omacom.io/2/the-omarchy-manual/77/fingerprint-fido2-authentication
- [ ] use zmx-select locally instead of zellij
  - zmx-select should be able to switch between machines, of course without blocking
  - can it switch between sessions as easily as zellij session manager?
- [ ] replace absolute path from xfce settings
- [ ] xdg-open fails to open due to container issue

### Low impact
- [ ] there's no gap between ghostty vertically
- [ ] make copilot key work as super
- [ ] review remaining mini-nvim modules: mini.splitjoin (toggle single/multi-line), mini.bracketed (unified [/] nav)

## Repo conventions

See `README.md` for the symlink-suffix convention (`*.symlink`, `*.configsymlink`, `*.filesymlink`) and bootstrap flow.

## Architecture index

Detailed design and rationale live in per-directory `AGENTS.md`. Pick the one closest to your task.

| Directory | Topic |
|-----------|-------|
| `home-manager.configsymlink/AGENTS.md` | Home Manager flake, schedule.nix (cross-backend periodic jobs), gnome.nix (IBus), nvim.nix, xmonad.nix, neovide.nix, xdg.nix, zmx.nix, system-deps.sh; Nix flake gotchas (impure eval, warn-dirty), font copying. |
| `xwindow/AGENTS.md` | xmonad.hs (rules, hooks, scratchpads, zoom handling), audio/brightness/battery OSDs, OSD library (cairo + XShape), weather/sysmon genmons, `random-lockscreen` (HEIC handling), copyq integration, monitor setup. |
| `keyd/AGENTS.md` | Key remapping stack (keyd configs, input-remapper, universal Super+C/V copy/paste origin). |
| `nvim.configsymlink/AGENTS.md` | Full Neovim dev tooling: per-language LSP/DAP, plugins, fzf-lua grep dialog, autoformat, treesitter, my-clipboard for Super+C/V. |
| `fzf/AGENTS.md` | `fzf.zsh`, `fzf-zellij` (adaptive sizing, ctrl-/ vertical-position injection), `functions.sh/` jj-first dispatchers, key-binding.zsh. |
| `zsh/AGENTS.md` | Standalone zsh config, functions (`c`/`p`/`o`/`say_done`/`ju`/`jda`), fzf-tab tab-completion. |
| `jj.configsymlink/AGENTS.md` | jj config (revset/template aliases), `empty()`/`diff_lines()` gotchas. |
| `zellij.configsymlink/AGENTS.md` | Keybindings; kitty keyboard protocol workaround. |
| `ghostty.configsymlink/AGENTS.md` | Legacy ctrl-code keybinds, terminfo. |
| `script/AGENTS.md` | `sync_all` / `sync_repo` (snapshot + bookmark-sync flows), `updatedb`, `flake-update` watchdog, `battery-notify`, `print-hp`. |
| `script/logger/AGENTS.md` | `log.sh` (level + retention + dedup), notification backends, Telegram setup, push-notification rationale. |
| `bin/AGENTS.md` | `logrun`, `commit-msg`, `say`/`say-en`/`say-ko` TTS, Claude Code Stop/Notification hooks, `vpn-up`/`vpn-watch`, `zellij-cycle`, `zmx-select`, `notify-webhook`, `mcp-tts`. |
| `kiro.filesymlink/AGENTS.md` | Kiro agents (default/no-mcp/builder), `settings/cli.json`, MCP TTS server, steering files, global `~/.claude/CLAUDE.md`. |
| `private-dotfiles/AGENTS.md` | Site/employer-specific JDK setup, impure-eval rationale, per-host `homeConfigurations`, host-onboarding recipe. |

## Cross-cutting notes

- **User on LDAP** — can't `chsh`, so `$SHELL` is bash; zsh is started via `exec` from `.bashrc`. Affects every shell-feature decision.
- **JDK on PATH** — when `apt` resolves to the JDK's Annotation Processing Tool (not Debian apt), `home-manager.configsymlink/system-deps.sh` checks dnf/yum first. linuxbrew's `dbus-run-session` has a broken config, so `gnome.nix` is conditionally skipped when `/usr/bin/dconf` is absent.
- **Hosts without per-user systemd** — when nix systemd ≥256 can't run (cgroup v1 hosts that can't be rebooted with `systemd.unified_cgroup_hierarchy=1`), `dotfiles.schedule` provides a cron backend instead — see `home-manager.configsymlink/AGENTS.md`.
- **Private dotfiles** (`private-dotfiles/`) — gitignored colocated jj/git repo; resolved at flake eval time via `builtins.getEnv "HOME"` (requires `home-manager switch --impure`). Stores machine-specific config (host configs, tokens, webhook URLs), site/employer-specific JDK setup, and per-host `homeConfigurations`. zsh `**/*.zsh` glob auto-sources; `install.sh` files run by `script/install`; `ssh.filesymlink/` provides SSH host aliases; `telegram.env` holds bot creds for the Telegram backend; `logger.nix` writes `~/.config/environment.d/20-logger.conf` so systemd-launched jobs inherit `LOG_ROOT`/`LOG_REL_BASE`.
