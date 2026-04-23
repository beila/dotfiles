# Dotfiles Workstation Setup — Context for AI Agent

## Agent Instructions

See `kiro.filesymlink/steering/instructions.md` for the canonical, always-loaded instruction set.

## TODO List

### High impact
- [ ] check `home-manager news` — neovim withRuby/withPython3 defaults changed (stateVersion < 26.05)
- [ ] can't type hangul in zellij/ghostty
- [ ] **universal Copy/paste key** — copy/paste keys that work the same way in x window app, terminals, zellij, neovide, (neo)vim in terminals
- [ ] use fzf for zsh tab completion
- [ ] remove hostname-prefixed remote bookmarks from jj without deleting them from the server
- [ ] `_gy` ↔ `_gyy` toggle via `become` produces wrong output
  - after `become`, the new function's output goes through the original function's post-processing pipeline
  - `_gy` expects hex operation IDs (`grep -o "[0-9a-f]\{12,\}"`), but `_jyy` returns change IDs (lowercase alpha via `_jj_log_fzf`)
  - possible fix: unify output format or move post-processing into the `become` target so each function owns its own output pipeline
  - files: `fzf/functions.sh/functions.sh` — `_jy()` (line ~263), `_jyy()` (line ~222)
- [ ] make zellij floating point as big and more importantly as wide as appropriate while leaving slight context
- [ ] stop amazon-vpn when the network changes
- [ ] use --impure for private-dotfiles instead of having to add commit and override the lock file every time
- [ ] run systemd for user from nix
- [ ] use https://github.com/neurosnap/zmx in just c instead of zellij

### Medium impact
- [ ] add squash feature to _gf
  - fzf shortcut (not enter) squashes the currently selected/highlighted file(s) from `@` into a target revision
  - opens `_gh` with a header explaining the squash context, minimise duplicated code
  - runs `jj squash --into <rev> -- <files>`
  - enter keeps current behaviour (output filenames)
- [ ] notify user when sync_repo merge has conflicts
  - Plan: set up Telegram bot for push notifications (ntfy is simpler but Telegram supports two-way); update notify-webhook to use Telegram
- [ ] how do I get notified with sync_all error
- [ ] share fzf config between shell (`fzf/functions.sh/functions.sh`) and nvim (`fzf.lua`)
  - fzf command-line parameters (including preview commands) are duplicated between the two
  - goal: single source of truth for shared fzf options/previews
  - direction: whichever is simpler (e.g. shared config file, shell script that both source, or generated opts)
- [ ] in nvim grep dialog, add a shortcut to toggle searching whole word+case sensitive
- [ ] review each nvim plugin and cleanup/modernise
- [ ] switch nix neovim module to `hm-generated.lua` approach
  - better: `xdg.configFile."nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;` + restore own `init.lua` with `require 'hm-generated'` at top
  - benefit: nix stops overwriting `init.lua`, `myinit.lua` can be merged back into `init.lua`, simpler config chain
  - see home-manager news 2026-01-25 and PR #8586/#8606
  - files: `home-manager.configsymlink/nvim.nix`, `nvim.configsymlink/myinit.lua`, `nvim.configsymlink/.gitignore`
- [ ] make sync_repo more readable
- [ ] automate nix flake updates and catch breaking changes early
  - flake inputs to keep updated: `nixpkgs` (nixos-unstable), `home-manager`, `nixGL`
  - consider: periodic `nix flake update` in `sync_all` or a separate timer, with notification on `home-manager switch` failure
  - consider: pin nixpkgs to a known-good rev and update intentionally, rather than always tracking unstable head
- [ ] fzf/functions.sh sets list width depending on the contents
- [ ] make ctrl-/ in fzf cycle through preview layouts: horizontal → vertical → hidden
  - fzf supports `change-preview-window` action to cycle layouts (e.g. `change-preview-window(right|down|hidden)`)
  - applies to `fzf_down()` in `fzf/functions.sh/functions.sh` and `fzf-zellij`
- [ ] use zellij floating pane for built-in fzf zsh widgets (ctrl-e, ctrl-f, ctrl-t, alt-c)
  - these use `fzf --zsh` generated widgets which call fzf directly, not through `fzf_down`/`fzf-zellij`
  - option A: override the fzf binary with a shell function that delegates to `fzf-zellij`
  - option B: set `FZF_TMUX=1` and `FZF_TMUX_OPTS` — but fzf-tmux doesn't work in zellij
  - option C: patch the generated widgets to call `fzf-zellij` instead of `fzf`
  - bindings: ctrl-e (`fzf-cd-widget`), ctrl-f (`_file_browse`), ctrl-t (`fzf-file-widget`), alt-c (`fzf-cd-widget` default)
  - files: `fzf/fzf.zsh` (env vars, widget sourcing), `fzf/functions.sh/key-binding.zsh` (custom bindings)
- [ ] Check if I can log in with fingerprint https://learn.omacom.io/2/the-omarchy-manual/77/fingerprint-fido2-authentication
- [ ] Check if I can sudo with security key https://learn.omacom.io/2/the-omarchy-manual/77/fingerprint-fido2-authentication

### Low impact
- [ ] zellij session picker: make it floating
- [ ] zellij session picker: show current session differently and make it not choosable
- [ ] zellij session picker: kills current pane, when the session is open in two zellij
- [ ] airline tabbar changes a lot when opening nvimtree
- [ ] there's no gap between ghostty vertically
- [ ] make battery notification sticky
- [ ] make copilot key work as super
- [ ] replace absolute path from xfce settings
- [ ] review remaining mini-nvim modules: mini.splitjoin (toggle single/multi-line), mini.bracketed (unified [/] nav)

## Architecture Overview

### Dotfiles Repo: ~/.dotfiles
- Home Manager config: `~/.dotfiles/home-manager.configsymlink/`
  - `flake.nix` — inputs: nixpkgs, home-manager, nixGL, private-dotfiles (`flake = false`); `mkHost` builds a `homeManagerConfiguration` from shared modules + extra modules; `nixFilesFrom` auto-loads root `.nix` files from private-dotfiles as modules; `hosts/*.nix` in private-dotfiles return `homeConfigurations` attrset fragments keyed by `username@static-hostname`; `nix.conf` `warn-dirty = false` required for home-manager auto-detection to work with jj (dirty tree warnings pollute `nix eval` stdout); `hm-session-vars.sh` sourced in `zshenv.symlink` (zsh not managed by home-manager)
  - `home.nix` — packages, unfree predicate (albert), battery-notify systemd timer (1min check, notify at 20%/10%)
  - `gnome.nix` — dconf settings (key repeat, mouse speed, cursor size 64, Korean input Sebeolsik 390, disable gnome-panel/desktop, empty gnome-panel layout as fallback), random-lockscreen systemd timer (daily wallpaper), gnome-flashback systemd drop-ins (xmonad session target requires gnome-flashback.target + service restart override)
  - `neovide.nix` — nixGL-wrapped neovide (GPU access on non-NixOS), font copying activation (JetBrains Mono + Nerd Font + Source Code Pro for neovide default fallback)
  - `nvim.nix` — neovim (default editor, vi/vim aliases), `initLua` sources `myinit.lua` (nix generates `init.lua` which overwrites `nvim.configsymlink/init.lua` on every switch — `init.lua` is gitignored), dev tool packages (LSPs, linters, formatters, DAP deps), rustaceanvim (Rust LSP); coverage table documents all tools per language
  - `xmonad.nix` — xmonad + contrib via nix 0.18, xfce4-panel + xfconf, xfconf dbus activation hook
  - `xdg.nix` — firefox-container desktop entry + mimeapps
  - `system-deps.sh` — detects package manager (dnf/yum preferred over apt-get for Amazon Linux); GNOME packages + session files guarded behind `gnome-session` check; keyd service guarded behind `/dev/input` check; loginctl enable-linger; ollama install guarded behind `$DISPLAY`/`$WAYLAND_DISPLAY` check (desktop only)
- xmonad config: `~/.dotfiles/xwindow/xmonad.symlink/xmonad.hs` (symlinked to ~/.xmonad/)
  - Build: `~/.xmonad/build` uses `$XMONAD_GHC` (set by nix xmonad wrapper, GHC with xmonad packages); falls back to PATH `ghc`; `set -euo pipefail` + `${1:?}` guard prevents creating misnamed binaries if output path is missing
  - HLS: `hie.yaml` + `.hie-bios` cradle points HLS to `$XMONAD_GHC` package db; HLS and GHC installed from same `haskellPackages` set in nvim.nix to keep versions in sync
  - ManageHook split into: `floatRules`, `browserRules`, `mailRules`, `editorRules`, `calendarRules`, `meetingRules`, `messengerRules`
  - `rescueOffscreenHook`: catches floating windows that move themselves offscreen (e.g. Zoom bug) via ConfigureEvent and snaps them back
  - `stripZoomFullscreenHook`: forces Zoom "Meeting" windows to stay tiled. Zoom renames the window to "Meeting" after ManageHook runs, so the event hook watches PropertyNotify on `_NET_WM_STATE`, `_NET_WM_NAME`, and `WM_NAME`; strips `_NET_WM_STATE_FULLSCREEN` and re-sinks via `W.sink`. Paired with `setEwmhFullscreenHooks`: fullscreen hook returns `idHook` for zoom+Meeting (default `doFullFloat` otherwise)
  - `monitorHotplugCfg` / `hideNSPWorkspace`: swaps NSP off visible screens after monitor hotplug
  - `greedyViewNoSwap`: workspace switch variant that swaps visible screens but not hidden
- keyd config: `~/.dotfiles/keyd/` (common, default.conf, kinesis.conf, thinkpad.conf — copied to /etc/keyd/ by system-deps.sh)
- input-remapper: `~/.dotfiles/input-remapper-2.configsymlink/` (symlinked to ~/.config/input-remapper-2/) — mice only
- jj config: `~/.dotfiles/jj.configsymlink/` (symlinked to ~/.config/jj/), user email in `private-dotfiles/jj/user.toml` (symlinked to `conf.d/user.toml`); revset aliases: `workspace_view()`, `unique(x, markers)`, `unique_boundary(x, markers)`; template aliases: `short_ago(ts)` (compact relative time: m/h/d/w/M/y), `fzf_oneline` (shortest change ID, no author/git-id, short relative time, bookmarks after description), `fzf_oneline_author` (same + author first name via `.split(" ").first()`, falls back to email local part)
- fzf config: `~/.dotfiles/fzf/fzf.zsh` — env vars, sources `fzf --zsh` dynamically, then sources custom key-binding.zsh, binds Ctrl-E to fzf-cd-widget
  - `fzf-zellij` — drop-in `fzf-tmux` equivalent for zellij; runs fzf in a floating pane with FIFO stdin streaming and temp file output; `FZF_ZELLIJ=1` env var prevents nested floating panes on `become` toggles and strips `--height`/`--min-height`; falls back to plain fzf outside zellij; panes closed explicitly (zellij `--close-on-exit` is unreliable)
  - `test_fzf_zellij.sh` — automated tests; run with `bash fzf/test_fzf_zellij.sh` inside a zellij session
  - `functions.sh/functions.sh` — jj-first/git-fallback functions; each `_g*` dispatcher delegates to `_j*` (jj) or `_git_*` (git); `_jb`/`_jt` previews use `unique_boundary()` revset; `_jb` preprocesses indented remote tracking lines; `_gh` shows upstream log, `_ghh` shows full ancestor log; toggles via `become`: `_jh`↔`_jhh` (ctrl-h), `_jb`↔`_jbb` (ctrl-b), `_jy`↔`_jyy` (ctrl-y); ctrl-o inserts empty revision after selected (`jj new --no-edit --after`), uses `transform:` colon form for error display; fzf query preserved across toggles via `{q}`→`--query`; line-number focus uses `result:pos(N+1)+unbind(result)`
  - `functions.sh/test_toggle_query.sh` — non-interactive test for toggle query/focus preservation, ctrl-o binding, and change ID extraction; run with `zsh fzf/functions.sh/test_toggle_query.sh`; file is read-only — only `chmod u+w` when the user explicitly allows it
  - `functions.sh/key-binding.zsh` — Ctrl-G sequences (`^G^F`, `^G^B`, etc.) bound in both viins and vicmd modes; `^G` rebound to undefined-key to prevent list-expand from swallowing the prefix; `^F` bound to `_file_browse`
  - All custom bindings must use `bindkey -M viins` and `bindkey -M vicmd` (vi mode)
- ghostty config: `~/.dotfiles/ghostty.configsymlink/` (symlinked to ~/.config/ghostty/)
  - `keybind = ctrl+{j,k,n,p}=text:\xNN` — sends legacy control codes; fixes zellij leaking kitty keyboard protocol sequences under rapid key repeat
  - terminfo: `pkgs.ghostty.terminfo` installed via home.nix; `~/.terminfo` symlinked to nix store terminfo dir so ncurses finds `xterm-ghostty` at process startup
- albert config: `~/.dotfiles/albert.configsymlink/` (symlinked to ~/.config/albert/)
- xfce4-panel config: `~/.dotfiles/xfce4.configsymlink/` (symlinked to ~/.config/xfce4/)
- gtk-3.0 config: `~/.dotfiles/gtk-3.0.configsymlink/` (symlinked to ~/.config/gtk-3.0/) — monospace tooltip font
- zellij config: `~/.dotfiles/zellij.configsymlink/` (symlinked to ~/.config/zellij/)
  - Normal mode: Alt-tab→Detach (triggers zellij-cycle session switch), Alt-s→fzf session picker, Alt-w→session manager (built-in plugin), Ctrl-tab→next tab, Alt-h/j/k/l→MoveFocus, Alt-Shift-h/j/k/l→MovePane
  - Move mode: Alt-Shift-h/l→move tab left/right, Ctrl-Shift-h/j/k/l→move pane
  - Config template: `CYCLE_SWITCH_CMD` placeholder in Alt-s binding, replaced by `zellij-cycle` via sed
- kiro config: `~/.dotfiles/kiro.filesymlink/` (individual files symlinked into ~/.kiro/) — agents/default.json (MCP TTS server, autoAllowReadonly), agents/no-mcp.json (no MCP servers, used by commit-msg to avoid orphaned processes), settings/cli.json (default agent: builder), bin/kiro-response (TTS fallback), bin/mcp-tts (MCP server for say/say_ko tools, kills previous playback via `setsid` + `kill -PGID`), bin/test_mcp_tts.sh (run with `bash bin/test_mcp_tts.sh`)
- Audio/brightness scripts: `~/.dotfiles/xwindow/bin/volume-osd`, `cycle-audio-output`, `cycle-audio-input`, `brightness-osd`
- Clipboard history: `copyq` (nix) — systemd user service, xmonad Super+V runs `copyq toggle`
- Weather script: `~/.dotfiles/xwindow/bin/weather-genmon` — wttr.in JSON API, python3 parser; 🌙 after sunset / before sunrise; tooltip: current + hourly + 3-day forecast
- System monitor: `~/.dotfiles/xwindow/bin/sysmon-genmon` — sparkline graphs (CPU, MEM, IO, NET, BAT) via xfce4-genmon-plugin; `color_bar` supports inverted mode for metrics where high=good (battery); history in `/tmp/sysmon-history`, 8 samples
- Battery indicator: `~/.dotfiles/xwindow/bin/battery-genmon` — standalone battery genmon (fallback; battery also in sysmon-genmon)
- Lock screen: `~/.dotfiles/xwindow/bin/random-lockscreen`
- Sync scripts: `~/.dotfiles/script/sync_all` (all jj/git repos via plocate, triggered by `sync-repos.timer`), `sync_repo` (single repo)
  - `sync_all` iterates `.jj`/`.git` markers under `$HOME` from plocate, filters noise paths; calls `notify-webhook` on failure (currently disabled — awaiting Telegram bot)
  - `sync_repo` jj path: per-repo `flock`; exits early if no `hj` remote; single `jj log -r @` call snapshots atomically; runs `jj new` on non-empty OR empty-merge `@`; describes with AI commit message (via `commit-msg` with `VERBOSE=1`); uses `if(description, ...)` for empty description check (jj has no `description.is_empty()`)
  - Workspace name: matched by current `@` commit_id against `jj workspace list`
  - Auto-merge: fetches tracking branches, merges local bookmark forward, pushes to hj
  - Prefixed bookmarks: delete+push via raw git (`hostname/bookmark`); single `ls-remote` per run, skips if unchanged
  - Workspace snapshot bookmark (Step 0): creates `hostname/workspace` bookmark at `PUSH_REV`, force-pushes via raw git
- Commit message generator: `~/.dotfiles/bin/commit-msg` — kiro-cli first (`--agent no-mcp`, stdin piping, 30s timeout), ollama + qwen2.5-coder:3b fallback (5s health check, started on demand), file-list final fallback; jj-first/git-fallback; `VERBOSE=1` enables detailed output
- Notifications: `~/.dotfiles/bin/notify-webhook` — currently disabled (exit 0), awaiting Telegram bot
- Private dotfiles: `~/.dotfiles/private-dotfiles/` — gitignored colocated jj/git repo; added as `git+file://` flake input; stores machine-specific config (host configs, tokens, webhook URLs), Brazil JDK setup, and per-host `homeConfigurations`; zsh `**/*.zsh` glob auto-sources; `install.sh` files run by `script/install`; `ssh.filesymlink/` provides SSH host aliases; see `private-dotfiles/AGENTS.md` for Brazil, flake input details, and how to add a new host
- Zellij session cycler: `~/.dotfiles/bin/zellij-cycle` — wraps `zellij attach --create` in a loop; on detach cycles to next active session; generates per-instance config via sed; supports session names with spaces
- Zellij session picker: `~/.dotfiles/bin/zellij-pick-session` — fzf-based session picker with Alt-s cycling; closes own pane and runs callback detached via setsid
- plocate updatedb: `~/.dotfiles/script/updatedb` — every 3min, notifies if slow
- Battery notify: `~/.dotfiles/script/battery-notify` — systemd timer every 1min, notifies at ≤20% (normal) and ≤10% (critical), once per threshold, resets on charge
- zsh config: standalone files in `~/.dotfiles/zsh/` (zprezto fully removed)
  - `zshenv.symlink` — sets `$DOTFILES_ROOT` via `%N`, sources `*/path.zsh`
  - `zshrc.symlink` — sources `**/*.zsh` (excludes path.zsh, completion.zsh); completion.zsh sourced last
  - `environment.zsh` — smart URLs, setopt, jobs, colored man pages
  - `terminal.zsh` — window/tab/pane titles via precmd/preexec
  - `editor.zsh` — vi mode, dot expansion, key bindings, vim-surround, text objects
  - `history.zsh` — 10M entries, dedup, HIST_IGNORE_SPACE disabled
  - `directory.zsh` — auto_cd, auto_pushd, extended_glob, no clobber
  - `utility.zsh` — correction, nocorrect/noglob aliases, colored ls/grep
  - `completion.zsh` — compinit, caching, fuzzy match, case-insensitive, menu select, AWS bashcompinit
  - `syntax-highlighting.zsh` — fast-syntax-highlighting (nix)
  - `autosuggestions.zsh` — zsh-autosuggestions (nix)
  - `git.zsh` — git aliases, no git-flow
  - `gnu-utility.zsh` — g-prefixed GNU utils on macOS, no-op on Linux
  - `p10k.zsh` — powerlevel10k (nix) + user config
- zsh functions: `~/.dotfiles/zsh/functions/c` (copy), `p` (paste), `o` (open), `say_done` (TTS notification), `ju` (jj unique) — Wayland/X11 aware
- TTS: `~/.dotfiles/bin/say` — piper-tts with en_GB-alba-medium voice, auto-downloads model; override voice with `$PIPER_MODEL`
  - `say_done` calls `say` to announce when commands >10s finish; only on desktop machines; runs in subshell
- TTS (Korean): `~/.dotfiles/bin/say-ko` — edge-tts with ko-KR-SunHiNeural voice (requires internet)
  - Default rate: +50%, override with `$EDGE_TTS_RATE`; override voice with `$EDGE_TTS_VOICE`

### Neovim Dev Tooling
- Config: `~/.dotfiles/nvim.configsymlink/` (symlinked to ~/.config/nvim; also ~/.vim via vim.symlink → nvim.configsymlink)
- Plugin management: all plugins installed via home-manager `programs.neovim.plugins`; no submodules
- Config loading: nix generates `init.lua` (lua paths + `myinit.lua` content via `initLua`); `myinit.lua` sources `vimrc.symlink`; `vimrc.symlink` sources `myvimrc`; `myvimrc` runs `runtime! vimrcs/*.vimrc`, `vimrcs/*.nvimrc`, `vimrcs/*.lua`; `init.lua` is gitignored (nix-generated); nvim only loads `init.lua` (not `init.vim`/vimrc) when both exist
- Logs: `~/.vim-messages.log` (nvim messages), `~/.local/state/nvim/lsp.log` (LSP), `~/.local/state/nvim/mason.log` (Mason)
- Project-local config: `myvimrc` sources `.nvim.lua` from cwd or ancestors on `BufEnter`, per-buffer dedup
- Per-language setup: `vimrcs/my-<lang>.lua` — LSP via `vim.lsp.config.NAME = { ... }` + `vim.lsp.enable('NAME')`, DAP, filetype-specific config
  - my-awk, my-bash (bash/sh only — no zsh LSP), my-cmake, my-cpp, my-css, my-docker, my-glsl, my-haskell, my-html, my-java, my-jinja, my-js (js/ts), my-json, my-just, my-kotlin, my-lua, my-markdown, my-nim, my-nix, my-python, my-rust (rustaceanvim, not vim.lsp.config), my-sql, my-text, my-toml, my-vim, my-xml, my-yaml
- Shared config: `vimrcs/lsp.lua` (keymaps incl. `<leader>e` floating diagnostic), `vimrcs/nvim-dap.lua` (codelldb + shared DAP keymaps), `vimrcs/nvim-lint.lua` (linter-by-filetype config)
- Autoformat: `vimrcs/my-autoformat.lua` (format on autosave via CursorHold/BufLeave/FocusLost, checks `vim.b.autoformat_fts`); per-project `.nvim.lua` sets `vim.b.autoformat_fts`
- Completion: `vimrcs/blink-cmp.lua` — blink.cmp
- DAP UI: `vimrcs/nvim-dap-ui.lua` — auto-open/close debug UI, F7 toggle
- Git gutter: `vimrcs/gitsigns.lua` — gitsigns.nvim with jj support (diffs against `@-` via `change_base`), `]c`/`[c` hunk nav, `<leader>hp` preview, `<leader>hr` reset, `<leader>hb` blame (no staging — safe for jj)
- LSP enhancements: `vimrcs/lsp_signature.lua` — inlay hints + auto signature help
- LSP progress: `vimrcs/fidget.lua` — fidget.nvim
- Treesitter textobjects: `vimrcs/nvim-treesitter.lua` — `vaf`/`vif` function, `vac`/`vic` class, `vaa`/`via` parameter, `]f`/`[f` function nav, `]a`/`[a` parameter nav, `<leader>a`/`<leader>A` swap parameter; manual global keymaps (buffer-local may not attach)
- mini.ai: `vimrcs/mini-ai.lua` — extended a/i textobjects; treesitter-powered `F` (function def), `c` (class); pattern-based `f`/`a` work better than treesitter for C++ templates
- nvim-surround: `vimrcs/nvim-surround.lua` — `ys`/`ds`/`cs` keybindings (matches zsh vi-mode surround)
- Treesitter incremental selection: `<C-e>` init/expand node, `<C-d>` shrink node (manual global keymaps)
- Indent detection: vim-sleuth (auto-detects tabstop/shiftwidth)
- Limelight: `my-text.lua` — auto-enabled for text, markdown, rst, org, asciidoc, tex, mail, gitcommit
- Table mode: `my-markdown.lua` — `silent! TableModeEnable` on markdown FileType
- fzf-lua: `vimrcs/fzf.lua` — `<leader>f` jj/git tracked files (ctrl-g toggles submodule files, ctrl-f toggles all files, query preserved), `<leader>F` all files, `<C-g><C-f>` changed files, ctrl-n/p preview scroll
- Font: `gvimrc` — JetBrains Mono Thin:h11 (neovide guifont); Source Code Pro must be installed for neovide fallback
- Linting: `nvim-lint` runs CLI linters (checkmake, hadolint, checkstyle, markdownlint-cli2, statix, deadnix) on save
- Tool installation: prefer nix (nvim.nix) over Mason; Mason only for DAPs not in nixpkgs (bash-debug-adapter, codelldb, kotlin-debug-adapter, java-debug-adapter, debugpy); `bash` package in nvim.nix required by Mason installer

### Key Remapping Stack
- **keyd** (`~/.dotfiles/keyd/`, system daemon, four files):
  - `common` — shared bindings: CapsLock→Ctrl (tap→Esc), Super tap→prog1 (albert), Alt_L tap→prog2 (ghostty1), Alt_R tap→prog3 (ghostty2), Ctrl_R tap→apostrophe, Pause/ScrollLock/PrtSc→volume keys; keyd v2.6.0 maps prog1/2/3 to f21/f22/f23 (evdev 191/192/193)
  - `default.conf` — all keyboards except device-specific, includes common
  - `kinesis.conf` — Kinesis Advantage2 (`29ea:0102`), Mac-mode key swaps, includes common
  - `thinkpad.conf` — ThinkPad (`0001:0001:09b4e68d`), Copilot key → tap: Albert, hold: Super, includes common
- **input-remapper** (per-device, systemd daemon):
  - Logitech USB Optical Mouse: left-handed
  - ExpertBT5.0 Mouse (Kensington): left-handed + BTN_SIDE→Super+Shift+C (close window) + BTN_LEFT→Super+Tab
- See `~/.dotfiles/keyd/README.md` for full key remapping documentation

### xmonad Key Bindings
- Super tap → Albert toggle
- Alt_L tap → ghostty scratchpad 1 (adaptive half-screen)
- Alt_R tap → ghostty scratchpad 2 (adaptive half-screen)
- Volume keys → volume-osd script (dzen2 FIFO-based)
- Brightness keys → brightness-osd script (5% steps ≤20%, 10% above)
- Super+VolumeUp → cycle audio output
- Super+VolumeDown → cycle audio input
- Super+N → W.view (focus workspace without swapping monitors)
- Ctrl+Super+N → W.greedyView (bring workspace to current monitor)
- Super+Shift+Enter → gnome-terminal
- Super+` / Super+= → next screen
- Super+0 → next empty workspace
- Super+V → `copyq toggle` (clipboard history)

### Audio OSD System
- Three independent dzen2 popups using FIFOs (no flicker on rapid presses):
  - volume-osd: green, y=100; audio-out-osd: cyan, y=210; audio-in-osd: pink, y=320
- Dimensions scale with Xft.dpi (base: x=100, w=1240, h=100 at 96dpi)
- Font: JetBrainsMono Nerd Font, size 36 bold (not scaled — font respects DPI natively)
- Auto-hide after 2-3 seconds

### Brightness OSD
- brightness-osd: yellow, y=430 — same dzen2 FIFO pattern as audio OSD
- Uses brightnessctl (nix), 5% steps ≤20%, 10% above

### Scratchpad System
- Two independent ghostty instances (scratchpad1, scratchpad2), each running `zellij-cycle` with its own default session
- `scratchpadToggle`: focused→hide, visible elsewhere→focus, hidden→bring to current workspace+float+focus
- `adaptiveFloat` manage hook: landscape→side-by-side halves, portrait→stacked halves, 2% margins
- `refloatAdaptive`: repositions scratchpad to match current screen orientation on every show

### Zoom Notification
- `zoom_linux_float_message_reminder`: floats on all workspaces without stealing focus
- Known bug: with multi-monitor, moving mouse toward notification can trigger workspace swap (focus-follows-mouse + `copyToAll` interaction)

### Known Issues / Constraints
- keyd v2.5.0 parser fails on UTF-8 box-drawing characters in default.conf comments (works in kinesis.conf)
- Nix-installed GTK apps don't show in xfce4-panel systray (library mismatch)
- xfconf needs dbus service registration (handled by Home Manager activation)
- Fonts need copying to ~/.local/share/fonts for neovide/dzen2 (nix font paths not read by skia/dzen2)
- User is on LDAP (can't chsh), $SHELL is bash, zsh started via exec from .bashrc
- AltGr on laptop keyboard doesn't map to Right Alt (needs keyd per-device config)
- gnome-flashback "Notifications" tray icon doesn't respond to clicks (no GNOME Shell notification panel)
- fzf-lua: `fzf_opts['--bind']` overwritten by `create_fzf_binds` — custom fzf binds must go through `actions` table or `keymap.fzf`, not `fzf_opts`
- fzf-lua: `ctrl-o` intercepted by neovim terminal mode; `ctrl-g` is fzf's default abort but can be overridden via Lua actions
- fzf `--bind`: `transform(...)` parenthesis form breaks with nested parens — use colon form `transform:` instead
- nvim-treesitter: `ensure_installed` + `auto_install` fail trying to write to nix store; use `auto_install = false` and `ensure_installed = {}`; nvim-treesitter 1.0 removed `nvim-treesitter.configs` module — `nvim-treesitter.lua` uses pcall for compat
- zsh vi mode: custom zle widget bindings must use `bindkey -M viins` and `bindkey -M vicmd` explicitly
- zsh fzf: `source <(fzf --zsh)` must come before custom bindkeys that reference fzf widgets; `zshrc.symlink` globs alphabetically — don't put static copies of fzf scripts in the glob path
- zellij + kitty keyboard protocol: under rapid key repeat, zellij occasionally fails to parse CSI u sequences; worked around by sending legacy control codes from ghostty for ctrl-j/k/n/p
- C++ treesitter textobjects: `#make-range!` directives can silently fail; `@function.outer` misses lambdas; mini.ai pattern-based `f`/`a` is more reliable for C++
- Push notifications: Google Chat webhooks blocked by org admin; Slack requires workspace admin; KakaoTalk "나에게 보내기" doesn't trigger push; Telegram bot or ntfy.sh are the viable options
- fzf `become` toggle output mismatch: `_gy`↔`_gyy` output goes through wrong post-processing pipeline; `_gh`↔`_ghh` unaffected (same output format)
- kiro-cli can't receive prompts as command-line arguments (hangs on large input) — use stdin piping
- kiro-cli `--agent default` spawns MCP servers that become orphaned on exit — use `--agent no-mcp` for scripted use
- Cloud desktop (Amazon Linux): `apt` in PATH is JDK's Annotation Processing Tool, not Debian apt; `system-deps.sh` checks dnf/yum first; linuxbrew `dbus-run-session` has broken config — `gnome.nix` conditionally skipped when `/usr/bin/dconf` absent
- Nix flakes and gitignored files: flakes copy git-tracked source tree to store; `git+file://` with a separate repo is the only way to include gitignored content without `--impure`
- Nix flakes `warn-dirty`: jj always has uncommitted changes; `nix eval` outputs warning to stdout, breaking home-manager's string comparison; fix: `warn-dirty = false` in `~/.config/nix/nix.conf`

### Monitors
- Current: 3 monitors — eDP-1 (1920x1200 laptop), DP-1 (3440x1440 ultrawide), DP-3 (1440x2560 portrait); varies by location
- Multi-monitor: configurations change frequently; `rescreenHook` with `hideNSPWorkspace` swaps NSP off visible screens after hotplug
- xfce4-panel bottom bar: 48px, using avoidStruts

### Sound System
- PipeWire with PulseAudio compatibility (pipewire-pulse)
- wpctl for device switching, amixer for volume control
- pavucontrol installed for GUI mixer
