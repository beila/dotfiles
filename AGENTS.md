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
- [ ] check `home-manager news` — neovim withRuby/withPython3 defaults changed (stateVersion < 26.05)
- [ ] can't type hangul in zellij/ghostty
- [ ] **universal Copy/paste key** — copy/paste keys that work the same way in x window app, terminals, zellij, neovide, (neo)vim in terminals
- [ ] use fzf for zsh tab completion
- [x] run fzf in a zellij floating pane instead of inline
  - `fzf/fzf-zellij` script (modeled after `fzf-tmux`): FIFO for streaming stdin, temp file for output, `zellij run --floating` to spawn pane, polls for EXIT-trap `done` marker, closes pane explicitly
  - `fzf_down()` calls `fzf-zellij` unconditionally; falls back to plain fzf outside zellij
  - `FZF_ZELLIJ=1` env var set inside floating pane prevents nested panes on `become` toggles; strips `--height`/`--min-height` so toggled fzf uses full pane
  - `fzf/test_fzf_zellij.sh` — automated tests (run with `bash fzf/test_fzf_zellij.sh` inside zellij)
- [x] shorten change id/date/time and remove git commit id in list panes of _gh, ...
  - jj template aliases `fzf_oneline` (no author/git-id) and `fzf_oneline_author`; revset alias `workspace_view()` for _jh; `_jh` uses `workspace_view()`, `_jhh` uses `::workspace_view()`
- [x] pass query between _jh/_jhh, _jy/_jyy, _jb/_jbb toggles
  - when toggling via `become` (ctrl-h, ctrl-b, ctrl-y), preserve the current fzf search query in the new view
- [x] shorten relative date/time in fzf_oneline templates (e.g. "1w" instead of "1 week ago")
  - `short_ago(ts)` template alias: single-letter suffixes (m/h/d/w/M/y), uses `.contains()`/`.substr()` chain; used by both `fzf_oneline` and `fzf_oneline_author`
- [ ] remove hostname-prefixed remote bookmarks from jj without deleting them from the server
- [ ] `_gy` ↔ `_gyy` toggle via `become` produces wrong output
  - after `become`, the new function's output goes through the original function's post-processing pipeline
  - `_gy` expects hex operation IDs (`grep -o "[0-9a-f]\{12,\}"`), but `_jyy` returns change IDs (lowercase alpha via `_jj_log_fzf`)
  - pre-existing bug (not caused by fzf-zellij), also affects `_gyy` → `_gy`
  - `_gh` ↔ `_ghh` works because both use `_jj_log_fzf` with the same output format
  - possible fix: unify output format (e.g. both return the raw fzf line, let the caller extract), or move post-processing into the `become` target so each function owns its own output pipeline
  - files: `fzf/functions.sh/functions.sh` — `_jy()` (line ~263), `_jyy()` (line ~222)
- [x] show first name instead of email local part in fzf_oneline_author (uses `author.name().split(" ").first()`, falls back to `email().local()` if name empty; requires jj ≥0.39)
- [ ] make zellij floating point as big and more importantly as wide as appropriate while leaving slight context
- [ ] stop amazon-vpn when the network changes
- [ ] use --impure for private-dotfiles instead of having to add commit and override the lock file every time
- [ ] run systemd for user from nix

### Medium impact
- [ ] add squash feature to _gf
  - fzf shortcut (not enter) squashes the currently selected/highlighted file(s) from `@` into a target revision
  - opens `_gh` with a header explaining the squash context, minimise duplicated code
  - runs `jj squash --into <rev> -- <files>`
  - enter keeps current behaviour (output filenames)
- [x] add inserting a new empty revision in _gh
  - ctrl-o inserts a blank revision after the selected revision (`jj new --no-edit --after <rev>`), does not move `@`
  - on success: reloads the log list; on failure (e.g. immutable rev): shows jj error in fzf header via `transform:`
  - header shows hint: `insert after (ctrl-o)` next to existing `ctrl-h` hint
- [x] change ctrl-o in `_gh`/`_ghh` to insert after instead of before
  - `jj new --no-edit --after <rev>` (insert after — more common use case)
  - header hint: `insert after (ctrl-o)`
  - files: `fzf/functions.sh/functions.sh` — `_jh()`, `_jhh()` ctrl-o bindings; `test_toggle_query.sh` assertions updated
- [ ] notify user when sync_repo merge has conflicts
  - Plan: set up Telegram bot for push notifications (ntfy is simpler but Telegram supports two-way); update notify-webhook to use Telegram
- [ ] how do I get notified with sync_all error
- [ ] share fzf config between shell (`fzf/functions.sh/functions.sh`) and nvim (`fzf.lua`)
  - fzf command-line parameters (including preview commands) are duplicated between the two
  - improvements made in one don't automatically apply to the other
  - goal: single source of truth for shared fzf options/previews, so both shell and nvim get the superset of features
  - direction: whichever is simpler (e.g. shared config file, shell script that both source, or generated opts)
  - scope: unify existing features only, no new functionality
- [ ] in nvim grep dialog, add a shortcut to toggle searching whole word+case sensitive
- [ ] review each nvim plugin and cleanup/modernise
- [x] ~~migrate lspconfig `require('lspconfig').X.setup()` to `vim.lsp.config`~~ (done 2026-04-07)
  - all 28 servers migrated to `vim.lsp.config.NAME = { ... }` + `vim.lsp.enable('NAME')`
  - `my-rust.lua` uses rustaceanvim (not vim.lsp.config) — unaffected
  - mason.lua handler also migrated
- [ ] switch nix neovim module to `hm-generated.lua` approach
  - current: `initLua` in `nvim.nix` inlines `myinit.lua` into nix-generated `init.lua`, overwriting `nvim.configsymlink/init.lua` on every `home-manager switch`; `init.lua` is gitignored (in `nvim.configsymlink/.gitignore`); `myinit.lua` is tracked (nix flake requires it); `nvim.configsymlink` is no longer in root `.gitignore`
  - better: `xdg.configFile."nvim/lua/hm-generated.lua".text = config.programs.neovim.initLua;` + restore own `init.lua` (from `myinit.lua`) with `require 'hm-generated'` at top
  - benefit: nix stops overwriting `init.lua`, `myinit.lua` can be merged back into `init.lua`, simpler config chain
  - see home-manager news 2026-01-25 and PR #8586/#8606
  - files: `home-manager.configsymlink/nvim.nix`, `nvim.configsymlink/myinit.lua`, `nvim.configsymlink/.gitignore`
- [ ] make sync_repo more readable
- [ ] automate nix flake updates and catch breaking changes early
  - flake inputs to keep updated: `nixpkgs` (nixos-unstable), `home-manager`, `nixGL`
  - `nix flake update` bumps all inputs; `nix flake update nixpkgs` bumps one
  - after update: `home-manager switch`, check `home-manager news` for breaking changes, test neovide + nvim startup
  - today's upgrade broke: nvim 0.12 (treesitter API, lspconfig deprecation), neovide font (Source Code Pro missing), zellij version mismatch (old server vs new binary), nvim init.lua overwritten (new home-manager neovim module)
  - consider: periodic `nix flake update` in `sync_all` or a separate timer, with notification on `home-manager switch` failure
  - consider: pin nixpkgs to a known-good rev and update intentionally, rather than always tracking unstable head
- [ ] fzf/functions.sh sets list width depending on the contents
- [ ] make ctrl-/ in fzf cycle through preview layouts: horizontal → vertical → hidden
  - currently `fzf_down` binds `ctrl-/:toggle-preview` (on/off only)
  - fzf supports `change-preview-window` action to cycle layouts (e.g. `change-preview-window(right|down|hidden)`)
  - applies to `fzf_down()` in `fzf/functions.sh/functions.sh` and `fzf-zellij` (which passes `--bind ctrl-/:toggle-preview`)
- [ ] use zellij floating pane for built-in fzf zsh widgets (ctrl-e, ctrl-f, ctrl-t, alt-c)
  - these use `fzf --zsh` generated widgets which call fzf directly, not through `fzf_down`/`fzf-zellij`
  - option A: override the fzf binary with a shell function that delegates to `fzf-zellij` (risk: infinite recursion, `fzf-zellij` resolves real binary via `command which fzf`)
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
- [x] ~~treesitter auto install~~ (done 2026-04-07)
  - all grammars installed via nix (`nvim-treesitter.withAllGrammars`), updated with `nix flake update`
  - `<leader>a`/`<leader>A` swap parameters, `<C-e>` expand selection, `<C-d>` shrink selection
- [ ] make copilot key work as super
- [ ] replace absolute path from xfce settings
- [ ] review remaining mini-nvim modules: mini.splitjoin (toggle single/multi-line), mini.bracketed (unified [/] nav)

## Architecture Overview

### Dotfiles Repo: ~/.dotfiles
- Home Manager config: `~/.dotfiles/home-manager.configsymlink/`
  - `flake.nix` — inputs: nixpkgs, home-manager, nixGL, private-dotfiles (`flake = false`); `mkHost` builds a `homeManagerConfiguration` from shared modules + extra modules; `nixFilesFrom` auto-loads root `.nix` files from private-dotfiles as modules; `hosts/*.nix` in private-dotfiles return `homeConfigurations` attrset fragments keyed by `username@static-hostname`; `local.nix` removed (host config moved to private-dotfiles); `nix.conf` `warn-dirty = false` required for home-manager auto-detection to work with jj (dirty tree warnings pollute `nix eval` stdout); `hm-session-vars.sh` sourced in `zshenv.symlink` (zsh not managed by home-manager)
  - `home.nix` — packages, unfree predicate (albert), battery-notify systemd timer (1min check, notify at 20%/10%)
  - `gnome.nix` — dconf settings (key repeat, mouse speed, cursor size 64, Korean input Sebeolsik 390, disable gnome-panel/desktop, empty gnome-panel layout as fallback), random-lockscreen systemd timer (daily wallpaper), gnome-flashback systemd drop-ins (xmonad session target requires gnome-flashback.target + service restart override)
  - `neovide.nix` — nixGL-wrapped neovide (GPU access on non-NixOS), font copying activation (JetBrains Mono + Nerd Font + Source Code Pro for neovide default fallback)
  - `nvim.nix` — neovim (default editor, vi/vim aliases), `initLua` sources `myinit.lua` (nix generates `init.lua` which overwrites `nvim.configsymlink/init.lua` on every switch — `init.lua` is gitignored), dev tool packages (LSPs, linters, formatters, DAP deps), rustaceanvim (Rust LSP, replaces rust-tools-nvim); coverage table documents all tools per language
  - `xmonad.nix` — xmonad + contrib via nix 0.18, xfce4-panel + xfconf, xfconf dbus activation hook
  - `xdg.nix` — firefox-container desktop entry + mimeapps
  - `system-deps.sh` — detects package manager (dnf/yum preferred over apt-get for Amazon Linux); GNOME packages + session files guarded behind `gnome-session` check; keyd service guarded behind `/dev/input` check; loginctl enable-linger; ollama install guarded behind `$DISPLAY`/`$WAYLAND_DISPLAY` check (desktop only)
- xmonad config: `~/.dotfiles/xwindow/xmonad.symlink/xmonad.hs` (symlinked to ~/.xmonad/)
  - Build: `~/.xmonad/build` uses `$XMONAD_GHC` (set by nix xmonad wrapper, GHC with xmonad packages); falls back to PATH `ghc`; `set -euo pipefail` + `${1:?}` guard prevents creating misnamed binaries if output path is missing
  - HLS: `hie.yaml` + `.hie-bios` cradle points HLS to `$XMONAD_GHC` package db; HLS and GHC installed from same `haskellPackages` set in nvim.nix to keep versions in sync
  - ManageHook split into: `floatRules`, `browserRules`, `mailRules`, `editorRules`, `calendarRules`, `meetingRules`, `messengerRules`
  - `rescueOffscreenHook`: catches floating windows that move themselves offscreen (e.g. Zoom bug) via ConfigureEvent and snaps them back
  - `monitorHotplugCfg` / `hideNSPWorkspace`: swaps NSP off visible screens after monitor hotplug
  - `greedyViewNoSwap`: workspace switch variant that swaps visible screens but not hidden
- keyd config: `~/.dotfiles/keyd/` (common, default.conf, kinesis.conf, thinkpad.conf — copied to /etc/keyd/ by system-deps.sh)
- input-remapper: `~/.dotfiles/input-remapper-2.configsymlink/` (symlinked to ~/.config/input-remapper-2/) — mice only
- jj config: `~/.dotfiles/jj.configsymlink/` (symlinked to ~/.config/jj/), user email in `private-dotfiles/jj/user.toml` (symlinked to `conf.d/user.toml` by `private-dotfiles/jj/install.sh`), `repos/` gitignored (machine-specific, auto-generated by jj); revset aliases: `workspace_view()` (mutable chain + boundary + branches for fzf _jh), `unique(x, markers)` (commits not in ancestor markers), `unique_boundary(x, markers)` (unique + boundary revs); template aliases: `short_ago(ts)` (compact relative time: m/h/d/w/M/y via `.contains()`/`.substr()` chain), `fzf_oneline` (shortest change ID, no author/git-id, short relative time, bookmarks after description), `fzf_oneline_author` (same + author first name via `.split(" ").first()`, falls back to email local part)
- fzf config: `~/.dotfiles/fzf/fzf.zsh` — env vars (FZF_ALT_C_COMMAND, FZF_CTRL_T_COMMAND, etc.), sources `fzf --zsh` dynamically (no static key-bindings.zsh), then sources custom key-binding.zsh, binds Ctrl-E to fzf-cd-widget
  - `fzf-zellij` — drop-in `fzf-tmux` equivalent for zellij; runs fzf in a floating pane with FIFO stdin streaming and temp file output; polls for EXIT-trap done marker; captures pane ID and closes explicitly; `FZF_ZELLIJ=1` env var prevents nested floating panes on `become` toggles and strips `--height`/`--min-height`; falls back to plain fzf outside zellij; `--close-on-exit` is unreliable in zellij so panes are closed explicitly
  - `test_fzf_zellij.sh` — automated tests for fzf-zellij (piped input, fallback, pipeline extraction, nested/become); run with `bash fzf/test_fzf_zellij.sh` inside a zellij session  - `functions.sh/functions.sh` — jj-first/git-fallback functions; each `_g*` dispatcher delegates to `_j*` (jj) or `_git_*` (git) implementation (e.g. `_gf`→`_jf`/`_git_f`); `_jb`/`_jt` previews use `unique_boundary()` revset alias to show commits unique to the selected bookmark/tag with boundary revs; `_jb` preprocesses indented remote tracking lines (`@hj`) by prefixing parent bookmark name; `_gh` shows upstream log (jj default / git upstream), `_ghh` shows full ancestor log (jj `::@` / git full log); `_jr` preview uses `remote_bookmarks(remote=NAME)`; `_fzf_functions_sh` captures source file path for `become` sourcing; `_jj_change_id`/`_jj_extract_id` extract change ID from fzf line (strips ANSI, supports single-char IDs via `\{1,\}`); `_jj_find_pos` finds line number of a change ID in jj log output (head -500 for SIGPIPE early exit); toggles via `become`: `_jh`↔`_jhh` (ctrl-h, revision-based focus), `_jb`↔`_jbb` (ctrl-b), `_jy`↔`_jyy` (ctrl-y); ctrl-o inserts empty revision after selected (`jj new --no-edit --after`), uses `transform:` (colon form) to show jj errors in header; fzf query preserved across toggles via `{q}`→`--query`; line-number focus uses `result:pos(N+1)+unbind(result)` (fzf `{n}` is 0-indexed, `pos` is 1-indexed)
  - `functions.sh/test_toggle_query.sh` — non-interactive test for toggle query/focus preservation, ctrl-o binding, and change ID extraction (incl. single-char IDs); mocks fzf via temp file to capture args through pipes; run with `zsh fzf/functions.sh/test_toggle_query.sh` from `~/.dotfiles` after any change to `functions.sh`; file is read-only — only `chmod u+w` when the user explicitly allows it
  - `functions.sh/key-binding.zsh` — Ctrl-G sequences (`^G^F`, `^G^B`, etc.) bound in both viins and vicmd modes; `^G` rebound to undefined-key to prevent list-expand from swallowing the prefix; `^F` bound to `_file_browse` (tracked/all files toggle)
  - All custom bindings must use `bindkey -M viins` and `bindkey -M vicmd` (vi mode — plain `bindkey` only sets viins/main)
- ghostty config: `~/.dotfiles/ghostty.configsymlink/` (symlinked to ~/.config/ghostty/)
  - `keybind = ctrl+{j,k,n,p}=text:\xNN` — sends legacy control codes instead of CSI u; fixes zellij leaking kitty keyboard protocol sequences as literal text into fzf query under rapid key repeat
  - terminfo: `pkgs.ghostty.terminfo` installed via home.nix; `~/.terminfo` symlinked to the nix store terminfo dir so ncurses finds `xterm-ghostty` at process startup (before any shell rc file runs); required for SSH into machines running ghostty as `$TERM`
- albert config: `~/.dotfiles/albert.configsymlink/` (symlinked to ~/.config/albert/)
- xfce4-panel config: `~/.dotfiles/xfce4.configsymlink/` (symlinked to ~/.config/xfce4/)
- gtk-3.0 config: `~/.dotfiles/gtk-3.0.configsymlink/` (symlinked to ~/.config/gtk-3.0/) — monospace tooltip font
- zellij config: `~/.dotfiles/zellij.configsymlink/` (symlinked to ~/.config/zellij/)
  - Normal mode keybindings: Alt-tab→Detach (triggers zellij-cycle session switch), Alt-s→fzf session picker (via CYCLE_SWITCH_CMD template), Ctrl-tab→next tab, Alt-h/j/k/l→MoveFocus, Alt-Shift-h/j/k/l→MovePane
  - Move keybindings: Alt-Shift-h/l→move tab left/right, Ctrl-Shift-h/j/k/l→move pane
  - Config template: `CYCLE_SWITCH_CMD` placeholder in Alt-s binding, replaced by `zellij-cycle` via sed with per-instance callback
- kiro config: `~/.dotfiles/kiro.filesymlink/` (individual files symlinked into ~/.kiro/) — agents/default.json (MCP TTS server, autoAllowReadonly), agents/no-mcp.json (no MCP servers, used by commit-msg to avoid orphaned processes), settings/cli.json (default agent: builder), bin/kiro-response (TTS fallback), bin/mcp-tts (MCP server for say/say_ko tools, kills previous playback via `setsid` + `kill -PGID` before starting new TTS; kill wrapped in `|| true` to survive dead PGID under `set -e`), bin/test_mcp_tts.sh (non-interactive test; run with `bash bin/test_mcp_tts.sh` after any change to mcp-tts)
- Audio/brightness scripts: `~/.dotfiles/xwindow/bin/volume-osd`, `cycle-audio-output`, `cycle-audio-input`, `brightness-osd`
- Weather script: `~/.dotfiles/xwindow/bin/weather-genmon` — single wttr.in JSON API call, python3 parses response; shows 🌙 after sunset / before sunrise (clear→moon, cloudy→☁🌙), weather icons unchanged for rain/snow/fog; tooltip: current conditions + hourly + 3-day forecast
- System monitor: `~/.dotfiles/xwindow/bin/sysmon-genmon` — sparkline graphs (CPU, MEM, IO, NET, BAT) via xfce4-genmon-plugin; `color_bar` supports inverted mode (2nd arg `1`) for metrics where high=good (battery); padding bars (no prior data) always use non-inverted color to avoid false red on battery; history in `/tmp/sysmon-history`, 8 samples
- Battery indicator: `~/.dotfiles/xwindow/bin/battery-genmon` — standalone battery genmon (kept as fallback; battery now also in sysmon-genmon)
- Lock screen: `~/.dotfiles/xwindow/bin/random-lockscreen`
- Keyboard hotplug: keyd handles remapping at evdev level (no hotplug workaround needed)
- Sync scripts: `~/.dotfiles/script/sync_all` (all repos, triggered by `sync-repos.timer`), `sync_repo` (single repo), `jj_snapshot_all` (snapshot all jj repos via plocate)
  - `sync_all` calls `notify-webhook` on failure (currently disabled — awaiting Telegram bot setup)
  - `sync_repo` jj path: per-repo `flock` on `jj root` (workspaces sharing a repo lock together); skips empty changes (commit/describe only), describes with AI commit message (via `commit-msg` with `VERBOSE=1`), always pushes bookmarks; rebases local mutable chain onto updated bookmark after merge; uses `if(description, ...)` for empty description check (not `is_empty()` — doesn't exist in jj)
  - Auto-merge: fetches tracking branches, merges local bookmark forward via jj (no force), pushes to hj; tracks `bm@hj` after push
  - Prefixed bookmarks: delete+push via raw git (`hostname/bookmark`, server doesn't support `--force`); single `ls-remote` per run, skips if unchanged; excludes already-prefixed local bookmarks; no tracking of prefixed remote bookmarks (jj requires name match)
  - Requirements documented as comments in script: (1) commit with AI message if non-empty, (2) push all bookmarks with hostname prefix, (3) safely merge and push tracked bookmark
- Commit message generator: `~/.dotfiles/bin/commit-msg` — kiro-cli first (`--agent no-mcp`, stdin piping, 30s timeout), ollama + qwen2.5-coder:3b fallback (5s health check, started on demand), file-list final fallback; jj-first/git-fallback; `strip_ansi` removes ANSI/CSI/OSC escape sequences; `clean_msg` strips markdown fences and takes first line; `VERBOSE=1` enables detailed `log()` output to stderr (exit code, raw/cleaned output per backend)
- Notifications: `~/.dotfiles/bin/notify-webhook` — sends push notifications for script failures; currently disabled (exit 0), awaiting Telegram bot; KakaoTalk "나에게 보내기" tested but doesn't trigger push notifications; tokens in `private-dotfiles/kakao-tokens.json`
- Private dotfiles: `~/.dotfiles/private-dotfiles/` — gitignored colocated jj/git repo (git@github.com:beila/private-dotfiles.git); cloned by `script/bootstrap`; added as `git+file://` flake input (bootstrap locks to local clone); stores machine-specific config (host configs, kakao tokens, webhook URLs), Brazil JDK setup, and per-host `homeConfigurations`; zsh `**/*.zsh` glob auto-sources any .zsh files within; `install.sh` files run by `script/install` (called by bootstrap); `ssh.filesymlink/` provides SSH host aliases via `~/.ssh/config.d/`; `jj/install.sh` symlinks `user.toml` into `~/.config/jj/conf.d/`; see `private-dotfiles/AGENTS.md` for Brazil, flake input details, and how to add a new host
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
- TTS: `~/.dotfiles/bin/say` — piper-tts with en_GB-alba-medium voice, auto-downloads model on first run; `~/.dotfiles/bin/path.zsh` adds `bin/` to PATH
  - `say_done` calls `say` to announce when commands >10s finish (via `add-zsh-hook` in `zsh/config.zsh`); only on desktop machines (`$DISPLAY`/`$WAYLAND_DISPLAY`); runs in subshell `(say_done &)` to suppress background PID output
  - Override voice with `$PIPER_MODEL`
- TTS (Korean): `~/.dotfiles/bin/say-ko` — edge-tts with ko-KR-SunHiNeural voice (requires internet)
  - Default rate: +50%, override with `$EDGE_TTS_RATE`
  - Override voice with `$EDGE_TTS_VOICE` (available: ko-KR-SunHiNeural, ko-KR-InJoonNeural, ko-KR-HyunsuMultilingualNeural)

### Neovim Dev Tooling
- Config: `~/.dotfiles/nvim.configsymlink/` (symlinked to ~/.config/nvim; also ~/.vim via vim.symlink → nvim.configsymlink)
- Plugin management: all plugins installed via home-manager `programs.neovim.plugins`; no submodules remain; `.gitmodules` removed (vim.symlink was last entry, now a symlink to nvim.configsymlink)
- Config loading: nix generates `init.lua` (lua paths + `myinit.lua` content via `initLua`); `myinit.lua` sources `vimrc.symlink`; `vimrc.symlink` sources `myvimrc`; `myvimrc` runs `runtime! vimrcs/*.vimrc`, `vimrcs/*.nvimrc`, `vimrcs/*.lua`; `set verbosefile=~/.vim-messages.log` captures `:messages` output; `init.lua` is gitignored (nix-generated, changes on every `home-manager switch`); nvim 0.12 only loads `init.lua` (not `init.vim`/vimrc) when both exist
- Logs: `~/.vim-messages.log` (nvim messages), `~/.local/state/nvim/lsp.log` (LSP), `~/.local/state/nvim/mason.log` (Mason)
- Project-local config: `myvimrc` sources `.nvim.lua` from cwd or ancestors on `BufEnter` (via `vim.schedule` after lcd), per-buffer dedup
- Per-language setup: `vimrcs/my-<lang>.lua` — LSP via `vim.lsp.config.NAME = { ... }` + `vim.lsp.enable('NAME')`, DAP, filetype-specific config
  - my-awk.lua, my-cmake.lua, my-cpp.lua, my-css.lua, my-docker.lua, my-glsl.lua
  - my-haskell.lua, my-html.lua, my-java.lua, my-jinja.lua, my-js.lua (js/ts)
  - my-json.lua, my-just.lua, my-kotlin.lua, my-lua.lua, my-markdown.lua
  - my-nim.lua, my-nix.lua, my-python.lua, my-rust.lua (rustaceanvim, not vim.lsp.config), my-sql.lua
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
- Font: `gvimrc` — JetBrains Mono Thin:h11 (neovide guifont); guarded by `has("gui_running") || exists("g:neovide")` (neovide doesn't set `gui_running`); neovide's default fallback font (Source Code Pro) must be installed or it errors on startup
- Linting: `nvim-lint` plugin runs CLI linters (checkmake, hadolint, checkstyle, markdownlint-cli2, statix, deadnix) on save
- Tool installation: prefer nix (nvim.nix) over Mason; Mason only for DAPs not in nixpkgs
  - Coverage table in `nvim.nix` documents all tools per language with install location
  - Mason-only: bash-debug-adapter, codelldb, kotlin-debug-adapter, java-debug-adapter, debugpy
  - `bash` package in nvim.nix required by Mason installer

### Key Remapping Stack
- **keyd** (`~/.dotfiles/keyd/`, system daemon, four files):
  - `common` — shared bindings (included by all configs): CapsLock→Ctrl (tap→Esc), Super tap→prog1 (XF86TouchpadToggle, albert), Alt_L tap→prog2 (XF86TouchpadOn, ghostty1), Alt_R tap→prog3 (XF86TouchpadOff, ghostty2), Ctrl_R tap→apostrophe, Pause/ScrollLock/PrtSc→volume keys; note: keyd v2.6.0 maps prog1/2/3 to f21/f22/f23 (evdev 191/192/193), not KEY_PROG1/2/3
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
- fzf `--bind`: `transform(...)` parenthesis form breaks when the script body contains nested parens (e.g. `reload(...)`, `change-header(...)`); use colon form `transform:` instead
- nvim-treesitter `ensure_installed` + `auto_install` can fail trying to write to nix store (read-only); `auto_install = false` and `ensure_installed = {}` as workaround; treesitter module buffer-local keymaps may not attach — manual global keymaps used for incremental selection and swap; nvim-treesitter 1.0 (nvim 0.12) removed `nvim-treesitter.configs` module — `nvim-treesitter.lua` uses pcall to support both old and new API
- zsh vi mode: custom zle widget bindings must use `bindkey -M viins` and `bindkey -M vicmd` explicitly; plain `bindkey` only sets main (viins) — vicmd (normal mode) shows `^X` literal for unbound keys
- zsh fzf: `source <(fzf --zsh)` must come before custom bindkeys that reference fzf widgets (fzf-cd-widget, etc.); `zshrc.symlink` globs `**/*.zsh` alphabetically — don't put static copies of fzf scripts in the glob path
- zellij + kitty keyboard protocol: under rapid key repeat, zellij occasionally fails to parse CSI u sequences and passes raw bytes to child programs; worked around by sending legacy control codes from ghostty for ctrl-j/k/n/p
- C++ treesitter textobjects: `#make-range!` directives can silently fail; `@function.outer` misses lambdas and some edge cases; mini.ai pattern-based `f`/`a` is more reliable for C++ function calls and arguments
- Push notifications: Google Chat webhooks blocked by org admin; Slack app creation requires workspace admin approval; KakaoTalk "나에게 보내기" doesn't trigger push (messages to self are silent); Telegram bot or ntfy.sh are the viable options
- zellij `--close-on-exit` is unreliable — panes sometimes stay open after the command exits; `fzf-zellij` works around this by capturing the pane ID and closing explicitly via `zellij action close-pane`
- fzf `become` toggle output mismatch: when `_gy` toggles to `_gyy` via `become`, the new function's output (change ID) goes through the original function's post-processing pipeline (hex grep), producing wrong or empty results; same issue in reverse (`_gyy` → `_gy`); `_gh` ↔ `_ghh` is unaffected because both share the same output format
- jj template `description.is_empty()` doesn't exist — use `if(description, ...)` instead (empty string is falsy); `sync_repo` uses this for empty description check
- kiro-cli can't receive prompts as command-line arguments (hangs on large/complex input) — use stdin piping instead (`< file`)
- kiro-cli `--agent default` spawns MCP servers that become orphaned when kiro-cli exits — use `--agent no-mcp` for non-interactive/scripted use
- Cloud desktop (Amazon Linux): `apt` in PATH is JDK's Annotation Processing Tool, not Debian apt; `system-deps.sh` checks dnf/yum before apt-get; linuxbrew `dbus-run-session` has broken config — `gnome.nix` conditionally skipped when `/usr/bin/dconf` absent
- Nix flakes and gitignored files: flakes copy the git-tracked source tree to the store; files in root `.gitignore` are excluded; files in nested `.gitignore` (e.g. `home-manager.configsymlink/.gitignore`) may still be visible if the flake uses `?dir=` subdir; `path:` inputs within a git repo still require the path to be git-tracked; `git+file://` with a separate repo is the only way to include gitignored content without `--impure`
- Nix flakes `warn-dirty`: jj always has uncommitted changes (auto-snapshot); `nix eval` outputs `warning: Git tree has uncommitted changes` to stdout, breaking home-manager's `== "true"` string comparison for `homeConfigurations` key detection; fix: `warn-dirty = false` in `~/.config/nix/nix.conf`

### Monitors
- Current: 3 monitors — eDP-1 (1920x1200 laptop), DP-1 (3440x1440 ultrawide), DP-3 (1440x2560 portrait); varies by location
- Multi-monitor: configurations change frequently; `rescreenHook` with `hideNSPWorkspace` swaps NSP off visible screens after hotplug
- xfce4-panel bottom bar: 48px, using avoidStruts (panel struts issue was worked around)

### Sound System
- PipeWire with PulseAudio compatibility (pipewire-pulse)
- wpctl for device switching, amixer for volume control
- pavucontrol installed for GUI mixer
