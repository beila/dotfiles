# script — Context for AI Agent

`~/.dotfiles/script/`. Periodic-job scripts (sync, updatedb, flake-update, battery-notify) plus a few one-off helpers. Logging and notifications live in `script/logger/` — see `script/logger/AGENTS.md`.

Most jobs are scheduled via `dotfiles.schedule` (see `home-manager.configsymlink/AGENTS.md`); the backend is systemd-user where available and cron elsewhere.

## Sync scripts

- **`sync_all`** — run by the `sync-repos` schedule. Iterates `.jj`/`.git` markers under `$HOME` from plocate, filters noise paths (`.cache`, `.cargo`, `.nix-profile`, `node_modules`), and **deduplicates by `jj --ignore-working-copy root` / `git top-level`** so discovery cannot snapshot an actively changing working copy and monorepos with many submodule markers trigger `sync_repo` once per underlying repo root (not once per marker). Logs via `script/logger/log.sh` with tag `sync_all`: INFO lines for START + discovery count; ERROR summary + non-zero exit when any per-repo sync fails. Workspaces of the same repo are still iterated separately (each has its own `jj root`), which is intentional — each workspace has its own `@` to sync; sync_repo's flock then serializes them on the shared `jj git root` so they don't race the shared op log. Test harness: `script/test_sync_all.sh` (27 assertions; fake plocate / sync_repo / jj / git).
- **`sync_repo`** — per-repo. `sync.enabled = false` is a silent repository-level kill switch, checked with `--ignore-working-copy` before any command can snapshot or commit the working copy. Two locks are keyed on `jj git root` (the shared `.git` path), NOT `jj root`: `/tmp/sync_repo_job_<git-root>.lock` is held for the whole run and prevents duplicate sync jobs, while `/tmp/sync_repo_<git-root>.lock` is shared with interactive `jj` and held only for local jj/ref work. Snapshot prep: single `jj log -r @` resolves `PUSH_REV` atomically; runs `jj new` on non-empty OR empty-merge `@`, then `commit-msg` for description. `LOG_CONTEXT` is path-relative-to-home with `/`→`-`, so workspace-name collisions don't pile into the same log file. **Both `sync_all` and `sync_repo` `unset LOG_ROOT LOG_REL_BASE LOG_NOTIFY_DEDUP_DIR` before sourcing log.sh** to land logs in `~/.local/state/logs/` instead of `~/hjdocs/logs/` (avoids self-referential race with the repo it's syncing). Test harnesses opt out via `SYNC_LOG_ROOT_KEEP=1`.
- **`agent-fallback`** — shared unattended agent runner. The caller passes
  the repository working directory, prompt file, output directory, task name,
  final failure message, stable log context, skipped agents, and prior
  validation errors. The runner resolves current Toolbox registrations, then
  tries Codex → Claude → Kiro until one process succeeds. It writes each
  agent's result, console output, and standard error into the supplied output directory
  and prints only the selected agent name on standard output. Exit 75 means every
  remaining agent was unavailable because of authentication, rate limiting,
  missing executables, or a temporary service failure. Those cases log at
  WARN and never notify. Exhausted real failures log one aggregated ERROR via
  `script/logger/log.sh`; task-specific text is supplied by the caller.
  Successful output is scanned for a temporary-failure signature only when it
  is at most 4096 bytes, so a substantial successful report can discuss rate
  limiting without being rejected. Like `sync_repo`, the runner unsets
  inherited `LOG_ROOT`, `LOG_REL_BASE`, and `LOG_NOTIFY_DEDUP_DIR`; tests can
  retain explicit temporary paths with `AGENT_FALLBACK_LOG_ROOT_KEEP=1`.
  `--report-error` and `--report-deferred` expose the same logger and
  notification path to callers with non-agent failures. The default
  notification deduplication window is ten years because contexts are
  operation-specific (for example, an Instapaper bookmark ID); volatile IDs
  inside messages are still normalized by `log.sh`. Test harness:
  `script/test_agent-fallback.sh`.
- **`jj-serialized`** — Home Manager installs `script/bin/jj-serialized` as `~/.nix-profile/bin/jj`, with the real `pkgs.jujutsu` binary injected through `$JJ_REAL_EXECUTABLE`.
  By default, every jj command inside a repository takes `/tmp/sync_repo_<git-root>.lock`, the local-state lock used during `sync_repo`'s jj and ref phases.
  Network fetch and push hold only the separate job lock, so interactive jj remains available.
  Commands in different repositories remain concurrent.
  `-R` and `--repository` are parsed so commands launched outside a checkout still lock the target.
  `flock --close` keeps the descriptor out of jj, SSH, and telemetry children.
  While `sync_repo` owns the local lock, it exports `JJ_SERIALIZED_LOCK_HELD=1` so nested jj calls bypass the wrapper.
  `JJ_SERIALIZED_READ_ONLY=1` is a second explicit bypass for callers that guarantee an operation-pinned read-only command.
  The fzf jj pickers use it after their one serialized snapshot so initial producers, reloads, and previews cannot deadlock each other on the external lock.
  Test: `script/test_jj-serialized.sh`.
- **`test_sync_repo.sh`** — covers local-ahead push, divergence rebase, REBASE-CONFLICT (incl. snapshot-first guarantee — snapshot lands even when bookmark sync bails), timeout guard with fake-ssh stub, snapshot-only and bookmark-only flows, non-default-workspace skipping local-bookmark snapshots, unchanged snapshot call counts (one discovery, zero pushes), direct creation of missing snapshot refs, malformed `sync.remote-bookmark`, non-jj-repo skip, corrupted-store REPO-LOAD-FAIL (deleted git object → ERROR + exit 1, no push attempts), the gitfarm-style "no-description rejection" regression, and a blocked-network concurrency case proving the local lock is released while the whole-run job lock still rejects a second sync. Stubs `hostname` / `hostnamectl` for deterministic ref names; stubs claude/kiro-cli/ollama so commit-msg falls through to the file-list fallback.

### `sync_repo` design

**Two independent flows driven by jj config** — both keys optional, set per-repo via `jj config set --repo`:

- `sync.snapshot-url = "git@server:repo.git"` — snapshot path: per-host workspace + bookmark snapshots pushed via raw `git push <URL>` (delete+push since gitfarm rejects `--force`). URL-direct push doesn't update `refs/remotes/<remote>/*`, so jj never imports these as remote bookmarks.
- `sync.remote-bookmark = "BOOKMARK@REMOTE"` (e.g. `main@backup`) — bookmark-sync path: raw Git discovers and fetches only `refs/heads/BOOKMARK` by URL without writing refs/FETCH_HEAD; a short locked phase updates `refs/remotes/REMOTE/BOOKMARK`, runs `jj git import`, and reconciles ancestry. Push uses the prepared immutable commit ID through raw Git, followed by another short locked tracking-ref import.

**With neither key set** the repo still gets the local half of the work: health gate, `jj workspace update-stale`, refused-snapshot check, `snapshot_at_to_push_rev` (`jj new` + `commit-msg` describe) and `step_describe_local_chain`, then `NO-SYNC-CONFIG` at INFO and exit 0. Committing WIP under a real description is useful without any remote, so the config gate sits *after* those steps rather than before them. Everything past the gate serves a push and stays gated — `step_run_jj_fix` especially: it rewrites file content (`generalize-paths`) to make commits portable before they leave the machine, which must not be inflicted on repos that aren't being pushed. Since `sync_all` feeds every jj repo under `$HOME` to `sync_repo`, this means the timer now finalizes and describes work in *all* of them, one `bin/commit-msg` (LLM) call per dirty repo per run.

**Snapshot-first ordering**: `prepare_snapshot_refs` captures the workspace and local-bookmark commit IDs under the local lock; `push_prepared_snapshots` pushes them after releasing it and always before fetched refs are imported or reconciliation starts. Thus the captured `@-` lands before any rebase / merge probe / bookmark advance can disturb it. On `REBASE-CONFLICT`, `handle_diverged` sets `SYNC_CONFLICT=1` and `step_rebase_local_chain` skips its own rebase — otherwise the working copy would silently re-acquire conflict markers and `@-` would diverge from the snapshot.

**Description gating**: `step_describe_local_chain` runs after `step_run_jj_fix` and before any push. It walks the local-only mutable chain (`<bookmark>@<remote>..@-`, falling back to `@-` when no remote bookmark is configured) and runs `bin/commit-msg` against any commit with `!description && !empty`. Servers like gitfarm reject pushes that contain undescribed commits ("Won't push commit X since it has no description"), and `snapshot_at_to_push_rev` only describes the working copy — older mid-chain commits left undescribed by interactive `jj split` / agent edits / etc. would otherwise reach the push and fail. Logs `DESCRIBE-OK` (info) per fixed commit; `DESCRIBE-FAIL` (warn) if commit-msg or `jj describe` fails (push will then fail loudly with the server's message rather than silently skipping the commit).

**Bookmark-sync reconcile** (`prepare_bookmark_sync`): explicit four-way ancestry between `@-` and imported `BOOKMARK@REMOTE`. Equal → `SKIP`. Local-ancestor → `FAST-FORWARD`, no push (`step_rebase_local_chain` moves mutable commits onto the new tip). Remote-ancestor → set transient local `BOOKMARK` at `@-`, track the remote bookmark, and queue `@-`'s immutable commit ID for raw Git push. Diverged → the existing 3-way merge probe / `.gitattributes` auto-resolve / linear-rebase flow, then queue the rebased commit ID. New-remote queues `@-` without requiring jj-version-specific `--allow-new`. `push_prepared_bookmark` runs unlocked with a normal non-force push, so remote movement is rejected as non-fast-forward; `finalize_bookmark_push` briefly reacquires the lock to update/import the tracking ref. Fetch failure skips reconciliation and push with `SKIP-PUSH <bm>: fetch failed`.

**Snapshot push** (`prepare_snapshot_refs` + `load_snapshot_remote_refs` + `push_prepared_snapshots`): the locked preparation phase resolves the active workspace's `PUSH_REV` and all eligible local bookmarks to immutable Git commit IDs. After unlocking, one `git ls-remote --heads <URL> refs/heads/<MACHINE_NAME>/*` loads every existing host snapshot before any push. Unchanged refs make no push call, missing refs use one direct push, and changed existing refs use delete+push because gitfarm rejects `--force`. **Local-bookmark snapshots run only in the default workspace**; each workspace's own snapshot still runs regardless of name.

**Hang prevention**: every git/jj network call wrapped in `timeout_cmd` (`SYNC_REPO_CMD_TIMEOUT=60s` default). `GIT_SSH_COMMAND` sets `ConnectTimeout=10`, `ServerAliveInterval=15`, `ServerAliveCountMax=3`, `BatchMode=yes` so stalled SSH dies fast and never prompts.

**Event logging** via `script/logger/log.sh`: `FETCH-OK`, `PUSH-OK`, `FAST-FORWARD`, `SKIP`, `SKIP-PUSH` (fetch-failed), `NO-SYNC-CONFIG`, `START` at INFO; `NETWORK-ERR`, `TIMEOUT`, `BENIGN-DEL`, `TRACKING-REF-RACE`, `SKIP-PUSH` (delete-failed) at WARN/DEBUG (transient, not notified); `OTHER-ERR`, `REBASE-CONFLICT`, `BAD-CONFIG`, `REFUSED-SNAPSHOT` (working-copy file >`snapshot.max-new-file-size`, silently bypasses sync — message lists the offending paths), `REPO-LOAD-FAIL`, `REMOTE-IMPORT-FAIL`, `REMOTE-LIST-FAIL` at ERROR (notified); `REBASE-PROBE-FAIL`, `REBASE-FAIL` at CRITICAL (notified). `classify_cmd` routes failures to `NETWORK-ERR` / `OTHER-ERR` / `BENIGN-DEL` based on stderr patterns. The `NETWORK-ERR` pattern includes gitfarm's transient markers — `Another user is currently pushing` (repo locked by concurrent receive-pack) and `fine to retry your request` (gitfarm's internal-error banner ends with "In most cases, it's fine to retry your request."); permanent gitfarm rejections (no-description, GuardRails) use different wording and stay `OTHER-ERR`. **Stderr capture for failed calls**: `_summarize_stderr` strips `remote: ` prefixes and blank lines, then joins the first 4 informative lines with `|` for the WARN/ERROR summary line. The full stderr is also folded into the structured log file at DEBUG (`STDERR-BEGIN`/`STDERR-END` envelope).

**Non-jj repos**: silently skipped (`jj root || exit 0`). No log file, no notification. Various build-tool checkouts and toolbox dirs sit under `$HOME` and would otherwise be picked up by `sync_all`'s plocate iteration; jj is the explicit opt-in (`jj git init --colocate`).

**Lock-fd inheritance** (`run_without_lock`): the whole-run job lock lives on fd 9 and the local-state lock on fd 8. Bash does not mark either descriptor close-on-exec, so a daemonizing child could otherwise retain a lock forever. `run_without_lock` closes both descriptors (`8>&- 9>&-`) around LLM and network children; the parent retains the job lock and, during local phases, the local lock. The nonblocking job-lock failure names holders via `fuser`, so leaked owners remain diagnosable.

**Repo health gate** (`step_check_repo_health`): `jj root` succeeds even on a corrupted store (missing git object, unreadable index) because it only resolves the workspace path. Before the gate existed, such a repo sailed past the early checks and every index-loading jj call failed with stderr discarded — including `jj git remote list`, whose empty erroring output was misread as "remote not configured" (benign INFO skip). Net effect: INFO-only runs, log deleted by retention, **no Telegram notification and no snapshot backup, indefinitely**. The gate probes the index once before the local commit/describe steps (`jj log -r @ --no-graph --ignore-working-copy -T '""'` — `--ignore-working-copy` keeps it read-only), and on failure logs `REPO-LOAD-FAIL` at ERROR (summary via `_summarize_stderr`, full stderr at DEBUG) and exits 1 so `sync_all` also counts the repo as failed.

**Old leftovers**: pre-split repos that still carry `<host>/*` remote bookmarks from the old run can be cleaned up with `jj bookmark forget --include-remotes "<host>/*"` (the new flow no longer creates them — direct `git push` skips `refs/remotes/*`).

## plocate updatedb

`script/updatedb` — runs every 10min via `updatedb.timer` (`home.nix` `OnCalendar="*:0/10"`). Uses `log.sh`. Classifies failures (disk full / permission / read-only FS / generic) with actionable messages. Slow-run threshold `UPDATEDB_THRESHOLD=30s` (override via env) logs WARN + desktop popup. Test harness: `script/test_updatedb.sh` (20 assertions; fake `updatedb` binary via PATH).

## Flake update watchdog

`script/flake-update` — weekly `systemd.user.timers.flake-update` (Sun 03:00 + 2h `RandomizedDelaySec` + `Persistent=true` so suspended laptops catch up). Runs `nix flake update` then `home-manager build --impure --flake .` (NEVER `switch`).

**Why**: nixos-unstable + home-manager unstable produce occasional breaking changes; running `home-manager switch` blind on update day means breakage shows up at the wrong moment. The watchdog finds it on a Sunday morning instead.

Failures: ERROR (paged via Telegram) for build failures and non-network `nix flake update` errors; WARN (silent) for transient network errors. Build-failure log captures the **last 40 lines + first 10 lines** of stderr — nix's verbose error trace puts the actionable line near the bottom (e.g. `error: Refusing to evaluate package 'X' because it has an unfree license`), so the older "first 20 lines" cap missed it. The Telegram body summary is extracted via `tac | grep -m1 '^error: '` so the actionable reason lands in the preview before the user clicks the log link.

**Home-manager news handling**: after a successful build, runs `home-manager news --flake . --impure` (the `--impure` is required because `bare-aliases.nix` uses impure builtins to read `/etc/hostname`) and pipes any unread items to `claude --print --tools "" --no-session-persistence` with a one-line classifier prompt (`BREAKING: <summary>` vs `OK`). 90s timeout (the previous 30s consistently hit `timeout(1)` exit 124 when invoked from a non-tty subshell). Only `BREAKING` escalates to ERROR notify; `OK` and unrecognised classifier output stay silent — pure-news flooding would defeat the whole "low-noise alert" goal. claude unavailable / `CLAUDECODE` set / Bedrock auth failure (`bedrock:InvokeModelWithResponseStream not authorized`) → silent INFO (news still goes to the persisted log file for grep).

Env: `FLAKE_UPDATE_DRY_RUN=1` skips the actual update (still runs build + news), `FLAKE_UPDATE_FLAKE_DIR` overrides the flake path.

The watchdog has caught real upstream breakage in production (e.g. nixpkgs reclassifying nvim plugins as unfree); when that happens, fix = add to `home.nix`'s `allowUnfreePredicate` allowlist.

Test harness: `script/test_flake-update.sh` (34 assertions; stubbed `nix`, `home-manager`, `claude` via PATH; the harness `env -u CLAUDECODE`s the runner so it works whether or not Claude Code is the calling shell).

## Battery notify

`script/battery-notify` — systemd timer every 1min. While discharging, fires a staged set of OSDs (each stage subsumes the earlier ones — once stage N has fired, lower-numbered stages never re-fire within the same discharge cycle):

- `warn:30` — yellow `battery-osd`, once per discharge.
- `warn:20` — yellow `battery-osd` + `notify-send`, once per discharge.
- `warn:15` — yellow `battery-osd`, once per discharge.
- `crit:<n>` — red `battery-osd`, re-fires on every percent change while still ≤10% so the user keeps noticing the trend.

State file holds the last-fired stage tag (`warn:30` / `warn:20` / `warn:15` / `crit:<capacity>`); rank ordering means a jump from 50% straight to 12% skips warn:30/20 and fires warn:15 directly. Charging/full/unknown clears the state so the next discharge cycle restarts at warn:30. `battery-osd` accepts `--style {warn|critical}` (yellow / red).

Env-overridable for tests: `BATTERY_NOTIFY_BAT_DIR`, `BATTERY_NOTIFY_POWER_SUPPLY_DIR`, `BATTERY_NOTIFY_STATE_FILE`, `BATTERY_OSD_BIN`. Test harness: `script/test_battery-notify.sh` (66 assertions; fake sysfs + stubbed notify-send and battery-osd; sets `LOG_KEEP_THRESHOLD=DEBUG` so INFO/WARN log lines persist for assertions).

## Conflict auto-resolver (.gitattributes-driven)

`script/bin/resolve-by-attrs` — best-effort conflict resolution for colocated jj/git repos. Reads conflicted paths from `jj resolve --list -r REVSET` (defaults to `@`), looks up each path's `merge=<name>` attribute via `git check-attr` (which handles macros, hierarchy, negation, and `core.attributesFile`), then dispatches:

- `theirs` → `jj resolve --tool=:theirs` (jj built-in, side #2 wins)
- `ours` → `jj resolve --tool=:ours` (built-in, side #1 wins)
- `union` → emulated; concatenates left + right into output
- `text` / `binary` / unspecified / unset / set → leave alone
- anything else → look up `[merge.<name>] driver` in gitconfig; if defined, expand git's `%A %B %O %P %L %S %X %Y` placeholders and run it. `%S/%X/%Y` (revision labels) are substituted with `local`/`base`/`other` because jj has no equivalent — drivers like mergiraf that pass these along won't break.

Driver dispatch goes through a transient `[merge-tools.shim]` written to a temp toml and passed via `jj --config-file`. The shim seeds `$output` with `cat $left > $output` (not `cp`) because jj creates the placeholder files read-only and `cp` would preserve that mode, breaking drivers that try to write to `%A`. Driver rc≠0 means "couldn't fully resolve" — jj keeps the original first-class conflict, which is what we want (jj's conflict view is richer than text markers).

Always exits 0 (best-effort helper). `sync_repo` calls it twice in `handle_diverged`: once on the conflicted probe (`-r <probe>`) before the linear rebase, once on `@-` after rebase, since rebase doesn't re-apply driver merges. If anything remains after the post-rebase attempt, `jj op restore` rewinds.

Test harness: `script/test_resolve-by-attrs.sh` (32 assertions across 14 scenarios — theirs/ours/union/text/binary/custom-driver/unknown/mixed-batch/path-with-spaces/non-colocated/conflicted-`.gitattributes`/cwd-default/count-reporting).

## Path generalization (jj fix-driven)

Two pure stream filters, exact inverses of each other, that swap absolute home-directory paths between machine-local and portable forms:

- **`script/bin/generalize-paths`** — `$HOME` literal → `$USER_HOME` placeholder. Wired into jj via `[fix.tools.generalize-paths]` in `jj.configsymlink/config.toml`, applied to all tracked files except `xfce4-panel.xml` (xfconf doesn't expand `$USER_HOME` in its values; that file needs a separate fix listed in the `AGENTS.md` TODO).
- **`script/bin/localize-paths`** — `$USER_HOME` placeholder → `$HOME` literal. Called by `script/bootstrap` once per machine to expand placeholders in tracked files. Skips the same exclusion list as the generalize side.

`USER_HOME` (not `$HOME` or `DOTFILES_HOME`) is the placeholder because tracked shell scripts contain literal `$HOME` that's meant to be expanded by the shell at run time — using `$HOME` as the placeholder would hard-code those at bootstrap. `USER_HOME` is set via `home.sessionVariables` (visible to systemd user units, cron, and login shells) and `zshenv.symlink` (interactive zsh fast path) so apps that interpolate env vars resolve it natively even before bootstrap runs. The localize step is for the holdouts (Amazon `claude` binary writing settings.json with literal absolute paths, xfconf).

`sync_repo` runs `jj fix -s <revset>` after `snapshot_at_to_push_rev` and before any push. The revset is `<bookmark>@<remote>..@-` when a remote bookmark is configured (only generalizes the local-only chain — never rewrites commits already on the remote, which would create divergence on push), otherwise just `@-`. jj fix preserves change IDs and rebases descendants automatically; idempotent runs are no-ops.

Why not git's `clean`/`smudge` filters: jj treats files as raw bytes and ignores `.gitattributes filter=` directives. The asymmetric design (jj fix on commit, bootstrap on clone) is the jj-native equivalent.

## Network printer CLI

`script/bin/print-hp` — sends a file to an HP network printer via raw JetDirect (TCP port 9100), bypassing CUPS entirely. Exists because some CUPS print servers (seen with Synology bundled CUPS 1.5 + `rastertogutenprint`) silently drop PDF jobs.

Discovery order: `--ip`/`$PRINT_HP_IP` → cached IP verified via 8s `/dev/tcp` probe (regardless of age — printers keep DHCP leases for days; 8s tolerates sleeping printers waking up on the TCP handshake) → `nmap` scan of the subnet. Cache file at `${XDG_CACHE_HOME:-~/.cache}/print-hp/hp-ip`; touched on successful reuse.

Accepts `.pdf` (converted via `pdftops`), `.ps`/`.eps` (sent as-is), and text (via `enscript` if installed, raw otherwise). Defaults: A4, duplex long-edge, subnet `192.168.1.0/24` (override with `$PRINT_HP_SUBNET` — e.g. set to `192.168.4.0/22` in `private-dotfiles/env.zsh` for Hojin's home LAN).

**Duplex enforcement via PJL**: PostScript-bearing payloads (PDF/PS/EPS, plus enscript-rendered text) are wrapped with a PJL header (`@PJL SET DUPLEX=ON` + `@PJL SET BINDING=LONGEDGE`, or `DUPLEX=OFF` for `--simplex`) before send. Raw text payloads (no enscript) skip the wrapping. Without PJL, duplex flags inside the PS aren't honoured by every HP firmware over raw JetDirect — PJL overrides the device default for the job and resets at `@PJL RESET`. Header/trailer use UEL (`<ESC>%-12345X`) per HP's PJL spec.

Flags: `-d`/`--discover` (print IP and exit), `-i`/`--ip` (skip discovery), `-s`/`--simplex`, `-n`/`--no-cache` (force rescan), `--pages RANGE` (PDF-only; `N`, `N-M`, `N-`, or `-M` → passed to `pdftops -f/-l`), `--dry-run` (skip sending; leaves the converted payload at a printed path).

Requires `nmap` (installed via `home.nix`, with `nix run nixpkgs#nmap` fallback), `ncat`/`nc`, `pdftops` (poppler).
