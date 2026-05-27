# script — Context for AI Agent

`~/.dotfiles/script/`. Periodic-job scripts (sync, updatedb, flake-update, battery-notify) plus a few one-off helpers. Logging and notifications live in `script/logger/` — see `script/logger/AGENTS.md`.

Most jobs are scheduled via `dotfiles.schedule` (see `home-manager.configsymlink/AGENTS.md`); the backend is systemd-user where available and cron elsewhere.

## Sync scripts

- **`sync_all`** — run by the `sync-repos` schedule. Iterates `.jj`/`.git` markers under `$HOME` from plocate, filters noise paths (`.cache`, `.cargo`, `.nix-profile`, `node_modules`), and **deduplicates by `jj root` / `git top-level`** so monorepos with many submodule markers trigger `sync_repo` once per underlying repo root (not once per marker). Logs via `script/logger/log.sh` with tag `sync_all`: INFO lines for START + discovery count; ERROR summary + non-zero exit when any per-repo sync fails. Workspaces of the same repo are still iterated separately (each has its own `jj root`), which is intentional — each workspace has its own `@` to sync; sync_repo's flock then serializes them on the shared `jj git root` so they don't race the shared op log. Test harness: `script/test_sync_all.sh` (27 assertions; fake plocate / sync_repo / jj / git).
- **`sync_repo`** — per-repo. Per-repo `flock` keyed on `jj git root` (the shared `.git` path), NOT `jj root` — multiple workspaces of one repo share a single `.jj/repo` store + op log, and locking on the per-workspace path lets concurrent runs race the shared op log. Snapshot prep: single `jj log -r @` resolves `PUSH_REV` atomically; runs `jj new` on non-empty OR empty-merge `@`, then `commit-msg` for description. `LOG_CONTEXT` is path-relative-to-home with `/`→`-`, so workspace-name collisions don't pile into the same log file. **Both `sync_all` and `sync_repo` `unset LOG_ROOT LOG_REL_BASE LOG_NOTIFY_DEDUP_DIR` before sourcing log.sh** to land logs in `~/.local/state/logs/` instead of `~/hjdocs/logs/` (avoids self-referential race with the repo it's syncing). Test harnesses opt out via `SYNC_LOG_ROOT_KEEP=1`.
- **`test_sync_repo.sh`** — covers local-ahead push, divergence rebase, REBASE-CONFLICT (incl. snapshot-first guarantee — snapshot lands even when bookmark sync bails), timeout guard with fake-ssh stub, snapshot-only and bookmark-only flows, non-default-workspace skipping local-bookmark snapshots, malformed `sync.remote-bookmark`, and non-jj-repo skip. Stubs `hostname` / `hostnamectl` for deterministic ref names; stubs claude/kiro-cli/ollama so commit-msg falls through fast.

### `sync_repo` design

**Two independent flows driven by jj config** — both keys optional, set per-repo via `jj config set --repo`:

- `sync.snapshot-url = "git@server:repo.git"` — snapshot path: per-host workspace + bookmark snapshots pushed via raw `git push <URL>` (delete+push since gitfarm rejects `--force`). URL-direct push doesn't update `refs/remotes/<remote>/*`, so jj never imports these as remote bookmarks.
- `sync.remote-bookmark = "BOOKMARK@REMOTE"` (e.g. `main@backup`) — bookmark-sync path: narrow `jj git fetch --remote REMOTE --branch BOOKMARK` then ancestry reconcile against `BOOKMARK@REMOTE`. The remote name is parsed from the value, no `jj git remote list` discovery.

**Snapshot-first ordering**: `step_push_workspace_snapshot` + `step_push_local_bookmark_snapshots` always run BEFORE `step_sync_remote_bookmark` and `step_rebase_local_chain`. Snapshot push is purely additive on the server, so `@-` lands before any rebase / merge probe / bookmark advance can disturb it. On `REBASE-CONFLICT`, `handle_diverged` sets `SYNC_CONFLICT=1` and `step_rebase_local_chain` skips its own rebase — otherwise the working copy would silently re-acquire conflict markers and `@-` would diverge from the snapshot.

**Bookmark-sync reconcile** (`step_sync_remote_bookmark`): explicit four-way ancestry between `@-` and `BOOKMARK@REMOTE`. Equal → `SKIP`. Local-ancestor → `FAST-FORWARD`, no push (`step_rebase_local_chain` moves mutable commits onto the new tip). Remote-ancestor → set transient local `BOOKMARK` at `@-`, `jj bookmark track BOOKMARK@REMOTE` (jj 0.40+ requires it before push), `jj git push --bookmark BOOKMARK`. Diverged → 3-way merge probe via `jj new --no-edit @- BOOKMARK@REMOTE`; conflicted probe abandons + logs `REBASE-CONFLICT` + skips push; clean probe abandons, then `jj rebase -s 'roots(::@- ~ ::REMOTE)' -d REMOTE` + transient bookmark + track + push. New-remote (no `BOOKMARK@REMOTE` yet) uses `jj git push --bookmark BOOKMARK --allow-new` then tracks. Fetch failure (`TIMEOUT`/`NETWORK-ERR`) skips the whole step with `SKIP-PUSH <bm>: fetch failed`.

**Snapshot push** (`step_push_workspace_snapshot` + `step_push_local_bookmark_snapshots`): for the active workspace's `PUSH_REV` and every non-host-prefixed local bookmark, `push_force_replace TAG URL COMMIT BRANCH` does `git push <URL> --delete <branch>` then `git push <URL> <commit>:<branch>`. Delete+push emulates force-push for servers that reject `--force`. Push only proceeds when the delete classified as `OK` or `BENIGN-DEL`. Branch name is `refs/heads/<MACHINE_NAME>/<workspace-or-bookmark>`. **Local-bookmark snapshots run only in the default workspace** — local bookmarks are repo-scoped, so non-default workspaces would push redundant copies. `resolve_workspace_name` (called once in main) provides `WORKSPACE_NAME`; each workspace's own snapshot still runs regardless of name.

**Hang prevention**: every git/jj network call wrapped in `timeout_cmd` (`SYNC_REPO_CMD_TIMEOUT=60s` default). `GIT_SSH_COMMAND` sets `ConnectTimeout=10`, `ServerAliveInterval=15`, `ServerAliveCountMax=3`, `BatchMode=yes` so stalled SSH dies fast and never prompts.

**Event logging** via `script/logger/log.sh`: `FETCH-OK`, `PUSH-OK`, `FAST-FORWARD`, `SKIP`, `SKIP-PUSH` (fetch-failed), `NO-SYNC-CONFIG`, `START` at INFO; `NETWORK-ERR`, `TIMEOUT`, `BENIGN-DEL`, `SKIP-PUSH` (delete-failed) at WARN/DEBUG (transient, not notified); `OTHER-ERR`, `REBASE-CONFLICT`, `BAD-CONFIG`, `REFUSED-SNAPSHOT` (working-copy file >`snapshot.max-new-file-size`, silently bypasses sync — message lists the offending paths) at ERROR (notified); `REBASE-PROBE-FAIL`, `REBASE-FAIL` at CRITICAL (notified). `classify_cmd` routes failures to `NETWORK-ERR` / `OTHER-ERR` / `BENIGN-DEL` based on stderr patterns.

**Non-jj repos**: silently skipped (`jj root || exit 0`). No log file, no notification. Various build-tool checkouts and toolbox dirs sit under `$HOME` and would otherwise be picked up by `sync_all`'s plocate iteration; jj is the explicit opt-in (`jj git init --colocate`).

**Old leftovers**: pre-split repos that still carry `<host>/*` remote bookmarks from the old run can be cleaned up with `jj bookmark forget --include-remotes "<host>/*"` (the new flow no longer creates them — direct `git push` skips `refs/remotes/*`).

## plocate updatedb

`script/updatedb` — runs every 10min via `updatedb.timer` (`home.nix` `OnCalendar="*:0/10"`). Uses `log.sh`. Classifies failures (disk full / permission / read-only FS / generic) with actionable messages. Slow-run threshold `UPDATEDB_THRESHOLD=30s` (override via env) logs WARN + desktop popup. Test harness: `script/test_updatedb.sh` (20 assertions; fake `updatedb` binary via PATH).

## Flake update watchdog

`script/flake-update` — weekly `systemd.user.timers.flake-update` (Sun 03:00 + 2h `RandomizedDelaySec` + `Persistent=true` so suspended laptops catch up). Runs `nix flake update` then `home-manager build --impure --flake .` (NEVER `switch`).

**Why**: nixos-unstable + home-manager unstable produce occasional breaking changes; running `home-manager switch` blind on update day means breakage shows up at the wrong moment. The watchdog finds it on a Sunday morning instead.

Failures: ERROR (paged via Telegram) for build failures and non-network `nix flake update` errors; WARN (silent) for transient network errors. Build-failure log captures the **last 40 lines + first 10 lines** of stderr — nix's verbose error trace puts the actionable line near the bottom (e.g. `error: Refusing to evaluate package 'X' because it has an unfree license`), so the older "first 20 lines" cap missed it. The Telegram body summary is extracted via `tac | grep -m1 '^error: '` so the actionable reason lands in the preview before the user clicks the log link.

**Home-manager news handling**: after a successful build, runs `home-manager news --flake . --impure` (the `--impure` is required because `bare-aliases.nix` uses impure builtins to read `/etc/hostname`) and pipes any unread items to `claude --print --tools "" --no-session-persistence` with a one-line classifier prompt (`BREAKING: <summary>` vs `OK`). 90s timeout (the previous 30s consistently hit `timeout(1)` exit 124 when invoked from a non-tty subshell). Only `BREAKING` escalates to ERROR notify; `OK` and unrecognised classifier output stay silent — pure-news flooding would defeat the whole "low-noise alert" goal. claude unavailable / `CLAUDECODE` set / Bedrock auth failure (`bedrock:InvokeModelWithResponseStream not authorized`) → silent INFO (news still goes to the persisted log file for grep).

Env: `FLAKE_UPDATE_DRY_RUN=1` skips the actual update (still runs build + news), `FLAKE_UPDATE_FLAKE_DIR` overrides the flake path.

**First production-validation run (2026-05-23) caught a real upstream breaking change**: nixpkgs reclassified 8 nvim plugins (`nvim-dap-vscode-js`, `typescript-vim`, `vim-argumentative`, `vim-dirdiff`, `vim-fubitive`, `vim-jinja`, `vim-table-mode`, `vimproc.vim`, `YankRing.vim`) as unfree, breaking the next `home-manager switch`. Watchdog fired ERROR before any switch happened; fix = added the names to `home.nix`'s `allowUnfreePredicate` allowlist.

Test harness: `script/test_flake-update.sh` (34 assertions; stubbed `nix`, `home-manager`, `claude` via PATH; the harness `env -u CLAUDECODE`s the runner so it works whether or not Claude Code is the calling shell).

## Battery notify

`script/battery-notify` — systemd timer every 1min. While discharging, fires a staged set of OSDs (each stage subsumes the earlier ones — once stage N has fired, lower-numbered stages never re-fire within the same discharge cycle):

- `warn:30` — yellow `battery-osd`, once per discharge.
- `warn:20` — yellow `battery-osd` + `notify-send`, once per discharge.
- `warn:15` — yellow `battery-osd`, once per discharge.
- `crit:<n>` — red `battery-osd`, re-fires on every percent change while still ≤10% so the user keeps noticing the trend.

State file holds the last-fired stage tag (`warn:30` / `warn:20` / `warn:15` / `crit:<capacity>`); rank ordering means a jump from 50% straight to 12% skips warn:30/20 and fires warn:15 directly. Charging/full/unknown clears the state so the next discharge cycle restarts at warn:30. `battery-osd` accepts `--style {warn|critical}` (yellow / red).

Env-overridable for tests: `BATTERY_NOTIFY_BAT_DIR`, `BATTERY_NOTIFY_POWER_SUPPLY_DIR`, `BATTERY_NOTIFY_STATE_FILE`, `BATTERY_OSD_BIN`. Test harness: `script/test_battery-notify.sh` (66 assertions; fake sysfs + stubbed notify-send and battery-osd; sets `LOG_KEEP_THRESHOLD=DEBUG` so INFO/WARN log lines persist for assertions).

## Network printer CLI

`script/bin/print-hp` — sends a file to an HP network printer via raw JetDirect (TCP port 9100), bypassing CUPS entirely. Exists because some CUPS print servers (seen with Synology bundled CUPS 1.5 + `rastertogutenprint`) silently drop PDF jobs.

Discovery order: `--ip`/`$PRINT_HP_IP` → cached IP verified via 8s `/dev/tcp` probe (regardless of age — printers keep DHCP leases for days; 8s tolerates sleeping printers waking up on the TCP handshake) → `nmap` scan of the subnet. Cache file at `${XDG_CACHE_HOME:-~/.cache}/print-hp/hp-ip`; touched on successful reuse.

Accepts `.pdf` (converted via `pdftops`), `.ps`/`.eps` (sent as-is), and text (via `enscript` if installed, raw otherwise). Defaults: A4, duplex long-edge, subnet `192.168.1.0/24` (override with `$PRINT_HP_SUBNET` — e.g. set to `192.168.4.0/22` in `private-dotfiles/env.zsh` for Hojin's home LAN).

**Duplex enforcement via PJL**: PostScript-bearing payloads (PDF/PS/EPS, plus enscript-rendered text) are wrapped with a PJL header (`@PJL SET DUPLEX=ON` + `@PJL SET BINDING=LONGEDGE`, or `DUPLEX=OFF` for `--simplex`) before send. Raw text payloads (no enscript) skip the wrapping. Without PJL, duplex flags inside the PS aren't honoured by every HP firmware over raw JetDirect — PJL overrides the device default for the job and resets at `@PJL RESET`. Header/trailer use UEL (`<ESC>%-12345X`) per HP's PJL spec.

Flags: `-d`/`--discover` (print IP and exit), `-i`/`--ip` (skip discovery), `-s`/`--simplex`, `-n`/`--no-cache` (force rescan), `--pages RANGE` (PDF-only; `N`, `N-M`, `N-`, or `-M` → passed to `pdftops -f/-l`), `--dry-run` (skip sending; leaves the converted payload at a printed path).

Requires `nmap` (installed via `home.nix`, with `nix run nixpkgs#nmap` fallback), `ncat`/`nc`, `pdftops` (poppler).
