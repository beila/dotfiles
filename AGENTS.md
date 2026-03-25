# Dotfiles Workstation Setup — Context for AI Agent

## Agent Instructions

See `.kiro/steering/instructions.md` for the canonical, always-loaded instruction set.
Summary (keep in sync with the steering file):

- Always use the fastest tool available for the job (e.g. `ripgrep` over `grep`, `fd` over `find`)
- If the preferred tool is not installed, ask whether to install it (via home-manager in `home.nix`) or run it ad-hoc with `nix run nixpkgs#<pkg>`
- TTS: at the end of every response, call the `say_ko` MCP tool with a Korean translation of a full summary of what was done or answered
- Before any tool call that requires user permission, call `say_ko` first starting with "도구 실행합니다" followed by a brief description of what's about to be done
- After making changes that affect architecture, conventions, or behavior described in `AGENTS.md` or `README.md`, update those docs to reflect the new state
- Never run `sudo` commands directly. Instead, copy the command to the clipboard (`xclip -selection clipboard`) and ask the user to run it. Use full paths for binaries not in root's PATH (e.g. `$(which keyd)`)
- These instructions persist for the entire session. If the agent violates any rule, it must stop and correct immediately

## TODO List

- [x] **Battery indicator** — genmon plugin (`battery-genmon` script), replaced xfce4-power-manager
- [x] **Git commit message generator** — ollama + qwen2.5-coder:3b, `~/.dotfiles/bin/commit-msg`
- [x] **jj periodic tasks** — auto-fetch, background operations
   - `sync_all` runs every 10min via systemd timer (randomized delay, low priority, flock)
   - `jj_snapshot_all` snapshots all jj repos found via plocate
   - `commit-msg` generates AI commit messages via ollama + qwen2.5-coder:3b
- [ ] **universal Copy/paste key** — copy/paste keys that work the same way in x window app, terminals, zellij, neovide, (neo)vim in terminals
- [x] **Auto-merge to main on sync** — sync_dotfiles fetches tracking branches, merges local bookmark forward, pushes to hj (no force)
- [x] **jj empty changes** — sync_dotfiles skips commit/describe when current change is empty, but still pushes bookmarks
- [x] **Ghostty unnecessary resizing** — scratchpadToggle no longer refloats when just focusing a visible scratchpad
- [x] **Fix open-in-container** — was using gawk-specific `gensub()` on mawk; fixed with POSIX awk + longest suffix matching
- [x] kill tmux server and remove zsh integration
- [x] zoom notification on all workspace
- [x] fix sync_all creating "```commit" or "```markdown" description
- [x] zellij session should outlive ghostty
- [ ] there's no gap between ghostty vertically
- [ ] fix lockscreen-related error message
- [ ] can't type hangul in zellij/ghostty
- [ ] add local settings file into a non-public VCS
- [x] run tts when asking for permission in kiro
- [x] change neovide font back
- [x] install nvim plugins with home manager and remove submodules (36 plugins moved to nix, 10 remain as submodules not in nixpkgs)
- [ ] review each nvim plugin and cleanup/modernise
- [x] keybindings for session/tab/pane changes in zellij
- [x] different zellij sessions for each scratchpad
- [ ] add a script to add a new git-worktree/jj-workspace
- [x] use kiro first for commit message generation
- [ ] ollama server started on demand
- [ ] how do I get notified with sync_all error
- [ ] notify user when sync_dotfiles merge has conflicts
- [ ] fix sync_dotfiles leaving orphan empty change after each run
   - After sync, `@` ends up on an immutable commit (master). Next run, jj creates an extra empty change (`pmxrolzz`) because it can't snapshot into an immutable `@`.
   - `jj new` on immutable `@` creates two empty commits instead of one.
   - `CHANGE_ID` is captured before `jj new`, so it points to the immutable commit, not the new mutable one. `jj describe` then says "Nothing changed".
   - The `jj git push`/`jj git import` may also rebase `@`, collapsing the empty intermediate and leaving `@` directly on master again.
   - Need to understand: why does `@` end up on master (immutable) between runs? The previous run's `jj new` should leave `@` on a fresh mutable change above master.
- [ ] make sync_dotfiles more readable
- [ ] add split feature to _gf
- [ ] zellij session picker: kills current pane, when the session is open in two zellij
- [ ] zellij session picker: show current session differently and make it not choosable
- [ ] zellij session picker: make it floating
- [x] replace remaining zprezto modules with standalone zsh config (history, directory, utility, completion, syntax-highlighting, git, gnu-utility, autosuggestions, osx) and remove zprezto
- [ ] use fzf for zsh tab completion
- [x] autoformat: move BufWritePre logic to .nvim.lua (per-project), keep update/autosave formatting in my-autoformat.lua (central)
- [ ] finish reviewing kickstart-modular.nvim files (options.lua, lsp-setup.lua, telescope-setup.lua, custom/) and remove kickstart-modular.nvim
- [ ] is it worth installing tpope/vim-markdown to get the latest change
- [ ] which-key blocks using single key such as ctrl-g or }
- [ ] airline tabar changes a lot when opening nvimtree
- [ ] in jj files dialog, ctrl-g for ignored files, some other key for submodule

## Architecture Overview

### Dotfiles Repo: ~/.dotfiles
- Home Manager config: `~/.dotfiles/home-manager.configsymlink/`
  - `flake.nix` — modules: gnome.nix, home.nix, neovide.nix, nvim.nix, xdg.nix, xmonad.nix
  - `home.nix` — packages, unfree predicate (albert), battery-notify systemd timer (1min check, notify at 20%/10%)
  - `gnome.nix` — dconf settings (key repeat, mouse speed, cursor size 64, Korean input Sebeolsik 390, disable gnome-panel/desktop), random-lockscreen systemd timer (daily wallpaper), gnome-flashback systemd drop-ins (xmonad session target requires gnome-flashback.target + service restart override)
  - `neovide.nix` — nixGL-wrapped neovide, font copying activation (JetBrains Mono + Nerd Font)
  - `nvim.nix` — neovim (default editor, vi/vim aliases), dev tool packages (LSPs, linters, formatters, DAP deps); coverage table documents all tools per language
  - `xmonad.nix` — xmonad + contrib via nix 0.18, xfce4-panel + xfconf, xfconf dbus activation hook
  - `xdg.nix` — firefox-container desktop entry + mimeapps
  - `system-deps.sh` — apt packages (ibus-hangul, gnome-session-flashback) + session file installs + keyd service setup
- xmonad config: `~/.dotfiles/xwindow/xmonad.symlink/xmonad.hs` (symlinked to ~/.xmonad/)
- keyd config: `~/.dotfiles/keyd/` (common, default.conf, kinesis.conf, thinkpad.conf — copied to /etc/keyd/ by system-deps.sh)
- input-remapper: `~/.dotfiles/input-remapper-2.configsymlink/` (symlinked to ~/.config/input-remapper-2/) — mice only
- jj config: `~/.dotfiles/jj.configsymlink/` (symlinked to ~/.config/jj/), local email in conf.d/local.toml (gitignored)
- fzf functions: `~/.dotfiles/fzf/functions.sh/functions.sh` — jj-first/git-fallback Ctrl-G bindings
- ghostty config: `~/.dotfiles/ghostty.configsymlink/` (symlinked to ~/.config/ghostty/)
- albert config: `~/.dotfiles/albert.configsymlink/` (symlinked to ~/.config/albert/)
- xfce4-panel config: `~/.dotfiles/xfce4.configsymlink/` (symlinked to ~/.config/xfce4/)
- gtk-3.0 config: `~/.dotfiles/gtk-3.0.configsymlink/` (symlinked to ~/.config/gtk-3.0/) — monospace tooltip font
- zellij config: `~/.dotfiles/zellij.configsymlink/` (symlinked to ~/.config/zellij/)
  - Normal mode keybindings: Alt-tab→Detach (triggers zellij-cycle session switch), Alt-s→fzf session picker (via CYCLE_SWITCH_CMD template), Ctrl-tab→next tab, Alt-h/j/k/l→MoveFocus, Alt-Shift-h/j/k/l→MovePane
  - Move keybindings: Alt-Shift-h/l→move tab left/right, Ctrl-Shift-h/j/k/l→move pane
  - Config template: `CYCLE_SWITCH_CMD` placeholder in Alt-s binding, replaced by `zellij-cycle` via sed with per-instance callback
- kiro config: `~/.dotfiles/kiro.filesymlink/` (individual files symlinked into ~/.kiro/) — agents/default.json (MCP TTS server, autoAllowReadonly), settings/cli.json (default agent: builder), bin/kiro-response (TTS fallback), bin/mcp-tts (MCP server for say/say_ko tools)
- Audio/brightness scripts: `~/.dotfiles/xwindow/bin/volume-osd`, `cycle-audio-output`, `cycle-audio-input`, `brightness-osd`
- Weather script: `~/.dotfiles/xwindow/bin/weather-genmon` — wttr.in-based, shown via xfce4-genmon-plugin
- Lock screen: `~/.dotfiles/xwindow/bin/random-lockscreen`
- Keyboard hotplug: keyd handles remapping at evdev level (no hotplug workaround needed)
- Sync scripts: `~/.dotfiles/script/sync_all` (all repos), `sync_dotfiles` (single repo), `jj_snapshot_all` (snapshot all jj repos via plocate)
  - `sync_dotfiles` jj path: skips empty changes (commit/describe only), describes with AI commit message, always pushes bookmarks
  - Auto-merge: fetches tracking branches, merges local bookmark forward via jj (no force), pushes to hj
  - Prefixed bookmarks: force-pushed via raw git (`hostname/bookmark`) for per-device backup; other devices' prefixes untouched
  - Requirements documented as comments in script: (1) commit with AI message if non-empty, (2) force-push all bookmarks with hostname prefix, (3) safely merge and push tracked bookmark
- Commit message generator: `~/.dotfiles/bin/commit-msg` — kiro-cli first (cloud model, `--agent default`), ollama + qwen2.5-coder:3b fallback; jj-first/git-fallback; strips ANSI codes, cursor sequences, and spinner carriage returns
- Zellij session cycler: `~/.dotfiles/bin/zellij-cycle` — wraps `zellij --config <generated> attach --create` in a loop; on detach cycles to next active session; generates per-instance config via sed (CYCLE_SWITCH_CMD→callback with pick file + pkill); supports session names with spaces (mapfile); temp files: `/tmp/zellij-cycle-{pick,pid,config}.$$`
- Zellij session picker: `~/.dotfiles/bin/zellij-pick-session` — fzf-based session picker with Alt-s cycling; accepts generic callback ($*); closes own pane and runs callback detached via setsid
- plocate updatedb: `~/.dotfiles/script/updatedb` — every 3min, notifies if slow
- Battery notify: `~/.dotfiles/script/battery-notify` — systemd timer every 1min, notifies at ≤20% (normal) and ≤10% (critical), once per threshold, resets on charge
- zsh config: standalone files in `~/.dotfiles/zsh/` (zprezto fully removed)
  - `zshenv.symlink` — sets `$DOTFILES_ROOT` via `%N` (works in all contexts), sources `*/path.zsh`
  - `zshrc.symlink` — sources `**/*.zsh` (excludes path.zsh, completion.zsh); completion.zsh sourced last
  - `environment.zsh` — smart URLs, setopt, jobs, colored man pages (from zprezto)
  - `terminal.zsh` — window/tab/pane titles via precmd/preexec, Apple Terminal support (based on zprezto)
  - `editor.zsh` — vi mode, dot expansion, key bindings, vim-surround, text objects (based on zprezto)
  - `history.zsh` — history options, 10M entries, dedup, HIST_IGNORE_SPACE disabled
  - `directory.zsh` — auto_cd, auto_pushd, extended_glob, no clobber (from zprezto)
  - `utility.zsh` — correction, nocorrect/noglob aliases, colored ls/grep, helper functions (from zprezto, partial)
  - `completion.zsh` — compinit, caching, fuzzy match, case-insensitive, menu select, AWS bashcompinit (from zprezto)
  - `syntax-highlighting.zsh` — fast-syntax-highlighting (installed via nix `zsh-fast-syntax-highlighting`)
  - `autosuggestions.zsh` — zsh-autosuggestions (installed via nix)
  - `git.zsh` — git aliases, no git-flow (from zprezto)
  - `gnu-utility.zsh` — g-prefixed GNU utils on macOS, no-op on Linux (from zprezto)
  - `p10k.zsh` — powerlevel10k (installed via nix `zsh-powerlevel10k`) + user config
  - Nix zsh packages: zsh-completions, nix-zsh-completions, zsh-powerlevel10k, zsh-fast-syntax-highlighting, zsh-autosuggestions
- zsh functions: `~/.dotfiles/zsh/functions/c` (copy), `p` (paste), `o` (open), `say_done` (TTS notification) — Wayland/X11 aware
- TTS: `~/.dotfiles/bin/say` — piper-tts with en_GB-alba-medium voice, auto-downloads model on first run
  - `say_done` calls `say` to announce when commands >10s finish (via `add-zsh-hook` in `zsh/config.zsh`); runs in subshell `(say_done &)` to suppress background PID output
  - Override voice with `$PIPER_MODEL`
- TTS (Korean): `~/.dotfiles/bin/say-ko` — edge-tts with ko-KR-SunHiNeural voice (requires internet)
  - Default rate: +50%, override with `$EDGE_TTS_RATE`
  - Override voice with `$EDGE_TTS_VOICE` (available: ko-KR-SunHiNeural, ko-KR-InJoonNeural, ko-KR-HyunsuMultilingualNeural)

### Neovim Dev Tooling
- Config: `~/.dotfiles/vim.symlink/` (symlinked to ~/.vim/, also ~/.config/nvim via init.lua)
- Plugin management: most plugins installed via home-manager `programs.neovim.plugins`; remaining submodules in `pack/bundles/start/` (cscope_maps, jsonc, nvim-treesitter, SrcExpl, tabline.vim, tasklist, tree-sitter-cmake, tree-sitter-just, vim-log-highlighting, vim-scimark)
- Config loading: `myvimrc` runs `runtime! vimrcs/*.vimrc`, `vimrcs/*.nvimrc`, `vimrcs/*.lua`
- Project-local config: `myvimrc` sources `.nvim.lua` from cwd or ancestors on `BufEnter` (via `vim.schedule` after lcd), per-buffer dedup
- Per-language setup: `vimrcs/my-<lang>.lua` — LSP, DAP, filetype-specific config
  - my-awk.lua, my-cmake.lua, my-cpp.lua, my-css.lua, my-docker.lua, my-glsl.lua
  - my-haskell.lua, my-html.lua, my-java.lua, my-jinja.lua, my-js.lua (js/ts)
  - my-json.lua, my-just.lua, my-kotlin.lua, my-lua.lua, my-markdown.lua
  - my-nim.lua, my-nix.lua, my-python.lua, my-rust.lua, my-sql.lua
  - my-text.lua, my-toml.lua, my-vim.lua, my-xml.lua, my-yaml.lua
  - my-bash.lua (bash/sh only — zsh excluded, no zsh LSP available)
- Shared config: `vimrcs/lsp.lua` (keymaps incl. `<leader>e` floating diagnostic), `vimrcs/nvim-dap.lua` (codelldb + shared DAP keymaps), `vimrcs/nvim-lint.lua` (linter-by-filetype config)
- Autoformat: `vimrcs/my-autoformat.lua` (format on autosave via CursorHold/BufLeave/FocusLost, checks `vim.b.autoformat_fts`); per-project `.nvim.lua` sets `vim.b.autoformat_fts` and buffer-local `BufWritePre` for explicit `:w`
  - Example: `~/dev/i/.nvim.lua` — autoformat for cpp, c, typescript, javascript
- Completion: `vimrcs/nvim-cmp.lua` — nvim-cmp with cmp-nvim-lsp source, no snippets (based on kickstart)
- DAP UI: `vimrcs/nvim-dap-ui.lua` — auto-open/close debug UI, F7 toggle
- Git gutter: `vimrcs/gitsigns.lua` — gitsigns.nvim with jj support (diffs against `@-` via `change_base`), `]c`/`[c` hunk nav, `<leader>hp` preview, `<leader>hr` reset, `<leader>hb` blame (no staging — safe for jj)
- LSP enhancements: `vimrcs/lsp_signature.lua` — inlay hints (neovim ≥ 0.10) + auto signature help (lsp_signature.nvim)
- LSP progress: `vimrcs/fidget.lua` — fidget.nvim notifications
- Keybind discovery: `vimrcs/which-key.lua` — which-key.nvim popup
- Treesitter textobjects: configured in `vimrcs/nvim-treesitter.lua` — `vaf`/`vif` function, `vac`/`vic` class, `vaa`/`via` parameter, `]f`/`[f` function nav, `]a`/`[a` parameter nav
- Indent detection: vim-sleuth (auto-detects tabstop/shiftwidth, no config)
- Yank highlight: `init.lua` — brief highlight on yank (from kickstart)
- Limelight: `my-text.lua` — auto-enabled for text, markdown, rst, org, asciidoc, tex, mail, gitcommit; per-buffer (BufEnter/BufLeave toggle)
- Table mode: `my-markdown.lua` — `silent! TableModeEnable` on markdown FileType (suppresses echo noise)
- fzf-lua: `vimrcs/fzf.lua` — `<leader>f` jj/git tracked files (ctrl-g toggles submodule files, query preserved across toggle, `vimrcs/jj-file-list-all` helper script), `<leader>F` all files (incl. gitignored), `<C-g><C-f>` jj/git changed files, ctrl-n/p preview scroll
- Font: `gvimrc` — JetBrains Mono Thin:h11 (neovide guifont)
- Linting: `nvim-lint` plugin runs CLI linters (checkmake, hadolint, checkstyle, markdownlint-cli2, statix, deadnix) on save
- Tool installation: prefer nix (nvim.nix) over Mason; Mason only for DAPs not in nixpkgs
  - Coverage table in `nvim.nix` documents all tools per language with install location
  - Mason-only: bash-debug-adapter, codelldb, kotlin-debug-adapter, java-debug-adapter, debugpy
  - `bash` package in nvim.nix required by Mason installer

### Key Remapping Stack
- **keyd** (`~/.dotfiles/keyd/`, system daemon, four files):
  - `common` — shared bindings (included by all configs): CapsLock→Ctrl (tap→Esc), Super tap→prog1 (XF86Launch1, albert), Alt_L tap→prog2 (XF86Launch2, ghostty1), Alt_R tap→prog3 (XF86Launch3, ghostty2), Ctrl_R tap→apostrophe, Pause/ScrollLock/PrtSc→volume keys
  - `default.conf` — all keyboards except those with device-specific configs, includes common
  - `kinesis.conf` — Kinesis Advantage2 (`29ea:0102`), aliases for Mac-mode key swaps (LCtrl→Super, LAlt→Esc, End→LAlt, PgDn→RAlt, apostrophe→RCtrl, backslash→Tab, PgUp→backslash, RMeta→Esc, RCtrl→Super, 102nd→backslash), includes common
  - `thinkpad.conf` — ThinkPad laptop (`0001:0001:09b4e68d`), Copilot key (Meta+Shift+F23 hardware combo) → tap: Albert (prog1), hold: Super modifier, long hold: noop (timeout prevents repeated toggling), includes common
- **input-remapper** (per-device, systemd daemon):
  - Logitech USB Optical Mouse: left-handed (swap left/right)
  - ExpertBT5.0 Mouse (Kensington): left-handed remap + BTN_SIDE→Super+Shift+C (close window) + BTN_LEFT→Super+Tab
- See `~/.dotfiles/keyd/README.md` for full key remapping documentation

### xmonad Key Bindings
- Super tap → Albert toggle
- Alt_L tap → ghostty scratchpad 1 (adaptive half-screen)
- Alt_R tap → ghostty scratchpad 2 (adaptive half-screen)
- Volume keys → volume-osd script (dzen2 FIFO-based, no flicker)
- Brightness keys → brightness-osd script (5% steps ≤20%, 10% above)
- Super+VolumeUp → cycle audio output (first press shows current, subsequent presses cycle)
- Super+VolumeDown → cycle audio input (same behavior, filters cameras)
- Super+N → W.view (focus workspace without swapping monitors)
- Ctrl+Super+N → W.greedyView (bring workspace to current monitor)
- Super+Shift+Enter → gnome-terminal
- Super+` → next screen
- Super+= → next screen
- Super+0 → next empty workspace

### Audio OSD System
- Three independent dzen2 popups using FIFOs (no flicker on rapid presses):
  - volume-osd: /tmp/volume-osd-fifo, green, y=100
  - audio-out-osd: /tmp/audio-out-osd-fifo, cyan, y=210
  - audio-in-osd: /tmp/audio-in-osd-fifo, pink, y=320
- Dimensions scale with Xft.dpi (base: x=100, w=1240, h=100 at 96dpi)
- Font: JetBrainsMono Nerd Font, size 36 bold (not scaled — font respects DPI natively)
- Auto-hide after 2-3 seconds using lockfile PID check

### Brightness OSD
- brightness-osd: /tmp/brightness-osd-fifo, yellow, y=430
- Same dzen2 FIFO pattern as audio OSD
- Uses brightnessctl (nix), 5% steps ≤20%, 10% above

### Scratchpad System
- Two independent ghostty instances (scratchpad1, scratchpad2), each running `zellij-cycle` with its own default session (scratch1, scratch2)
- `zellij-cycle` wrapper: loops attach→detach, cycling to next active session on Alt-tab (Detach); Alt-s opens fzf session picker in a tiled pane; generates per-instance zellij config (sed CYCLE_SWITCH_CMD) with callback that writes pick file and pkills attach; picker runs detached via setsid to survive pane closure
- `scratchpadToggle`: focused→hide to NSP, visible on another screen→focus, hidden (NSP or any non-visible workspace)→bring to current workspace+float+focus
- `adaptiveFloat` manage hook: landscape→side-by-side halves, portrait→stacked halves, 2% margins
- `refloatAdaptive`: repositions scratchpad to match current screen orientation on every show
- Identified by x11-instance-name (scratchpad1/scratchpad2)

### Zoom Notification
- `zoom_linux_float_message_reminder` window: floats on all workspaces without stealing focus (via `copyToAll` + `insertPosition Below Older`)

### Known Issues / Constraints
- keyd v2.5.0 parser fails on UTF-8 box-drawing characters in default.conf comments (works in kinesis.conf — likely a parser bug)
- Nix-installed GTK apps don't show in xfce4-panel systray (library mismatch)
- xfconf needs dbus service registration (handled by Home Manager activation, re-runs on nix updates)
- Fonts need copying to ~/.local/share/fonts for neovide/dzen2 (nix font paths not read by skia/dzen2)
- User is on LDAP (can't chsh), $SHELL is bash, zsh started via exec from .bashrc
- AltGr on laptop keyboard doesn't map to Right Alt (needs keyd per-device config)
- gnome-flashback "Notifications" tray icon doesn't respond to clicks (no GNOME Shell notification panel)
- fzf-lua: `fzf_opts['--bind']` is overwritten by `create_fzf_binds` in core.lua — custom fzf binds must go through `actions` table (Lua actions) or `keymap.fzf`, not `fzf_opts`
- fzf-lua: `ctrl-o` doesn't reach fzf (neovim terminal mode intercepts it for normal-mode-one-command); `ctrl-g` is fzf's default abort but can be overridden via fzf-lua Lua actions

### Monitors
- Primary: varies (currently 1920x1200, 3440x1440, 1440x2560 portrait)
- Multi-monitor: stacked/side-by-side configurations change frequently
- xfce4-panel bottom bar: 48px, using avoidStruts (panel struts issue was worked around)

### Sound System
- PipeWire with PulseAudio compatibility (pipewire-pulse)
- wpctl for device switching, amixer for volume control
- pavucontrol installed for GUI mixer
