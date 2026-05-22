# Dotfiles Workstation Setup — Context for AI Agent

## Agent Instructions

See `kiro.filesymlink/steering/instructions.md` for the canonical, always-loaded instruction set.

## TODO List

### High impact
- [ ] can't type hangul in zellij/ghostty
- [ ] **universal Copy/paste key** — copy/paste keys that work the same way in x window app, terminals, zellij, neovide, (neo)vim in terminals
- [ ] use fzf for zsh tab completion
- [ ] remove hostname-prefixed remote bookmarks from jj without deleting them from the server
- [ ] `_gy` ↔ `_gyy` toggle via `become` produces wrong output
  - after `become`, the new function's output goes through the original function's post-processing pipeline
  - `_gy` expects hex operation IDs (`grep -o "[0-9a-f]\{12,\}"`), but `_jyy` returns change IDs (lowercase alpha via `_jj_log_fzf`)
  - possible fix: unify output format or move post-processing into the `become` target so each function owns its own output pipeline
  - files: `fzf/functions.sh/functions.sh` — `_jyy()` (line ~222), `_jy()` (line ~263)
- [ ] make zellij floating point as big and more importantly as wide as appropriate while leaving slight context
- [ ] stop amazon-vpn when the network changes
- [ ] run systemd for user from nix

### Medium impact
- [ ] make focused window more noticeable but not ugly (currently red `focusedBorderColor` line)
  - options: pick a subtler border colour, or `borderWidth = 0` + picom shadow as the focus indicator
  - picom adds GPU/process overhead; only adopt if the visual win is worth it
- [ ] add squash feature to _gf
  - fzf shortcut (not enter) squashes the currently selected/highlighted file(s) from `@` into a target revision
  - opens `_gh` with a header explaining the squash context, minimise duplicated code
  - runs `jj squash --into <rev> -- <files>`
  - enter keeps current behaviour (output filenames)
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
- [ ] there's no gap between ghostty vertically
- [ ] make battery notification sticky
- [ ] make copilot key work as super
- [ ] replace absolute path from xfce settings
- [ ] review remaining mini-nvim modules: mini.splitjoin (toggle single/multi-line), mini.bracketed (unified [/] nav)

## Architecture Overview

### Dotfiles Repo: ~/.dotfiles
- Home Manager config: `~/.dotfiles/home-manager.configsymlink/`
  - `flake.nix` — inputs: nixpkgs, home-manager, nixGL (no `private-dotfiles` flake input — see "private-dotfiles" below for how it's resolved); `mkHost` builds a `homeManagerConfiguration` from shared modules + extra modules; `nixFilesFrom` auto-loads root `.nix` files from private-dotfiles as modules; private-dotfiles is resolved from `$HOME/.dotfiles/private-dotfiles` via `builtins.getEnv "HOME"` at eval time, so `home-manager switch --impure` is required (sentinel path falls back to empty when unavailable, so pure eval still succeeds); `hosts/*.nix` in private-dotfiles return `homeConfigurations` attrset fragments keyed by `username@static-hostname`; bare-username aliases for auto-detection live in `bare-aliases.nix` (see below); `nix.conf` `warn-dirty = false` required for home-manager auto-detection to work with jj (dirty tree warnings pollute `nix eval` stdout); `hm-session-vars.sh` sourced in `zshenv.symlink` (zsh not managed by home-manager)
  - `bare-aliases.nix` — at eval time, reads `/etc/hostname` (FQDN and short form both tried) and exposes any `user@<live-host>` entry under bare `user`, so `home-manager switch --impure --flake ~/.dotfiles/home-manager.configsymlink` (no explicit `#user@host`) auto-detects via `$USER`. Pure-eval-safe: empty `/etc/hostname` produces no aliases. **Caveat**: the flake snapshot is read from git's index, so any new file under `home-manager.configsymlink/` (or new `hosts/<hostname>.nix`) needs `git add` before the next switch — jj's auto-snapshot does not bridge to the git index for `git+file://` flake inputs.
  - `home.nix` — packages, unfree predicate (albert), battery-notify systemd timer (1min check, notify at 20%/10%)
  - `gnome.nix` — dconf settings (key repeat, mouse speed, cursor size 64, Korean input Sebeolsik 390, disable gnome-panel/desktop, empty gnome-panel layout as fallback), random-lockscreen systemd timer (daily wallpaper), gnome-flashback systemd drop-ins (xmonad session target requires gnome-flashback.target + service restart override)
  - `neovide.nix` — nixGL-wrapped neovide (GPU access on non-NixOS), font copying activation (JetBrains Mono + Nerd Font + Source Code Pro for neovide default fallback)
  - `nvim.nix` — neovim (default editor, vi/vim aliases), `initLua` sources `myinit.lua` (nix generates `init.lua` which overwrites `nvim.configsymlink/init.lua` on every switch — `init.lua` is gitignored), dev tool packages (LSPs, linters, formatters, DAP deps), rustaceanvim (Rust LSP); coverage table documents all tools per language
  - `xmonad.nix` — xmonad + contrib via nix 0.18, xfce4-panel + xfconf, xfconf dbus activation hook
  - `xdg.nix` — firefox-container desktop entry + mimeapps
  - `zmx.nix` — prebuilt zmx binary from zmx.sh (session persistence tool; source build via zmx's flake fails because zig2nix cannot vendor ghostty's `git+https?ref=HEAD` dependency)
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
  - `fzf-zellij` — drop-in `fzf-tmux` equivalent for zellij; runs fzf in a floating pane with FIFO stdin streaming and temp file output; `FZF_ZELLIJ=1` env var prevents nested floating panes on `become` toggles and strips `--height`/`--min-height`; `zellij run` stdout suppressed (prints pane name `terminal_##`); output post-processed to strip `\r` and residual `terminal_*` lines; `FZF_ZELLIJ_OUTPUT` exported for `become` targets via `_fzf_become` wrapper; falls back to plain fzf outside zellij
  - `test_fzf_zellij.sh` — automated tests; run with `bash fzf/test_fzf_zellij.sh` inside a zellij session
  - `functions.sh/functions.sh` — jj-first/git-fallback functions; each `_g*` dispatcher delegates to `_j*` (jj) or `_git_*` (git); `_jb`/`_jt` previews use `unique_boundary()` revset; `_jb` parses `jj bookmark list` output directly (indented remote-tracking lines like `  @hj …` get re-prefixed with the parent bookmark via awk so the row says `nix@hj …`); toggles via `become`: `_jh`↔`_jhh` (ctrl-h), `_jb`↔`_jbb` (workspaces, ctrl-b), `_jy`↔`_jyy` (op log, ctrl-y); ctrl-o inserts empty revision after selected (`jj new --no-edit --after`), uses `transform:` colon form for error display; fzf query preserved across toggles via `{q}`→`--query`; line-number focus uses `result:pos(N+1)+unbind(result)`
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
  - Normal mode: Alt-tab→Detach (triggers zellij-cycle session switch), Alt-w→session manager (built-in plugin), Ctrl-tab→next tab, Alt-h/j/k/l→MoveFocus, Alt-Shift-h/j/k/l→MovePane
  - Move mode: Alt-Shift-h/l→move tab left/right, Ctrl-Shift-h/j/k/l→move pane
- kiro config: `~/.dotfiles/kiro.filesymlink/` (individual files symlinked into ~/.kiro/) — agents/default.json (MCP TTS server, autoAllowReadonly), agents/no-mcp.json (no MCP servers, used by commit-msg to avoid orphaned processes), agents/builder.json (local override of the AmazonBuilderCoreAIAgents `builder` agent: adds TTS MCP server, narrowed `execute_bash` allowlist for read-only operations, allows `fs_write:*AGENTS.md` so Kiro can edit this file without prompting), settings/cli.json (default agent: builder, default model: claude-opus-4.7), kiro.filesymlink/bin/kiro-response (TTS fallback), bin/mcp-tts (MCP server for say/say_ko tools, kills previous playback via `setsid` + `kill -PGID`), bin/test_mcp_tts.sh (run with `bash bin/test_mcp_tts.sh`)
- Audio/brightness scripts: `~/.dotfiles/xwindow/bin/volume-osd`, `cycle-audio-output`, `cycle-audio-input`, `brightness-osd`
- Clipboard history: `copyq` (nix) — systemd user service, xmonad Super+V runs `copyq toggle`
- Weather script: `~/.dotfiles/xwindow/bin/weather-genmon` — wttr.in JSON API, python3 parser; 🌙 after sunset / before sunrise; tooltip: current + hourly + 3-day forecast
- System monitor: `~/.dotfiles/xwindow/bin/sysmon-genmon` — sparkline graphs (CPU, MEM, IO, NET, BAT) via xfce4-genmon-plugin; `color_bar` supports inverted mode for metrics where high=good (battery); history in `/tmp/sysmon-history`, 8 samples
- Battery indicator: `~/.dotfiles/xwindow/bin/battery-genmon` — standalone battery genmon (fallback; battery also in sysmon-genmon)
- Lock screen: `~/.dotfiles/xwindow/bin/random-lockscreen`
- Sync scripts: `~/.dotfiles/script/sync_all` (all jj/git repos via plocate, triggered by `sync-repos.timer`), `sync_repo` (single repo), `script/test_sync_repo.sh` (divergence/conflict/timeout test harness)
  - `sync_all` iterates `.jj`/`.git` markers under `$HOME` from plocate, filters noise paths (`.cache`, `.cargo`, `.nix-profile`, `node_modules`), and **deduplicates by `jj root` / `git top-level`** so monorepos with many submodule markers trigger sync_repo once per underlying repo root (not once per marker). Logs via `script/logger/log.sh` with tag `sync_all`: INFO lines for START + discovery count; ERROR summary + non-zero exit when any per-repo sync fails. Workspaces of the same repo are still iterated separately (each has its own `jj root`), which is intentional — each workspace has its own `@` to sync; sync_repo's flock then serializes them on the shared `jj git root` so they don't race the shared op log. Test harness: `script/test_sync_all.sh` (25 assertions; fake plocate / sync_repo / jj / git).
  - `sync_repo` jj path: per-repo `flock` keyed on `jj git root` (the shared `.git` path), NOT `jj root` — multiple workspaces of the same repo (e.g. `~/dev/{pro,pro2,sawt}/src/IgnitionX`) share one `.jj/repo` store + op log via `~/brazil-repos/IgnitionX/.jj`, so locking on the per-workspace `jj root` allows concurrent runs to race the shared op log (visible as branching `workspace update-stale` ops) and ping-pong the shared `sync.bookmark` between each workspace's `PUSH_REV`, producing divergent change_ids; exits early if no `backup` remote (checks both `jj git remote list` and falls back to `git remote get-url backup`; additional defensive check for empty `BACKUP_URL`); `jj git root` falls back to `git rev-parse --git-dir` when jj's view is degraded (stale op log). Single `jj log -r @` call snapshots atomically; runs `jj new` on non-empty OR empty-merge `@`; describes with AI commit message (via `commit-msg` with `VERBOSE=1`); uses `if(description, ...)` for empty description check (jj has no `description.is_empty()`). `LOG_CONTEXT` derived from path-relative-to-home (not basename) so different workspaces/worktrees of the same-named repo don't collide in log filenames (e.g. `~/dev/pro/src/IgnitionX` → `pro-src-IgnitionX`, `~/dev/pro2/src/IgnitionX` → `pro2-src-IgnitionX`).
  - Tracked bookmark: reads `sync.bookmark` from per-repo jj config (`jj config set --repo sync.bookmark NAME`); skips fetch/rebase/push when not set
  - Workspace name: matched by current `@` commit_id against `jj workspace list`
  - Reconcile (Step 2): explicit four-way ancestry between `LOCAL_BM_REV` and `REMOTE_REV` — equal → SKIP; local ancestor of remote → fast-forward local (no push); remote ancestor of local → push local (ahead, no `--allow-new` since remote bookmark exists); diverged → pre-flight conflict probe via `jj new --no-edit LOCAL_BM_REV REMOTE_REV -m "rebase-probe"`. Probe shares conflict semantics with the actual rebase (both reduce to the same 3-way merge of common-ancestor / L / R), so a clean probe guarantees a clean rebase. Conflicted probe: report filenames (`jj resolve --list`), abandon, leave bookmarks untouched, log `REBASE-CONFLICT` and skip push — next sync retries after user resolves on either side. Clean probe: abandon, then `jj rebase -s 'roots(::LOCAL_BM_REV ~ ::REMOTE_REV)' -d REMOTE_REV` — rebases the entire local-only chain onto remote. `change_id` is preserved by rebase, so the tracked bookmark auto-follows; the rebased tip is a descendant of `REMOTE_REV`, so the push is a fast-forward (no `--force-with-lease` needed). The new-remote case (`REMOTE_REV` empty) keeps a separate `--allow-new` push since `jj new --no-edit L ""` doesn't work. Fetch failure (TIMEOUT/NETWORK-ERR) skips the entire Step 2 with `SKIP-PUSH <bm>: fetch failed`; otherwise stale `${BM}@backup` would lead to wrong-path pushes (e.g. mistaking an existing remote bookmark for new and trying full-history push that fails on any no-description ancestor).
  - Ambiguous-bookmark handling: resolves `$LOCAL_BM_REV` to a commit_id BEFORE fetch so post-fetch revsets don't fail when the bare bookmark name becomes conflicted (local vs remote). Probe creation (`jj new --no-edit`) and rebase are checked for success and log `REBASE-PROBE-FAIL`/`REBASE-FAIL` (CRITICAL, notified) instead of silently falling through. The probe commit is located via `latest(L+ & R+, 1)` (newest child of both parents); using `description(exact:...)` would require escaping jj's trailing-newline semantics.
  - Hang prevention: every git/jj network call is wrapped in `timeout_cmd` (default `SYNC_REPO_CMD_TIMEOUT=60s`, override via env). `GIT_SSH_COMMAND` sets `ConnectTimeout=10`, `ServerAliveInterval=15`, `ServerAliveCountMax=3`, `BatchMode=yes` so stalled SSH connections die fast and can't prompt.
  - Event logging via `script/logger/log.sh` (level per event tag): `FETCH-OK`, `PUSH-OK`, `FAST-FORWARD`, `SKIP`, `SKIP-PUSH` (fetch-failed), `NO-BACKUP-URL`, `START` at INFO; `NETWORK-ERR`, `TIMEOUT`, `BENIGN-DEL` (remote ref doesn't exist), `SKIP-PUSH` (delete-failed) at WARN/DEBUG (transient, not notified); `OTHER-ERR`, `REBASE-CONFLICT` at ERROR (notified); `REBASE-PROBE-FAIL`, `REBASE-FAIL` at CRITICAL (notified). `classify_cmd` wraps each network call and routes failures to NETWORK-ERR / OTHER-ERR / BENIGN-DEL based on stderr pattern matching.
  - Prefixed bookmarks: delete+push via raw git (`hostname/bookmark`); single `ls-remote` per run, skips if unchanged
  - Workspace snapshot bookmark (Step 0): creates `hostname/workspace` bookmark at `PUSH_REV`, force-pushes via raw git
- Output writer/decorator: `~/.dotfiles/bin/logrun` — wraps a command to tee its combined stdout/stderr into a timestamped log file (ANSI stripped) AND pipe the live stream through a decorator (`spacer` → visual break on output pauses, then `watchlog` → "idle for Ns" indicator; both fall back to `cat` if not installed). Flags: `--name`, `--log-dir`, `--log-path`, `--decorator`/`--no-decorator`, `--fail-suffix` (default `FAILED.txt`; empty disables rename), `-c`/`--command` (run via `bash -c`). Env: `log_path` pre-sets the target path (nested recipes pass it down); `build_dir` is the default log dir if it exists, else `./build`, else `/tmp`; `LOGRUN_DECORATOR` overrides the decorator pipeline. `recurse-brazil.just`'s `run` recipe (the leaf used by every `j`/`n`/`jr`/`nijr` zsh wrapper) shells out to it — so any command funnelled through those wrappers picks up the log + decorator for free. Companion `bin/logrun-move NEW_DIR` relocates the active logrun log to a different directory mid-run (preserves the filename); only works when invoked as a descendant of `logrun` since it talks to the wrapper via `$LOGRUN_PID` / `$LOGRUN_MOVE_FILE`. Test harness: `bin/test_logrun.sh` (naming, ANSI strip, fail-suffix rename, env inheritance, sanitisation, custom decorator, usage errors).
- Commit message generator: `~/.dotfiles/bin/commit-msg` — provider chain: claude (`--print --tools "" --no-session-persistence`, skipped when `$CLAUDECODE` is set so a `claude` session never spawns a child claude) → kiro-cli (`--agent no-mcp`, stdin piping) → ollama + qwen2.5-coder:3b fallback (5s health check, started on demand) → capped file-list final fallback (first 3 files + `and N more`, 200-char hard cap; includes deleted files); jj-first/git-fallback; `VERBOSE=1` enables detailed output. For jj merge commits (parents.len() > 1) the prompt is augmented per-parent: compute `unique_revset = (::P ~ ::others) ~ ::(merges() & (::P ~ ::others) ~ P)` (linear run on P's side since previous merge), take the cumulative diff from `roots(unique_revset)-` (parent of the oldest unique commit = previous merge on that side) to P via `jj diff --from START --to P --git`. If that side diff is ≤ `MAX_MERGE_DIFF_LINES` (default 500, env-overridable) it goes into the prompt; else fall back to a per-commit description list. This gives the LLM code-level context for merges instead of commit-subject boilerplate.
- Leveled logger: `~/.dotfiles/script/logger/log.sh` — sourceable shell library providing `log LEVEL "msg"`. Levels: `DEBUG < INFO < WARN < ERROR < CRITICAL`. Call-site declares the level explicitly (shared across multiple scripts; implicit classification is fragile). Writes to `$LOG_ROOT/<machine>/<tag>[.<context>].<date>[.<time>].log`; the first run of a day takes the undecorated name, subsequent runs the same day add `.HHMMSS`. **Retention + temp-file buffering**: during a run, every log line goes to a `/tmp/log.<tag>.XXXXXX` temp file; `$LOG_ROOT` is never touched mid-run. On `log_finalize` (auto-called on EXIT), if the run recorded at least one event at level ≥ `LOG_KEEP_THRESHOLD` (default `ERROR`) the temp file is moved into place at `$LOG_ROOT/...`; otherwise the temp file is deleted. This is critical when `$LOG_ROOT` lives inside a synced jj/git repo (like `~/hjdocs/logs`): the log file never changes the repo's working copy while scripts that sync that same repo are running, so no self-referential race. `LOG_KEEP_THRESHOLD=DEBUG` keeps every run; `LOG_KEEP_THRESHOLD=NEVER` always deletes. The auto-installed EXIT trap is safe in subshells (trap text is inherited but dormant; our `trap log_finalize EXIT` affects only the current shell). Callers that set their own EXIT trap AFTER sourcing must call `log_finalize` manually. Required env: `LOG_TAG`. Optional: `LOG_CONTEXT` (e.g., repo basename — appears in filename and log lines), `LOG_ROOT` (default `~/.local/state/logs`; overridden to `~/hjdocs/logs` via `private-dotfiles/env.zsh` for zsh and `private-dotfiles/logger.nix` for systemd so logs replicate across machines), `LOG_REL_BASE` (notification paths are shown relative to this; defaults to `$LOG_ROOT`, overridden to `~/hjdocs` so notifications say e.g. `logs/taygeta/sync_repo.xxx.log`), `LOG_NOTIFY_THRESHOLD` (default `ERROR`), `LOG_NOTIFY_MODE` (`auto`|`always`|`never`; default `auto` suppresses notifications when stderr is a TTY so manual runs don't ping the phone), `LOG_NOTIFY_CMD` (default `bin/notify-webhook`), `LOG_NOTIFY_DEDUP_WINDOW` (seconds; default `21600` = 6h; set `0` to disable) and `LOG_NOTIFY_DEDUP_DIR` (default `$LOG_ROOT/.notify-dedup`) — suppresses re-notification of the same (TAG, CONTEXT, LEVEL, normalized-message) signature within the window. Normalization collapses hex IDs ≥8 chars and digit runs ≥2 chars. Dedup state writes are ALSO deferred to `log_finalize` (buffered in `_LOG_PENDING_DEDUP_KEYS`) so `$LOG_NOTIFY_DEDUP_DIR` under `$LOG_ROOT` isn't touched mid-run either. Within a single process the in-memory list always suppresses duplicates; across processes the window/on-disk mtime applies. `LOG_MACHINE_NAME` (default from `hostnamectl --pretty`). Also exposes `log_file()` (returns the currently-active path — temp during the run, final after finalize) and `log_finalize()` for manual cleanup. CLI wrapper at `~/.dotfiles/script/logger/bin/dlog` (added to `$PATH` via `path.zsh`; named `dlog` rather than `log` because zsh has a `log` builtin that shadows PATH entries); each CLI invocation is an independent "run". Notifications reference the FINAL path (even before finalize) so the link opens the file after the process exits. Interactive stderr is colored by level (dim/plain/yellow/red/bold-red). Context sanitization strips slashes, whitespace, and leading `.`/`-` from `LOG_CONTEXT` so filenames stay clean. Test harness: `script/logger/test_log.sh` (49 assertions; run with `bash script/logger/test_log.sh`).
- Notifications: `~/.dotfiles/bin/notify-webhook` — dispatcher for structured alerts. Flags: `-t TITLE`, `-p {low|normal|high|urgent}`, `-u URL`. Backends live in `~/.dotfiles/script/logger/backends/<name>.sh` and must define `notify_send TITLE PRIORITY URL MESSAGE`. Selection priority: explicit `$NOTIFY_BACKEND` env var → auto-detect (`telegram.env` present → `telegram`) → `none`. Missing credentials or unknown backend = silent no-op (exit 0) so machines without configuration don't fail. Backends: `telegram.sh` (reads `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` from `private-dotfiles/telegram.env`; posts to Telegram Bot API with HTML formatting; `low` priority → `disable_notification=true`, `high`/`urgent` add 🟠/🔴 to the title; 5s curl timeout), `none.sh` (no-op default), `mock.sh` (test helper — writes TSV lines to `$NOTIFY_MOCK_FILE`).
- Telegram setup: create a bot via `@BotFather` → `/newbot`; send any message to the new bot from your account; fetch your chat id via `curl -s "https://api.telegram.org/bot<TOKEN>/getUpdates"` (look for `chat.id`); save `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID` in `~/.dotfiles/private-dotfiles/telegram.env` (chmod 600). Test with `notify-webhook -t test -p high "hello"`. Revoke and rotate the token via BotFather if it's ever exposed.
- Private dotfiles: `~/.dotfiles/private-dotfiles/` — gitignored colocated jj/git repo; resolved at flake eval time via `builtins.getEnv "HOME"` (requires `home-manager switch --impure`); stores machine-specific config (host configs, tokens, webhook URLs), Brazil JDK setup, and per-host `homeConfigurations`; zsh `**/*.zsh` glob auto-sources; `install.sh` files run by `script/install`; `ssh.filesymlink/` provides SSH host aliases; `telegram.env` holds `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` for the notify-webhook Telegram backend; `logger.nix` writes `~/.config/environment.d/20-logger.conf` so systemd-launched jobs inherit `LOG_ROOT`/`LOG_REL_BASE`. See `private-dotfiles/AGENTS.md` for Brazil setup, the impure-eval rationale, and how to add a new host
- Zellij session cycler: `~/.dotfiles/bin/zellij-cycle` — wraps `zellij attach --create` in a loop; on detach cycles to next active session; supports session names with spaces; numeric argument (e.g. `1`, `2`) attaches to the Nth existing session instead of a named one
- zmx session picker: `~/.dotfiles/bin/zmx-select` — fzf picker over `zmx list`; Enter attaches highlighted, Ctrl-N creates a new session with the typed name (auto-suffixes `-2`, `-3`... if the name is already in use), Ctrl-C exits. Skips the picker and attaches directly to a default session (CLI arg, `$ZMX_DEFAULT_SESSION`, or `main`) when no sessions exist
- Network printer CLI: `~/.dotfiles/script/bin/print-hp` — sends a file to an HP network printer via raw JetDirect (TCP port 9100), bypassing CUPS entirely. Exists because some CUPS print servers (seen with Synology bundled CUPS 1.5 + `rastertogutenprint`) silently drop PDF jobs. Discovery order: `--ip`/`$PRINT_HP_IP` → cached IP verified via 8s `/dev/tcp` probe (regardless of age — printers keep DHCP leases for days; 8s tolerates sleeping printers waking up on the TCP handshake) → `nmap` scan of the subnet. Cache file at `${XDG_CACHE_HOME:-~/.cache}/print-hp/hp-ip`; touched on successful reuse. Accepts `.pdf` (converted via `pdftops`), `.ps`/`.eps` (sent as-is), and text (via `enscript` if installed, raw otherwise). Defaults: A4, duplex long-edge, subnet `192.168.1.0/24` (override with `$PRINT_HP_SUBNET` — e.g. set to `192.168.4.0/22` in `private-dotfiles/env.zsh` for Hojin's home LAN). Flags: `-d`/`--discover` (print IP and exit), `-i`/`--ip` (skip discovery), `-s`/`--simplex`, `-n`/`--no-cache` (force rescan), `--pages RANGE` (PDF-only; `N`, `N-M`, `N-`, or `-M` → passed to `pdftops -f/-l`), `--dry-run` (skip sending; leaves the converted payload at a printed path). Requires `nmap` (installed via `home.nix`, with `nix run nixpkgs#nmap` fallback), `ncat`/`nc`, `pdftops` (poppler).
- plocate updatedb: `~/.dotfiles/script/updatedb` — runs every 10min via updatedb.timer (home.nix `OnCalendar="*:0/10"`). Uses `log.sh`; classifies failures (disk full / permission / read-only FS / generic) with actionable messages. Slow-run threshold `UPDATEDB_THRESHOLD=30s` (override via env) logs WARN + desktop popup. Test harness: `script/test_updatedb.sh` (20 assertions; fake `updatedb` binary via PATH).
- Battery notify: `~/.dotfiles/script/battery-notify` — systemd timer every 1min. While discharging, fires a staged set of OSDs (each stage subsumes the earlier ones — once stage N has fired, lower-numbered stages never re-fire within the same discharge cycle): `warn:30` (yellow `battery-osd`, once), `warn:20` (yellow `battery-osd` + `notify-send`, once), `warn:15` (yellow `battery-osd`, once), `crit:<n>` (red `battery-osd`, re-fires on every percent change while still ≤10% so the user keeps noticing the trend). State file holds the last-fired stage tag (`warn:30` / `warn:20` / `warn:15` / `crit:<capacity>`); rank ordering means a jump from 50% straight to 12% skips warn:30/20 and fires warn:15 directly. Charging/full/unknown clears the state so the next discharge cycle restarts at warn:30. `battery-osd` accepts `--style {warn|critical}` (yellow / red). Env-overridable for tests: `BATTERY_NOTIFY_BAT_DIR`, `BATTERY_NOTIFY_POWER_SUPPLY_DIR`, `BATTERY_NOTIFY_STATE_FILE`, `BATTERY_OSD_BIN`. Test harness: `script/test_battery-notify.sh` (66 assertions; fake sysfs + stubbed notify-send and battery-osd; sets `LOG_KEEP_THRESHOLD=DEBUG` so INFO/WARN log lines persist for assertions).
- Battery OSD: `~/.dotfiles/xwindow/bin/battery-osd.py` — thin invocation script (argparse → call into `osd` library). Built as the `battery-osd` binary via `pkgs.writers.writePython3Bin` in `home.nix`, with the local `osd` Python package as a library dep.
- OSD library: `~/.dotfiles/xwindow/osd/` — local Python package (pyproject.toml + `src/osd/__init__.py`) providing the cairo + XShape OSD primitives. Built via `pkgs.python3Packages.buildPythonPackage` in `home.nix`. Public API: `OSDStyle` (dataclass: colours, font, layout, anchor, multi-monitor sizing), `render_surface(text, w, h, style)` → `cairo.ImageSurface`, `display_on_all_monitors(text, duration, style)` → one-shot show, `get_monitors(d, root)` → active CRTC rects via Xrandr (de-duped, falls back to whole virtual screen). Renders text with cairo (configurable fill / outline / drop shadow), then displays in override-redirect X windows whose XShape mask is derived from the rendered alpha channel — the "background" is genuinely transparent (XShape clips), so the OSD is highly visible without painting a coloured block. Works without a compositor. Multi-monitor: shows one window per active CRTC, sized to that monitor by default (`per_monitor_size=True`). Splits cairo→X `PutImage` calls into row chunks because python-xlib doesn't use BIG-REQUESTS for those ops (16-bit length cap → ~256 KB per request). Catches SIGTERM/SIGINT for clean window teardown. Designed to be reused by future migrations of `volume-osd`/`brightness-osd`/`audio-{out,in}-osd` from dzen2.
- Random lockscreen: `~/.dotfiles/xwindow/bin/random-lockscreen` — daily systemd timer. Uses `log.sh`; WALLPAPER_DIR env-overridable (default `~/Pictures/Favourites`); actionable ERRORs for missing dir, empty dir, DBus/schema unreachable, gsettings missing. **HEIC handling**: candidates include `*.heic`; if a HEIC is picked, the script transcodes it to JPG (full resolution, q≈92) into `${XDG_CACHE_HOME:-~/.cache}/random-lockscreen/<basename>.<src-mtime>.jpg` and sets `picture-uri` to the cached file. Cache key includes source mtime so re-saves trigger re-conversion; older mtime variants for the same basename are removed before writing. ffmpeg over ImageMagick because Ubuntu's `convert-im6.q16` ships a buggy HEIC reader (`error/heic.c/IsHEIFSuccess/139`); ffmpeg's libavcodec unwraps the embedded HEVC/MJPEG stream cleanly. Conversion failure logs WARN and re-rolls to a non-HEIC candidate. Why not skip HEIC entirely: gnome-shell on this machine inherits `GDK_PIXBUF_MODULE_FILE` from a Nix-store `loaders.cache` (set by librsvg's home-manager wrapper) that has no HEIF loader, so a raw HEIC URI silently renders as the primary fallback colour (black) on the lock screen — converting to JPG sidesteps gdk-pixbuf's loader set entirely. Test harness: `script/test_random-lockscreen.sh` (23 assertions + 1 skip when real gsettings on PATH; fake wallpaper dir + stubbed gsettings).
- zsh config: standalone files in `~/.dotfiles/zsh/` (zprezto fully removed)
  - `zshenv.symlink` — sets `$DOTFILES_ROOT` via `%N`, sources `*/path.zsh`
  - `zshrc.symlink` — sources `**/*.zsh` (excludes path.zsh, completion.zsh); completion.zsh sourced last
  - `environment.zsh` — smart URLs, setopt, jobs, colored man pages
  - `terminal.zsh` — window/tab/pane titles via precmd/preexec
  - `editor.zsh` — vi mode, dot expansion, key bindings, vim-surround, text objects. `KEYTIMEOUT=1` and `zle-line-init` forces insert mode on every new prompt so stray escape sequences (e.g. from zmx re-attach or kitty keyboard protocol) don't silently leave ZLE in vicmd mode. Bindkey setup is skipped when `! -o shinstdin` (e.g. under `zsh -ic 'cmd'`) because terminfo keycaps aren't populated yet
  - `history.zsh` — 10M entries, dedup, HIST_IGNORE_SPACE disabled
  - `directory.zsh` — auto_cd, auto_pushd, extended_glob, no clobber
  - `utility.zsh` — correction, nocorrect/noglob aliases, colored ls/grep
  - `completion.zsh` — compinit, caching, fuzzy match, case-insensitive, menu select, AWS bashcompinit
  - `syntax-highlighting.zsh` — fast-syntax-highlighting (nix)
  - `autosuggestions.zsh` — zsh-autosuggestions (nix)
  - `git.zsh` — git aliases, no git-flow
  - `gnu-utility.zsh` — g-prefixed GNU utils on macOS, no-op on Linux
  - `p10k.zsh` — powerlevel10k (nix) + user config
- zsh functions: `~/.dotfiles/zsh/functions/c` (copy), `p` (paste), `o` (open), `say_done` (TTS notification), `ju` (jj unique), `jda` (jj describe with AI commit-msg; prints the generated description) — Wayland/X11 aware
- TTS dispatcher: `~/.dotfiles/bin/say` — routes by content language. Hangul (U+AC00–U+D7A3) → `say-ko`, otherwise → `say-en`. Accepts text as args or stdin.
- TTS (English): `~/.dotfiles/bin/say-en` — piper-tts with en_GB-alba-medium voice, auto-downloads model; override voice with `$PIPER_MODEL`
  - `say_done` calls `say` to announce when commands >10s finish; only on desktop machines; runs in subshell
- TTS (Korean): `~/.dotfiles/bin/say-ko` — edge-tts with ko-KR-SunHiNeural voice (requires internet)
  - Default rate: +50%, override with `$EDGE_TTS_RATE`; override voice with `$EDGE_TTS_VOICE`
- Claude Code Stop hook: `~/.dotfiles/bin/claude-stop-tts` — reads `last_assistant_message` from the Stop hook stdin JSON (authoritative current-turn text; the `transcript_path` file lags Stop firing by several seconds and would replay the *previous* turn). Picks the last paragraph starting with `요약:`, strips that prefix so TTS speaks only the summary content (the user doesn't want "summary" announced every turn), strips markdown, caps to `$CLAUDE_TTS_MAX_CHARS` (default 500), and pipes to `say` (which routes by language). Falls back to the last non-empty paragraph when no `요약` marker exists, and falls back to parsing `transcript_path` if `last_assistant_message` is missing (older Claude Code). Spawns via `setsid` so audio outlives the turn. Debug log at `~/.local/state/claude-stop-tts.log` (override via `$CLAUDE_TTS_LOG`; auto-trimmed to 1000 lines when over 2000). Wired into `~/.claude/settings.json` `hooks.Stop`.

### Neovim Dev Tooling
- Config: `~/.dotfiles/nvim.configsymlink/` (symlinked to ~/.config/nvim; also ~/.vim via `~/.dotfiles/vim.symlink` → `nvim.configsymlink`). If the `~/.vim/myvimrc` path is unreachable on a machine (vim.symlink missing/broken), `vimrc.symlink`'s `source ~/.vim/myvimrc` will error and abort everything downstream in `init.lua`. Fix via `ln -sfn nvim.configsymlink ~/.dotfiles/vim.symlink`.
- Plugin management: all plugins installed via home-manager `programs.neovim.plugins`; no submodules
- Config loading: nix generates `init.lua` (lua paths + `myinit.lua` content via `initLua`); `myinit.lua` sources `vimrc.symlink`; `vimrc.symlink` sources `myvimrc`; `myvimrc` runs `runtime! vimrcs/*.vimrc`, `vimrcs/*.nvimrc`, `vimrcs/*.lua`; `init.lua` is gitignored (nix-generated); nvim only loads `init.lua` (not `init.vim`/vimrc) when both exist
- Logs: `~/.vim-messages.log` captures vim's verbose output AND any `:echoerr` / plugin error messages (via `set verbosefile=~/.vim-messages.log` in `myvimrc`). Rotated to `~/.vim-messages.log.old` at nvim exit when > 1MB (see `myvimrc` autocmd). `~/.local/state/nvim/lsp.log` has full LSP RPC traffic; `~/.local/state/nvim/mason.log` has Mason installer output. Debug recipe: `grep -i '<pattern>' ~/.vim-messages.log{,.old} 2>/dev/null` for error strings; `tail -50 ~/.local/state/nvim/lsp.log` for LSP issues. Inside a running nvim: `:messages` (history), `:messages clear` (drops in-memory copy; doesn't rotate the file).
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
- Tabline: `vimrcs/my-tabline.lua` — custom `&tabline` showing `<tabnr> <path>` per tab (strips `$HOME/`, elides middle with `…` under tight budgets). Replaces nvim's default (which prepended a window-count digit) and airline's tabline extension (disabled in `vim-airline.vimrc`). Tab number highlighted via `MyTabNum`.
- Indent detection: vim-sleuth (auto-detects tabstop/shiftwidth)
- Limelight: `my-text.lua` — auto-enabled for text, markdown, rst, org, asciidoc, tex, mail, gitcommit
- Table mode: `my-markdown.lua` — `silent! TableModeEnable` on markdown FileType
- fzf-lua: `vimrcs/fzf.lua` — `<leader>f` jj/git tracked files (ctrl-g toggles submodule files, ctrl-f toggles all files, query preserved), `<leader>F` all files, `<C-g><C-f>` changed files, ctrl-n/p preview scroll
- Font: `gvimrc` — JetBrains Mono Thin:h11 (neovide guifont); Source Code Pro must be installed for neovide fallback
- Linting: `nvim-lint` runs CLI linters (checkmake, hadolint, checkstyle, markdownlint-cli2, statix, deadnix) on save
- Tool installation: prefer nix (nvim.nix) over Mason; Mason only for DAPs not in nixpkgs (bash-debug-adapter, codelldb, kotlin-debug-adapter, java-debug-adapter, debugpy); `bash` package in nvim.nix required by Mason installer
- Amazon-internal plugin loader: `~/.dotfiles/private-dotfiles/nvim-amazon.nix` appends a snippet to `programs.neovim.initLua` (`lib.mkAfter`) that prepends `~/hjdocs/public-docs/nvim-amazon` to `&runtimepath`. That path holds a plugin (`plugin/init.lua`, `plugin/fugitive-gitfarm.vim`) providing Barium LSP for Brazil Config files, Bemol workspace-folder support, and `:Gbrowse` integration with code.amazon.com. Kept in private-dotfiles so the public dotfiles repo doesn't leak a reference to Amazon-internal resources. Guarded on `vim.fn.isdirectory` so machines without the hjdocs checkout are unaffected.

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
- Super+S → `scrot -s` selection screenshot to clipboard (image/png via xclip)
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
- Two independent ghostty instances (scratchpad1, scratchpad2), each running `zellij-cycle` with a numeric index (1/2) — attaches to the Nth existing zellij session, falls back to creating `main-N`
- `scratchpadToggle`: focused→hide, visible elsewhere→focus, hidden→bring to current workspace+float+focus
- `adaptiveFloat` manage hook: landscape→side-by-side halves, portrait→stacked halves, 2% margins
- `refloatAdaptive`: repositions scratchpad to match current screen orientation on every show

### Zoom Notification
- `zoom_linux_float_message_reminder`: floats on all workspaces without stealing focus
- `annotate_toolbar`: shifted to 8:meeting by the general zoom rule + floated via a dedicated `doFloat` rule in `meetingRules`. No `title /=?` exclusion is needed because `composeAll` stacks rules (shift + float) additively — the `zoom_linux_float_*` exclusions exist only to stop those windows from being shifted at all, which isn't what we want for the annotate bar.
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
- Push notifications: Google Chat webhooks blocked by org admin; Slack requires workspace admin; KakaoTalk "나에게 보내기" doesn't trigger push. Chose Telegram bot (see Notifications + Telegram setup sections); ntfy.sh remains a viable alternative via a new backend under `script/logger/backends/`.
- fzf `become` toggle output mismatch: `_gy`↔`_gyy` output goes through wrong post-processing pipeline; `_gh`↔`_ghh` unaffected (same output format)
- kiro-cli can't receive prompts as command-line arguments (hangs on large input) — use stdin piping
- kiro-cli `--agent default` spawns MCP servers that become orphaned on exit — use `--agent no-mcp` for scripted use
- Cloud desktop (Amazon Linux): `apt` in PATH is JDK's Annotation Processing Tool, not Debian apt; `system-deps.sh` checks dnf/yum first; linuxbrew `dbus-run-session` has broken config — `gnome.nix` conditionally skipped when `/usr/bin/dconf` absent
- Nix flakes and gitignored files: flakes copy git-tracked source tree to store. Two ways to include gitignored content: (1) keep it in a separate colocated repo and use `git+file://` (no `--impure` needed but flake.lock then bakes a per-machine path — bad for portability), or (2) resolve the path from `$HOME` via `builtins.getEnv` at eval time and run `--impure` (portable flake.lock — this is what private-dotfiles uses).
- Nix flakes `warn-dirty`: jj always has uncommitted changes; `nix eval` outputs warning to stdout, breaking home-manager's string comparison; fix: `warn-dirty = false` in `~/.config/nix/nix.conf`
- jj revset `empty()` vs template `empty`: the revset predicate excludes commits that contain conflicts, even when the template keyword `empty` reports them as empty. So `files(X) & empty()` (revset) will NOT match conflict-only auto-merges; use `-T 'if(empty, …)'` (template) when you need the merge-with-no-user-work semantics (e.g., filtering out boilerplate merges in `jj-untrack-files`, `commit-msg`).
- jj revset `diff_lines(regex:".", X)` vs `files(X)`: `diff_lines` matches only commits with visible diff text in X, which means submodule pointer changes, mode-only changes, and binary-only changes are NOT matched (gitlinks have no textual content). Use `files(X)` when you need tree-level change detection; use `diff_lines` when you want to ignore conflict-only tree diffs on merges.
- input-remapper after Bluetooth reconnect: when a BT mouse/trackball drops + re-attaches mid-session, the daemon's internal device list goes stale and autoload doesn't re-apply to the new evdev node — `xinput list` shows BOTH the original device AND `input-remapper <name> forwarded`, but real button presses pass through unmapped. First try `input-remapper-control --command autoload`; if that still says "Device unknown", restart the daemon: `sudo systemctl restart input-remapper-daemon`. If this happens repeatedly, automate via a udev rule that triggers `autoload` on `add` events for the device, or a systemd path/dispatcher hook.

### Monitors
- Current: 3 monitors — eDP-1 (1920x1200 laptop), DP-1 (3440x1440 ultrawide), DP-3 (1440x2560 portrait); varies by location
- Multi-monitor: configurations change frequently; `rescreenHook` with `hideNSPWorkspace` swaps NSP off visible screens after hotplug
- xfce4-panel bottom bar: 48px, using avoidStruts

### Sound System
- PipeWire with PulseAudio compatibility (pipewire-pulse)
- wpctl for device switching, amixer for volume control
- pavucontrol installed for GUI mixer
