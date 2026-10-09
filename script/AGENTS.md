# script — Context for AI Agent

`~/.dotfiles/script/`. Periodic-job scripts (sync, updatedb, flake-update, battery-notify) plus a few one-off helpers. Logging and notifications live in `script/logger/` — see `script/logger/AGENTS.md`.

Most jobs are scheduled via `dotfiles.schedule` (see `home-manager.configsymlink/AGENTS.md`); the backend is systemd-user where available and cron elsewhere.

## Sync scripts

- **`sync_all`** — run by the `sync-repos` schedule. Iterates `.jj`/`.git` markers under `$HOME` from plocate, filters noise paths (`.cache`, `.cargo`, `.local/state`, `.nix-profile`, `node_modules`), and **deduplicates by `jj --ignore-working-copy root` / `git top-level`** so discovery cannot snapshot an actively changing working copy and monorepos with many submodule markers trigger `sync_repo` once per underlying repo root (not once per marker). Logs via `script/logger/log.sh` with tag `sync_all`: INFO lines for START + discovery count; ERROR summary + non-zero exit when any per-repo sync fails. Workspaces of the same repo are still iterated separately (each has its own `jj root`), which is intentional — each workspace has its own `@` to sync; sync_repo's flock then serializes them on the shared `jj git root` so they don't race the shared op log. Test harness: `script/test_sync_all.sh` (28 assertions; fake plocate / sync_repo / jj / git).
- **`sync_repo`** — per-repo. `sync.enabled = false` is a silent repository-level kill switch, checked with `--ignore-working-copy` before any command can snapshot or commit the working copy. Two locks are keyed on `jj git root` (the shared `.git` path), NOT `jj root`: `/tmp/sync_repo_job_<git-root>.lock` is held for the whole run and prevents duplicate sync jobs, while `/tmp/sync_repo_<git-root>.lock` is shared with interactive `jj` and held only for local jj/ref work. Snapshot prep: single `jj log -r @` resolves `PUSH_REV` atomically; runs `jj new` on non-empty OR empty-merge `@`, then `commit-msg` for description. `LOG_CONTEXT` is path-relative-to-home with `/`→`-`, so workspace-name collisions don't pile into the same log file. **Both `sync_all` and `sync_repo` `unset LOG_ROOT LOG_REL_BASE LOG_NOTIFY_DEDUP_DIR` before sourcing log.sh** to land logs in `~/.local/state/logs/` instead of `~/hjdocs/logs/` (avoids self-referential race with the repo it's syncing). Test harnesses opt out via `SYNC_LOG_ROOT_KEEP=1`. **Repository hooks**: the optional jj config keys `sync.pre-snapshot` (before the first working-copy snapshot) and `sync.post-update` (at the end, after fetch/rebase) each hold one shell command. `sync_repo` runs it with `sh -c` in the workspace root, with the local-state lock held (`JJ_SERIALIZED_LOCK_HELD=1`, lock fds closed in the child) and the usual command timeout. A failure logs `HOOK-FAIL sync.<name>` at ERROR and the sync continues. Repo-specific logic belongs in the hook command, not in `sync_repo` (example: `private-dotfiles` `claude.symlink/settings-split`). A file that one machine stops tracking while another machine has an unpushed edit to it causes a modify/delete `REBASE-CONFLICT` that no `.gitattributes` driver resolves; the hook must handle such migrations. **Home-directory templates**: `script/bin/home-template capture` runs after `sync.pre-snapshot` and `render` before `sync.post-update` (see "Home-directory templates" below).
- **`jj-fix-churn [-d DAYS] [-m MIN_OPS] [REPO...]`** — lists files that `jj fix` rewrote in at least MIN_OPS fix operations of the last DAYS days (default 7 days, 3 operations), from `jj op show --summary` of each fix operation. Without REPO it checks every jj repo in the plocate database. Read-only (`--ignore-working-copy`). The former `generalize-paths` fix tool is gone (see "Home-directory templates"), so the tool now mainly finds files that it rewrote in the past. Such a file may still contain a literal `$HOME` that its program cannot expand; restore the absolute path, and the next `home-template capture` converts the file.
- **`agent-fallback`** — shared unattended agent runner. The caller passes
  the repository working directory, prompt file, output directory, task name,
  final failure message, stable log context, skipped agents, and prior
  validation errors. The runner resolves current Toolbox registrations, then
  tries Codex → Kiro → Claude until one process succeeds. It writes each
  agent's result, console output, and standard error into the supplied output directory
  and prints only the selected agent name on standard output. Exit 75 means every
  remaining agent was unavailable because of authentication, rate limiting,
  missing executables, or a temporary service failure. Those cases log at
  WARN and never notify. Exhausted real failures log one aggregated ERROR via
  `script/logger/log.sh`; task-specific text is supplied by the caller.
  Successful output is scanned for a temporary-failure signature only when it
  is at most 4096 bytes, so a substantial successful report can discuss rate
  limiting without being rejected. Strong authentication failures in standard
  error, including expired Midway sessions and unavailable AWS credentials,
  are always treated as deferred even when the process exits successfully and
  emits a large banner or prompt transcript. Authentication diagnostics passed
  back as prior caller validation errors are filtered the same way. Like
  `sync_repo`, the runner unsets
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
  The shell and Neovim fzf jj pickers use it with operation-pinned reads so initial producers, reloads, and previews cannot deadlock each other on the external lock.
  Test: `script/test_jj-serialized.sh`.
- **`test_sync_repo.sh`** — covers local-ahead push, divergence rebase, REBASE-CONFLICT (incl. snapshot-first guarantee — snapshot lands even when bookmark sync bails), timeout guard with fake-ssh stub, snapshot-only and bookmark-only flows, non-default-workspace skipping local-bookmark snapshots, unchanged snapshot call counts (one discovery, zero pushes), direct creation of missing snapshot refs, malformed `sync.remote-bookmark`, non-jj-repo skip, corrupted-store REPO-LOAD-FAIL (deleted git object → ERROR + exit 1, no push attempts), the gitfarm-style "no-description rejection" regression, and a blocked-network concurrency case proving the local lock is released while the whole-run job lock still rejects a second sync. Stubs `hostname` / `hostnamectl` for deterministic ref names; stubs claude/kiro-cli/ollama so commit-msg falls through to the file-list fallback.

### `sync_repo` design

**Independent flows driven by jj config** — all keys optional, set per-repo via `jj config set --repo`:

- `sync.snapshot-url = "git@server:repo.git"` — snapshot path: per-host workspace + bookmark snapshots pushed via raw `git push <URL>` (delete+push since gitfarm rejects `--force`). URL-direct push doesn't update `refs/remotes/<remote>/*`, so jj never imports these as remote bookmarks.
- `sync.remote-bookmark = "BOOKMARK@REMOTE"` (e.g. `main@backup`) — bookmark-sync path: raw Git discovers and fetches only `refs/heads/BOOKMARK` by URL without writing refs/FETCH_HEAD; a short locked phase updates `refs/remotes/REMOTE/BOOKMARK`, runs `jj git import`, and reconciles ancestry. Push uses the prepared immutable commit ID through raw Git, followed by another short locked tracking-ref import.

- `sync.bookmarks = "BOOKMARK@REMOTE ..."` (e.g. `"main@backup build@backup"`, processed in that order) — listed-bookmark path: each bookmark is synced as it is and never moved to `@-`. Transport matches the bookmark-sync path (raw Git fetch by URL unlocked; tracking-ref update + `jj git import` + `jj bookmark track` locked). Reconcile per bookmark: missing locally → created from the remote; remote ahead → `FAST-FORWARD`; local ahead → push; diverged → a merge probe (`jj new --no-edit L R`) and, when clean, `jj rebase -s roots(R..L) -d R`, which also moves descendants such as `@`. A probe conflict logs `REBASE-CONFLICT` and leaves the bookmark at the local commit. A rebase that still leaves conflicted commits is rewound with `jj op restore`. A bookmark that jj import left conflicted keeps its non-remote side. Before a push, commits without a description in `R..L` (for a new bookmark: `::L ~ ::remote_bookmarks()`) skip that bookmark with `SKIP-PUSH … commits without description` at ERROR; nothing is rewritten. Listed reconciliation runs before `prepare_bookmark_sync`, because a rebase can rewrite `@-`. An entry equal to `sync.remote-bookmark`, a duplicate, or one without `@` is `BAD-CONFIG`. The `@` working-copy commit is still made, as with the other keys.

**With no key set** the repo still gets the local half of the work: health gate, `jj workspace update-stale`, refused-snapshot check, `snapshot_at_to_push_rev` (`jj new` + `commit-msg` describe) and `step_describe_local_chain`, then `NO-SYNC-CONFIG` at INFO and exit 0. Committing WIP under a real description is useful without any remote, so the config gate sits _after_ those steps rather than before them. Everything past the gate serves a push and stays gated. The `home-template capture` step runs before the gate (it must precede the first snapshot) but checks the same two keys, because it untracks files and edits `.gitignore` — not something to inflict on repos that aren't being pushed. Since `sync_all` feeds every jj repo under `$HOME` to `sync_repo`, this means the timer now finalizes and describes work in _all_ of them, one `bin/commit-msg` (LLM) call per dirty repo per run.

**Snapshot-first ordering**: `prepare_snapshot_refs` captures the workspace and local-bookmark commit IDs under the local lock; `push_prepared_snapshots` pushes them after releasing it and always before fetched refs are imported or reconciliation starts. Thus the captured `@-` lands before any rebase / merge probe / bookmark advance can disturb it. On `REBASE-CONFLICT`, `handle_diverged` sets `SYNC_CONFLICT=1` and `step_rebase_local_chain` skips its own rebase — otherwise the working copy would silently re-acquire conflict markers and `@-` would diverge from the snapshot.

**Description gating**: `step_describe_local_chain` runs after the snapshot and before any push. It walks the local-only mutable chain (`<bookmark>@<remote>..@-`, falling back to `@-` when no remote bookmark is configured) and runs `bin/commit-msg` against any commit with `!description && !empty`. Servers like gitfarm reject pushes that contain undescribed commits ("Won't push commit X since it has no description"), and `snapshot_at_to_push_rev` only describes the working copy — older mid-chain commits left undescribed by interactive `jj split` / agent edits / etc. would otherwise reach the push and fail. Logs `DESCRIBE-OK` (info) per fixed commit; `DESCRIBE-FAIL` (warn) if commit-msg or `jj describe` fails (push will then fail loudly with the server's message rather than silently skipping the commit).

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

Before preflight, the script appends the standard user, Nix daemon, and NixOS profile directories to the inherited `PATH`. This allows a cron host with a stale generated `PATH` to find `nix` and `home-manager`. Inherited entries stay first for explicit overrides and tests.

**Why**: nixos-unstable + home-manager unstable produce occasional breaking changes; running `home-manager switch` blind on update day means breakage shows up at the wrong moment. The watchdog finds it on a Sunday morning instead.

Failures: ERROR (paged via Telegram) for build failures and non-network `nix flake update` errors; WARN (silent) for transient network errors. Build-failure log captures the **last 40 lines + first 10 lines** of stderr — nix's verbose error trace puts the actionable line near the bottom (e.g. `error: Refusing to evaluate package 'X' because it has an unfree license`), so the older "first 20 lines" cap missed it. The Telegram body summary is extracted via `tac | grep -m1 '^error: '` so the actionable reason lands in the preview before the user clicks the log link.

**Home-manager news handling**: after a successful build, runs `home-manager news --flake . --impure` (the `--impure` is required because `bare-aliases.nix` uses impure builtins to read `/etc/hostname`) and pipes any unread items to `claude --print --tools "" --no-session-persistence` with a one-line classifier prompt (`BREAKING: <summary>` vs `OK`). 90s timeout (the previous 30s consistently hit `timeout(1)` exit 124 when invoked from a non-tty subshell). Only `BREAKING` escalates to ERROR notify; `OK` and unrecognised classifier output stay silent — pure-news flooding would defeat the whole "low-noise alert" goal. claude unavailable / `CLAUDECODE` set / Bedrock auth failure (`bedrock:InvokeModelWithResponseStream not authorized`) → silent INFO (news still goes to the persisted log file for grep).

Env: `FLAKE_UPDATE_DRY_RUN=1` skips the actual update (still runs build + news), `FLAKE_UPDATE_FLAKE_DIR` overrides the flake path.

The watchdog has caught real upstream breakage in production (e.g. nixpkgs reclassifying nvim plugins as unfree); when that happens, fix = add to `home.nix`'s `allowUnfreePredicate` allowlist.

Test harness: `script/test_flake-update.sh` (36 assertions; stubbed `nix`, `home-manager`, `claude` via `PATH`). The harness removes `CLAUDECODE` so it works from Claude Code, and verifies recovery from a stripped scheduler `PATH` through a fake Nix profile.

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

## Home-directory templates

`script/bin/home-template` keeps this machine's absolute home directory out of pushed commits. It replaced the `generalize-paths` jj fix tool. That tool rewrote committed content to a literal `$HOME`, which programs that need an absolute path cannot expand, and programs then wrote the absolute path back on every run.

A text file `FILE` that contains the home directory is converted once:

- `FILE.home-template` (tracked) is a copy of `FILE` with the home directory replaced by `@HOME@`. `@HOME@` is the token the GTK bookmarks template already uses. Literal `$HOME` / `${HOME}` in scripts stays untouched, because only template files are rendered back.
- `FILE` becomes ignored (an anchored `/FILE` entry in the `.gitignore` of its directory) and untracked. The live file keeps the absolute path.

The home directory matches only when the next character is not a name character, so `/home/ab` does not change `/home/abc`. It also must not end a longer absolute path: with a home of `/home/hojin`, `/local/home/hojin` (another machine's home) stays unchanged, while `-L/home/hojin/lib` and `a:/home/hojin` are converted. Before 2026-10-09 the second check was missing, and templates got `/local@HOME@`. `generalize_live` accepts the old rule when only that rule agrees with a saved state, so a corrected template reaches machines that rendered the broken one; remove it when every machine has synced. Binary files, symlinks, and files that already contain `@HOME@` are not converted; a file with `@HOME@` would not round-trip, so it is reported.

`sync.home-template-exclude` (jj config, per repo) lists shell patterns separated by spaces; `*` also matches `/`. Matching paths are never converted and keep the absolute path in commits; an existing template of a matching path is no longer updated. Use it for files that programs append to (transcripts, logs): their templates would change at every sync. `private-dotfiles/jj/user.toml` sets it for Claude/Codex transcripts and logs and for `~/hjdocs` `logs/*`.

`sync_repo` runs two steps, only for repositories with `sync.remote-bookmark` or `sync.snapshot-url`:

- `capture` runs after the `sync.pre-snapshot` hook and before the first snapshot. It copies local changes of each `FILE` into its template, then converts new files. It searches tracked files and untracked files that jj would track at the next snapshot, so a new file never enters a commit with the absolute path.
- `render` runs after `step_rebase_local_chain` and before the `sync.post-update` hook. It writes fetched template changes into `FILE`, in place, so the inode and open handles survive. It creates `FILE` when it is missing (for example, on a new clone).

A per-file state copy under `${XDG_STATE_HOME:-~/.local/state}/home-template/` records the template content that `FILE` and the template last agreed on. Each step compares both sides with it:

- Only `FILE` changed: `capture` copies it to the template. `render` waits.
- Only the template changed (a fetch, or a manual `jj rebase` between syncs): `render` writes it to `FILE`. `capture` does not overwrite it with the stale file.
- Both changed: `git merge-file` merges them. On a conflict, `FILE` wins at the next `capture`. The jj history keeps the template version.

**Tracking a file again**: when neither `FILE` nor its template contains `@HOME@` any more (the home path was removed from the file), `render` tracks `FILE` again (`jj file track --include-ignored`), deletes the template and the `.gitignore` entry (an emptied `.gitignore` is deleted), and drops the state. It runs in `render`, after the merge, so every remote template change is already in `FILE`; the change is pushed by the next run. Every machine makes the identical change, so concurrent re-tracks merge cleanly. A machine that receives the re-track first follows in `capture` (`follow_retrack`): it deletes the template but keeps the `.gitignore` entry, so the remote deletion of the entry merges cleanly. jj 0.45 does not write a tracked file over an ignored local copy ("updates were skipped because there were conflicting changes in the working copy"); `render` (`receive_retracks`) then replaces the local copy with the received `FILE` from `parents(@)` when the copy has no local edits since the saved state, and 3-way merges local edits otherwise. It finds such files through `STATE.path`, a sidecar of each state file that records the absolute path. Both migrations compare with `fork_point(@ | remote)`, so they follow only changes that the remote made and never undo this machine's unpushed conversion or re-track. Excluded paths are never re-tracked: their content differs per machine, so concurrent re-tracks would conflict. Their existing templates stay frozen (neither step updates them). Remaining race: a template edit on one machine between another machine's re-track and its next push gives a modify/delete `REBASE-CONFLICT`.

**Migration across machines**: when the remote bookmark has `FILE.home-template` but `FILE` is still tracked locally, `capture` follows the remote first. It squashes unpushed changes of `FILE` into `@`, adds the same `.gitignore` entry, untracks `FILE`, and stores `FILE` from the fork point as the merge base. The rebase then sees two identical deletions instead of a modify/delete conflict. `render` 3-way merges the local edits with the remote template.

Stdout lines go to the sync log at INFO (`HOME-TEMPLATE capture: converted …`); a nonzero exit logs `HOME-TEMPLATE-FAIL` at ERROR. Both steps can also run by hand in any workspace directory: `home-template capture|render`.

Binary detection uses `file --mime-encoding`, which reports some length-prefixed formats as text: jj's `~/.config/jj/workspaces/*/metadata.binpb` (protobuf) was converted once, and a render with a home of another length would corrupt it. Those files are per-machine jj state, so `jj.configsymlink/.gitignore` now ignores `workspaces/` like `repos/`. Exclude any similar format with `sync.home-template-exclude`. GTK bookmarks keep their own renderer: `script/bootstrap` calls `script/bin/generate-gtk-bookmarks`, which renders `gtk-3.0.configsymlink/bookmarks.template` into the ignored `bookmarks` file.

Why not git's `clean`/`smudge` filters: jj treats files as raw bytes and ignores `.gitattributes filter=` directives.

Tests: `bash script/test_home-template.sh` (conversion, render, both-side merges, conflicts, migration, re-tracking, a received re-track with a local edit) and Scenario 18 of `script/test_sync_repo.sh` (end to end through a bare remote, including a re-track received by a second clone). Scenario 19 covers `sync.bookmarks` (creation from the remote, fast-forward, push, rebase of a diverged bookmark, conflict, undescribed commit).

## Network printer CLI

`script/bin/print-hp` — sends a file to an HP network printer via raw JetDirect (TCP port 9100), bypassing CUPS entirely. Exists because some CUPS print servers (seen with Synology bundled CUPS 1.5 + `rastertogutenprint`) silently drop PDF jobs.

Discovery order: `--ip`/`$PRINT_HP_IP` → cached IP verified via 8s `/dev/tcp` probe (regardless of age — printers keep DHCP leases for days; 8s tolerates sleeping printers waking up on the TCP handshake) → `nmap` scan of the subnet. Cache file at `${XDG_CACHE_HOME:-~/.cache}/print-hp/hp-ip`; touched on successful reuse.

Accepts `.pdf` (converted via `pdftops`), `.ps`/`.eps` (sent as-is), and text (via `enscript` if installed, raw otherwise). Defaults: A4, duplex long-edge, subnet `192.168.1.0/24` (override with `$PRINT_HP_SUBNET` — e.g. set to `192.168.4.0/22` in `private-dotfiles/env.zsh` for Hojin's home LAN).

**Duplex enforcement via PJL**: PostScript-bearing payloads (PDF/PS/EPS, plus enscript-rendered text) are wrapped with a PJL header (`@PJL SET DUPLEX=ON` + `@PJL SET BINDING=LONGEDGE`, or `DUPLEX=OFF` for `--simplex`) before send. Raw text payloads (no enscript) skip the wrapping. Without PJL, duplex flags inside the PS aren't honoured by every HP firmware over raw JetDirect — PJL overrides the device default for the job and resets at `@PJL RESET`. Header/trailer use UEL (`<ESC>%-12345X`) per HP's PJL spec.

Flags: `-d`/`--discover` (print IP and exit), `-i`/`--ip` (skip discovery), `-s`/`--simplex`, `-n`/`--no-cache` (force rescan), `--pages RANGE` (PDF-only; `N`, `N-M`, `N-`, or `-M` → passed to `pdftops -f/-l`), `--dry-run` (skip sending; leaves the converted payload at a printed path).

Requires `nmap` (installed via `home.nix`, with `nix run nixpkgs#nmap` fallback), `ncat`/`nc`, `pdftops` (poppler).
