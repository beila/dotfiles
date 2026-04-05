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

### High impact
- [ ] can't type hangul in zellij/ghostty
- [ ] **universal Copy/paste key** — copy/paste keys that work the same way in x window app, terminals, zellij, neovide, (neo)vim in terminals
- [ ] use fzf for zsh tab completion
- [ ] make fzf zellij popup
- [x] shorten change id/date/time and remove git commit id in list panes of _gh, ...
  - jj template aliases `fzf_oneline` (no author/git-id) and `fzf_oneline_author`; revset alias `workspace_view()` for _jh; `_jh` uses `workspace_view()`, `_jhh` uses `::workspace_view()`
- [ ] pass query between _jh/_jhh, _jy/_jyy, _jb/_jbb toggles
  - when toggling via `become` (ctrl-h, ctrl-b, ctrl-y), preserve the current fzf search query in the new view
- [x] shorten relative date/time in fzf_oneline templates (e.g. "1w" instead of "1 week ago")
  - `short_ago(ts)` template alias: single-letter suffixes (m/h/d/w/M/y), uses `.contains()`/`.substr()` chain (jj 0.32 lacks `.replace()`); used by both `fzf_oneline` and `fzf_oneline_author`
- [ ] remove hostname-prefixed remote bookmarks from jj without deleting them from the server
- [ ] show first name instead of email local part in fzf_oneline_author (jj templates lack string split)

### Medium impact
- [ ] add squash feature to _gf
  - fzf shortcut (not enter) squashes the currently selected/highlighted file(s) from `@` into a target revision
  - opens `_gh` with a header explaining the squash context, minimise duplicated code
  - runs `jj squash --into <rev> -- <files>`
  - enter keeps current behaviour (output filenames)
- [ ] add inserting a new empty revision in _gh
- [ ] notify user when sync_dotfiles merge has conflicts
  - Plan: set up Telegram bot for push notifications (ntfy is simpler but Telegram supports two-way); update notify-webhook to use Telegram
- [ ] how do I get notified with sync_all error
- [ ] share code between fzf/functions.sh/functions.sh and fzf.lua
- [ ] in nvim grep dialog, add a shortcut to toggle searching whole word+case sensitive
- [ ] review each nvim plugin and cleanup/modernise
- [ ] make sync_dotfiles more readable
- [ ] fzf/functions.sh sets list width depending on the contents
- [ ] Check if I can log in with fingerprint https://learn.omacom.io/2/the-omarchy-manual/77/fingerprint-fido2-authentication
- [ ] Check if I can sudo with security key https://learn.omacom.io/2/the-omarchy-manual/77/fingerprint-fido2-authentication

### Low impact
- [ ] zellij session picker: make it floating
- [ ] zellij session picker: show current session differently and make it not choosable
- [ ] zellij session picker: kills current pane, when the session is open in two zellij
- [ ] airline tabbar changes a lot when opening nvimtree
- [ ] there's no gap between ghostty vertically
- [ ] make battery notification sticky
- [ ] treesitter auto install
- [ ] make copilot key work as super
- [ ] replace absolute path from xfce settings
- [ ] review remaining mini-nvim modules: mini.splitjoin (toggle single/multi-line), mini.bracketed (unified [/] nav)

## Architecture Overview

### Dotfiles Repo: ~/.dotfiles
- Home Manager config: `~/.dotfiles/home-manager.configsymlink/`
  - `flake.nix` — modules: gnome.nix, home.nix, neovide.nix, nvim.nix, xdg.nix, xmonad.nix
  - `home.nix` — packages, unfree predicate (albert), battery-notify systemd timer (1min check, notify at 20%/10%)
  - `gnome.nix` — dconf settings (key repeat, mouse speed, cursor size 64, Korean input Sebeolsik 390, disable gnome-panel/desktop, empty gnome-panel layout as fallback), random-lockscreen systemd timer (daily wallpaper), gnome-flashback systemd drop-ins (xmonad session target requires gnome-flashback.target + service restart override)
  - `neovide.nix` — nixGL-wrapped neovide, font copying activation (JetBrains Mono + Nerd Font)
  - `nvim.nix` — neovim (default editor, vi/vim aliases), dev tool packages (LSPs, linters, formatters, DAP deps); coverage table documents all tools per language
  - `xmonad.nix` — xmonad + contrib via nix 0.18, xfce4-panel + xfconf, xfconf dbus activation hook
  - `xdg.nix` — firefox-container desktop entry + mimeapps
  - `system-deps.sh` — apt packages (ibus-hangul, gnome-session-flashback) + session file installs (gnome-flashback-xmonad.session strips gnome-panel, keeps essential SettingsDaemons: Datetime, Housekeeping, Keyboard, Power, ScreensaverProxy, XSettings) + keyd service setup + loginctl enable-linger (keeps systemd --user alive after logout so zellij/timers survive) + ollama install (service disabled, started on demand by commit-msg)
- xmonad config: `~/.dotfiles/xwindow/xmonad.symlink/xmonad.hs` (symlinked to ~/.xmonad/)
  - Build: `~/.xmonad/build` uses `$XMONAD_GHC` (set by nix xmonad wrapper, GHC with xmonad packages); falls back to PATH `ghc`; `set -euo pipefail` + `${1:?}` guard prevents creating misnamed binaries if output path is missing
  - HLS: `hie.yaml` + `.hie-bios` cradle points HLS to `$XMONAD_GHC` package db; HLS and GHC installed from same `haskellPackages` set in nvim.nix to keep versions in sync
  - ManageHook split into: `floatRules`, `browserRules`, `mailRules`, `editorRules`, `calendarRules`, `meetingRules`, `messengerRules`
  - `rescueOffscreenHook`: catches floating windows that move themselves offscreen (e.g. Zoom bug) via ConfigureEvent and snaps them back
  - `monitorHotplugCfg` / `hideNSPWorkspace`: swaps NSP off visible screens after monitor hotplug
  - `greedyViewNoSwap`: workspace switch variant that swaps visible screens but not hidden
- keyd config: `~/.dotfiles/keyd/` (common, default.conf, kinesis.conf, thinkpad.conf — copied to /etc/keyd/ by system-deps.sh)
- input-remapper: `~/.dotfiles/input-remapper-2.configsymlink/` (symlinked to ~/.config/input-remapper-2/) — mice only
- jj config: `~/.dotfiles/jj.configsymlink/` (symlinked to ~/.config/jj/), local email in conf.d/local.toml (gitignored), revset aliases: `workspace_view()` (mutable chain + boundary + branches for fzf _jh), `unique(x, markers)` (commits not in ancestor markers), `unique_boundary(x, markers)` (unique + boundary revs); template aliases: `short_ago(ts)` (compact relative time: m/h/d/w/M/y via `.contains()`/`.substr()` chain — jj 0.32 lacks `.replace()`), `fzf_oneline` (shortest change ID, no author/git-id, short relative time, bookmarks after description), `fzf_oneline_author` (same + author)
- fzf config: `~/.dotfiles/fzf/fzf.zsh` — env vars (FZF_ALT_C_COMMAND, FZF_CTRL_T_COMMAND, etc.), sources `fzf --zsh` dynamically (no static key-bindings.zsh), then sources custom key-binding.zsh, binds Ctrl-E to fzf-cd-widget
  - `functions.sh/functions.sh` — jj-first/git-fallback functions; each `_g*` dispatcher delegates to `_j*` (jj) or `_git_*` (git) implementation (e.g. `_gf`→`_jf`/`_git_f`); `_jb`/`_jt` previews use `unique_boundary()` revset alias to show commits unique to the selected bookmark/tag with boundary revs; `_jb` preprocesses indented remote tracking lines (`@hj`) by prefixing parent bookmark name; `_gh` shows upstream log (jj default / git upstream), `_ghh` shows full ancestor log (jj `::@` / git full log); `_jr` preview uses `remote_bookmarks(remote=NAME)`; `_fzf_functions_sh` captures source file path for `become` sourcing; `_jj_change_id` extracts change ID from fzf line (strips ANSI); `_jj_find_pos` finds line number of a change ID in jj log output (head -500 for SIGPIPE early exit); toggles via `become`: `_jh`↔`_jhh` (ctrl-h, revision-based focus), `_jb`↔`_jbb` (ctrl-b), `_jy`↔`_jyy` (ctrl-y); fzf query preserved across toggles via `{q}`→`--query`; line-number focus uses `result:pos(N+1)+unbind(result)` (fzf `{n}` is 0-indexed, `pos` is 1-indexed)
  - `functions.sh/key-binding.zsh` — Ctrl-G sequences (`^G^F`, `^G^B`, etc.) bound in both viins and vicmd modes; `^G` rebound to undefined-key to prevent list-expand from swallowing the prefix; `^F` bound to `_file_browse` (tracked/all files toggle)
  - All custom bindings must use `bindkey -M viins` and `bindkey -M vicmd` (vi mode — plain `bindkey` only sets viins/main)
- ghostty config: `~/.dotfiles/ghostty.configsymlink/` (symlinked to ~/.config/ghostty/)
  - `keybind = ctrl+{j,k,n,p}=text:\xNN` — sends legacy control codes instead of CSI u; fixes zellij leaking kitty keyboard protocol sequences as literal text into fzf query under rapid key repeat
- albert config: `~/.dotfiles/albert.configsymlink/` (symlinked to ~/.config/albert/)
- xfce4-panel config: `~/.dotfiles/xfce4.configsymlink/` (symlinked to ~/.config/xfce4/)
- gtk-3.0 config: `~/.dotfiles/gtk-3.0.configsymlink/` (symlinked to ~/.config/gtk-3.0/) — monospace tooltip font
- zellij config: `~/.dotfiles/zellij.configsymlink/` (symlinked to ~/.config/zellij/)
  - Normal mode keybindings: Alt-tab→Detach (triggers zellij-cycle session switch), Alt-s→fzf session picker (via CYCLE_SWITCH_CMD template), Ctrl-tab→next tab, Alt-h/j/k/l→MoveFocus, Alt-Shift-h/j/k/l→MovePane
  - Move keybindings: Alt-Shift-h/l→move tab left/right, Ctrl-Shift-h/j/k/l→move pane
  - Config template: `CYCLE_SWITCH_CMD` placeholder in Alt-s binding, replaced by `zellij-cycle` via sed with per-instance callback
- kiro config: `~/.dotfiles/kiro.filesymlink/` (individual files symlinked into ~/.kiro/) — agents/default.json (MCP TTS server, autoAllowReadonly), settings/cli.json (default agent: builder), bin/kiro-response (TTS fallback), bin/mcp-tts (MCP server for say/say_ko tools, kills previous playback via `setsid` + `kill -PGID` before starting new TTS)
- Audio/brightness scripts: `~/.dotfiles/xwindow/bin/volume-osd`, `cycle-audio-output`, `cycle-audio-input`, `brightness-osd`
- Weather script: `~/.dotfiles/xwindow/bin/weather-genmon` — single wttr.in JSON API call, python3 parses response; shows 🌙 after sunset / before sunrise (clear→moon, cloudy→☁🌙), weather icons unchanged for rain/snow/fog; tooltip: current conditions + hourly + 3-day forecast
- System monitor: `~/.dotfiles/xwindow/bin/sysmon-genmon` — sparkline graphs (CPU, MEM, IO, NET, BAT) via xfce4-genmon-plugin; `color_bar` supports inverted mode (2nd arg `1`) for metrics where high=good (battery); padding bars (no prior data) always use non-inverted color to avoid false red on battery; history in `/tmp/sysmon-history`, 8 samples
- Battery indicator: `~/.dotfiles/xwindow/bin/battery-genmon` — standalone battery genmon (kept as fallback; battery now also in sysmon-genmon)
- Lock screen: `~/.dotfiles/xwindow/bin/random-lockscreen`
- Keyboard hotplug: keyd handles remapping at evdev level (no hotplug workaround needed)
- Sync scripts: `~/.dotfiles/script/sync_all` (all repos, triggered by `sync-repos.timer`), `sync_dotfiles` (single repo), `jj_snapshot_all` (snapshot all jj repos via plocate)
  - `sync_all` calls `notify-webhook` on failure (currently disabled — awaiting Telegram bot setup)
  - `sync_dotfiles` jj path: per-repo `flock` on `jj root` (workspaces sharing a repo lock together); skips empty changes (commit/describe only), describes with AI commit message, always pushes bookmarks
  - Auto-merge: fetches tracking branches, merges local bookmark forward via jj (no force), pushes to hj; tracks `bm@hj` after push
  - Prefixed bookmarks: delete+push via raw git (`hostname/bookmark`, server doesn't support `--force`); single `ls-remote` per run, skips if unchanged; excludes already-prefixed local bookmarks; no tracking of prefixed remote bookmarks (jj requires name match)
  - Requirements documented as comments in script: (1) commit with AI message if non-empty, (2) push all bookmarks with hostname prefix, (3) safely merge and push tracked bookmark
- Commit message generator: `~/.dotfiles/bin/commit-msg` — kiro-cli first (cloud model, `--agent default`), ollama + qwen2.5-coder:3b fallback (started on demand, stopped after); jj-first/git-fallback; strips ANSI codes, cursor sequences, and spinner carriage returns; rejects kiro-cli login/spinner output (falls back to ollama)
- Notifications: `~/.dotfiles/bin/notify-webhook` — sends push notifications for script failures; currently disabled (exit 0), awaiting Telegram bot; KakaoTalk "나에게 보내기" tested but doesn't trigger push notifications; tokens in `private-dotfiles/kakao-tokens.json`
- Private dotfiles: `~/.dotfiles/private-dotfiles/` — gitignored nested jj repo (git@github.com:beila/private-dotfiles.git); cloned by `script/bootstrap`; stores machine-specific secrets (kakao tokens, webhook URLs); zsh `**/*.zsh` glob auto-sources any .zsh files within
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
- zsh functions: `~/.dotfiles/zsh/functions/c` (copy), `p` (paste), `o` (open), `say_done` (TTS notification), `ju` (jj unique — show commits unique to a bookmark/tag with boundary revs, auto-detects bookmark vs tag markers) — Wayland/X11 aware
- TTS: `~/.dotfiles/bin/say` — piper-tts with en_GB-alba-medium voice, auto-downloads model on first run
  - `say_done` calls `say` to announce when commands >10s finish (via `add-zsh-hook` in `zsh/config.zsh`); runs in subshell `(say_done &)` to suppress background PID output
  - Override voice with `$PIPER_MODEL`
- TTS (Korean): `~/.dotfiles/bin/say-ko` — edge-tts with ko-KR-SunHiNeural voice (requires internet)
  - Default rate: +50%, override with `$EDGE_TTS_RATE`
  - Override voice with `$EDGE_TTS_VOICE` (available: ko-KR-SunHiNeural, ko-KR-InJoonNeural, ko-KR-HyunsuMultilingualNeural)

### Neovim Dev Tooling
- Config: `~/.dotfiles/nvim.configsymlink/` (symlinked to ~/.config/nvim; also ~/.vim via vim.symlink → nvim.configsymlink)
- Plugin management: all plugins installed via home-manager `programs.neovim.plugins`; no submodules remain; `.gitmodules` removed (vim.symlink was last entry, now a symlink to nvim.configsymlink)
- Config loading: `myvimrc` runs `runtime! vimrcs/*.vimrc`, `vimrcs/*.nvimrc`, `vimrcs/*.lua`; `set verbosefile=~/.vim-messages.log` captures `:messages` output
- Logs: `~/.vim-messages.log` (nvim messages), `~/.local/state/nvim/lsp.log` (LSP), `~/.local/state/nvim/mason.log` (Mason)
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
- Completion: `vimrcs/blink-cmp.lua` — blink.cmp completion (based on kickstart)
- DAP UI: `vimrcs/nvim-dap-ui.lua` — auto-open/close debug UI, F7 toggle
- Git gutter: `vimrcs/gitsigns.lua` — gitsigns.nvim with jj support (diffs against `@-` via `change_base`), `]c`/`[c` hunk nav, `<leader>hp` preview, `<leader>hr` reset, `<leader>hb` blame (no staging — safe for jj)
- LSP enhancements: `vimrcs/lsp_signature.lua` — inlay hints (neovim ≥ 0.10) + auto signature help (lsp_signature.nvim)
- LSP progress: `vimrcs/fidget.lua` — fidget.nvim notifications
- Keybind discovery: which-key.nvim removed (auto-triggers interfered with `}`, `{`, `<C-g>` prefixes)
- Treesitter textobjects: configured in `vimrcs/nvim-treesitter.lua` — `vaf`/`vif` function, `vac`/`vic` class, `vaa`/`via` parameter, `]f`/`[f` function nav, `]a`/`[a` parameter nav, `<leader>a`/`<leader>A` swap parameter next/prev (manual global keymaps)
- mini.ai: `vimrcs/mini-ai.lua` — extended a/i textobjects with forward/backward seeking; builtin `f` (function call), `a` (argument), `b` (any bracket), `q` (any quote), `t` (tag), `?` (user prompt); treesitter-powered `F` (function definition), `c` (class); pattern-based `f`/`a` work better than treesitter for C++ templates
- nvim-surround: `vimrcs/nvim-surround.lua` — `ys`/`ds`/`cs` keybindings (matches zsh vi-mode surround); no surround plugin existed in nvim before this
- Treesitter incremental selection: `<C-e>` init/expand node, `<C-d>` shrink node (manual global keymaps)
- Indent detection: vim-sleuth (auto-detects tabstop/shiftwidth, no config)
- Yank highlight: `init.lua` — brief highlight on yank (from kickstart)
- Limelight: `my-text.lua` — auto-enabled for text, markdown, rst, org, asciidoc, tex, mail, gitcommit; per-buffer (BufEnter/BufLeave toggle)
- Table mode: `my-markdown.lua` — `silent! TableModeEnable` on markdown FileType (suppresses echo noise)
- fzf-lua: `vimrcs/fzf.lua` — `<leader>f` jj/git tracked files (ctrl-g toggles submodule files, ctrl-f toggles all files incl. gitignored, query preserved across toggle, `vimrcs/jj-file-list-all` helper script), `<leader>F` all files (incl. gitignored), `<C-g><C-f>` jj/git changed files, ctrl-n/p preview scroll
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
- Known bug: with multi-monitor (3 screens), moving mouse toward the notification can trigger workspace swap (focus-follows-mouse + `copyToAll` interaction); notification appears to jump to another screen before you can click it; needs investigation when reproducible

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
- nvim-treesitter `ensure_installed` + `auto_install` can fail trying to write to nix store (read-only); `auto_install = false` and `ensure_installed = {}` as workaround; treesitter module buffer-local keymaps may not attach — manual global keymaps used for incremental selection and swap
- zsh vi mode: custom zle widget bindings must use `bindkey -M viins` and `bindkey -M vicmd` explicitly; plain `bindkey` only sets main (viins) — vicmd (normal mode) shows `^X` literal for unbound keys
- zsh fzf: `source <(fzf --zsh)` must come before custom bindkeys that reference fzf widgets (fzf-cd-widget, etc.); `zshrc.symlink` globs `**/*.zsh` alphabetically — don't put static copies of fzf scripts in the glob path
- zellij + kitty keyboard protocol: under rapid key repeat, zellij occasionally fails to parse CSI u sequences and passes raw bytes to child programs; worked around by sending legacy control codes from ghostty for ctrl-j/k/n/p
- C++ treesitter textobjects: `#make-range!` directives can silently fail; `@function.outer` misses lambdas and some edge cases; mini.ai pattern-based `f`/`a` is more reliable for C++ function calls and arguments
- Push notifications: Google Chat webhooks blocked by org admin; Slack app creation requires workspace admin approval; KakaoTalk "나에게 보내기" doesn't trigger push (messages to self are silent); Telegram bot or ntfy.sh are the viable options

### Monitors
- Current: 3 monitors — eDP-1 (1920x1200 laptop), DP-1 (3440x1440 ultrawide), DP-3 (1440x2560 portrait); varies by location
- Multi-monitor: configurations change frequently; `rescreenHook` with `hideNSPWorkspace` swaps NSP off visible screens after hotplug
- xfce4-panel bottom bar: 48px, using avoidStruts (panel struts issue was worked around)

### Sound System
- PipeWire with PulseAudio compatibility (pipewire-pulse)
- wpctl for device switching, amixer for volume control
- pavucontrol installed for GUI mixer
