# Dotfiles Workstation Setup — Context for AI Agent

## Agent Instructions

See `kiro.filesymlink/steering/instructions.md` for the canonical, always-loaded instruction set.

## TODO List

### High impact
- [~] make copilot key work as super — **WON'T FIX** (investigated 2026-06-21, do not retry without new info). The Copilot key is a hardware chord `leftmeta+leftshift+f23`; collapsing it requires a keyd chord on `leftmeta`, but `common`'s `leftmeta = overloadt2` (which gives Super-key-tap=Albert) consumes `leftmeta` before the chord can assemble. Mutually exclusive on the same keycode — and Super-tap=Albert is used more, so it wins. keyd maintainer also calls the meta+shift+f23 variant "mostly hopeless". Full findings + the working-but-rejected config + revisit conditions (e.g. a future kernel collapsing the chord) are in `keyd/AGENTS.md`. Current state: `f23 = noop` (tap suppressed), hold = Super+Shift via `common`.
- [ ] skip commands in skip list even when running with nix run, npx, uvx. When TUI command is detected with nix run, npx, uvx, add the correct package to the skip list.
- [ ] Add a way for commands to disable logrun from themselves.
- [x] Add a way to add NOLOG=1 more easily even after typing all the command line — Alt+Enter (`\e^M`) prepends `NOLOG=1 ` to the buffer and submits; history records the full `NOLOG=1 cmd`. Widget `_logrun_nolog_accept_line` in `zsh/zz-logrun-auto.zsh`.

### Medium impact
- [x] make focused window more noticeable but not ugly — focused border is now 4px LEGO orange `#F8BB3D` (matches hangul-OSD), unfocused painted near-invisible `#1d1d1d`, `smartBorders` hides the border for a lone window on a single screen (kept when multiple screens are visible). Picom rejected (extra compositor process for a purely cosmetic win); true 0px-unfocused rejected because border-width toggles resize the client by 2×width on every focus change → terminal re-wrap under focus-follows-mouse. See `xwindow/AGENTS.md`.
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
- [x] match sysmon color threshold to match the resolution of height, so that the same height doesn't show sometimes green and sometimes yellow — `severity()` now keys off the quantized dot-height (0..4) instead of raw percent, so a bar height maps to exactly one color (h1,h2→green, h3→yellow, h4→red). See `xwindow/bin/sysmon-genmon`.
- [x] _jh outputs incorrect string when the graph area includes space — the oneline templates now carry the change id/path/commit-id in hidden tab fields (`<display>\t<change-id>\t<path>\t<commit-id>`) and `_jh`/`_gh` extract via `cut -f2`/`--accept-nth=2` (tab-delimited), so merge/elision graph spaces no longer shift the field. See `fzf/functions.sh` and `jj.configsymlink/config.toml`.
- [x] add a way to output the git commit id instead of the change id from `_jh`/`_jhh` — **ctrl-x** in the log picker yanks the commit id (12-char `commit_id.short()`) via hidden tab field 4 (`become(printf '%s\n' {+4})`), while Enter still yields the change id (`--accept-nth=2`). See `fzf/functions.sh`, `jj.configsymlink/config.toml`, and `fzf/AGENTS.md`.
- [x] add a shortcut to _jb to toggle remote bookmarks — **ctrl-r** toggles `_jb`↔`_jbr` (`jj bookmark list --all-remotes`: every tracked + untracked remote bookmark, even when the target matches local). Same `become` pattern as the ctrl-b workspace toggle; header checkbox (`☐/☑ remotes`) shows the state. See `fzf/functions.sh/functions.sh` and `fzf/AGENTS.md`.
- [ ] show network graph differently when the internet is not accessible

### Low impact
- [ ] no vertical gap between ghostty windows
- [x] random voice for `say-en`/`say-ko`; same voice within one parent process (parent pid mod # voices?) — shared `bin/say-voice.sh` maps caller→voice via `voice = pool[sha256(key) mod N]` (sha256 not cksum/CRC32, so the distribution is uniform for arbitrary opaque keys the caller passes blind — no need to know N). Key = `$SAY_VOICE_KEY` if set (empty ⇒ unidentified ⇒ default voice; `"1"` honoured verbatim), else `$PPID`. `say` resolves+exports the key before its `setsid`; detaching callers (`claude-stop-tts`/`claude-notification-tts` → Claude `session_id`, `mcp-tts` → server `$$`) pass it themselves because a `setsid` child does *not* get `PPID==1` under a user-systemd subreaper. Korean = 3 free edge-tts voices; English = 5-voice piper pool with lazy per-voice download (alba fallback). See `bin/AGENTS.md`. Test: `bin/test_say_voice.sh`.
- [ ] super-c in visual block mode of neovide
- [x] add temperature in sysmon — CPU package temp now renders as a `🌡️` braille sparkline in the panel row (normalized 40–100°C → green ≤~77°C, yellow ~78–92°C, red ≥~92°C, reusing the existing height/severity quantizer) plus a `Temp:` tooltip line; fan RPM (`thinkpad/fan1_input`) is tooltip-only (`Fan:`). Sensors resolved by driver name via `hwmon_by_name` (not fixed `hwmonN`). See `xwindow/bin/sysmon-genmon` and `xwindow/AGENTS.md`.
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
| `bin/` | `logrun`, `commit-msg`, `say`/`say-en`/`say-ko` TTS, Claude Code hooks, `vpn-up`/`vpn-watch`, `zellij-cycle`, `zmx-select`, `notify-webhook`, `mcp-tts`, `evolution-token-refresh` (in-place M365 token refresh, scheduled; notifies when a hardware-key sign-in is needed) + `evolution-reauth` (attended wrapper). |
| `kiro.filesymlink/` | Kiro/Claude agents, `settings/cli.json`, MCP TTS server, steering files, global `~/.claude/CLAUDE.md`. |
| `private-dotfiles/` | Companion repo (gitignored). See its own AGENTS.md. |
| `work-dotfiles/` | Companion repo (gitignored). See its own AGENTS.md. |

## Cross-cutting notes

- **User on LDAP** — can't `chsh`, so `$SHELL` is bash; zsh is started via `exec` from `.bashrc`. Affects every shell-feature decision.
- **`apt` collision with the JDK's Annotation Processing Tool** — `home-manager.configsymlink/system-deps.sh` checks dnf/yum first.
- **linuxbrew's `dbus-run-session` has a broken config** — `gnome.nix` is conditionally skipped when `/usr/bin/dconf` is absent.
- **Hosts without per-user systemd** — when nix systemd ≥256 can't run (cgroup v1 hosts that can't be rebooted with `systemd.unified_cgroup_hierarchy=1`), `dotfiles.schedule` provides a cron backend instead. See `home-manager.configsymlink/AGENTS.md`.
- **Private/work dotfiles** (`private-dotfiles/`, `work-dotfiles/`) — gitignored sibling jj/git repos, resolved at flake eval time via `builtins.getEnv "HOME"` (requires `home-manager switch --impure`). Auto-loaded `*.nix` modules and auto-sourced `*.zsh`. `script/bootstrap`'s `*.filesymlink` walk also picks up files at `-maxdepth 3`. Both fall back to empty when absent. See each repo's own AGENTS.md.
