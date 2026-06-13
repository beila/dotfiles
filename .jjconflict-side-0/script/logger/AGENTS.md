# script/logger — Context for AI Agent

`~/.dotfiles/script/logger/`. Sourceable shell library for leveled logging plus the notification backends used by `bin/notify-webhook`.

## Leveled logger (`log.sh`)

Sourceable shell library providing `log LEVEL "msg"`. Levels: `DEBUG < INFO < WARN < ERROR < CRITICAL`. Call-site declares the level explicitly (shared across multiple scripts; implicit classification is fragile).

Writes to `$LOG_ROOT/<machine>/<tag>[.<context>].<date>[.<time>].log`; the first run of a day takes the undecorated name, subsequent runs the same day add `.HHMMSS`.

**Retention + temp-file buffering**: during a run, every log line goes to a `/tmp/log.<tag>.XXXXXX` temp file; `$LOG_ROOT` is never touched mid-run. On `log_finalize` (auto-called on EXIT), if the run recorded at least one event at level ≥ `LOG_KEEP_THRESHOLD` (default `ERROR`) the temp file is moved into place at `$LOG_ROOT/...`; otherwise the temp file is deleted. This is critical when `$LOG_ROOT` lives inside a synced jj/git repo (like `~/hjdocs/logs`): the log file never changes the repo's working copy while scripts that sync that same repo are running, so no self-referential race. `LOG_KEEP_THRESHOLD=DEBUG` keeps every run; `LOG_KEEP_THRESHOLD=NEVER` always deletes.

The auto-installed EXIT trap is safe in subshells (trap text is inherited but dormant; our `trap log_finalize EXIT` affects only the current shell). Callers that set their own EXIT trap AFTER sourcing must call `log_finalize` manually.

### Required env

- `LOG_TAG`

### Optional env

- `LOG_CONTEXT` — e.g. repo basename; appears in filename and log lines.
- `LOG_ROOT` — default `~/.local/state/logs`; overridden to `~/hjdocs/logs` via `private-dotfiles/env.zsh` for zsh and `private-dotfiles/logger.nix` for systemd so logs replicate across machines.
- `LOG_REL_BASE` — notification paths shown relative to this; defaults to `$LOG_ROOT`, overridden so notifications say e.g. `logs/<host>/sync_repo.xxx.log`.
- `LOG_NOTIFY_THRESHOLD` (default `ERROR`).
- `LOG_NOTIFY_MODE` — `auto`|`always`|`never`; default `auto` suppresses notifications when stderr is a TTY so manual runs don't ping the phone.
- `LOG_NOTIFY_CMD` — default `bin/notify-webhook`.
- `LOG_NOTIFY_DEDUP_WINDOW` — seconds; default `21600` = 6h; set `0` to disable.
- `LOG_NOTIFY_DEDUP_DIR` — default `$LOG_ROOT/.notify-dedup`. Suppresses re-notification of the same `(TAG, CONTEXT, LEVEL, normalized-message)` signature within the window. Normalization collapses hex IDs ≥8 chars and digit runs ≥2 chars. Dedup state writes are ALSO deferred to `log_finalize` (buffered in `_LOG_PENDING_DEDUP_KEYS`) so `$LOG_NOTIFY_DEDUP_DIR` under `$LOG_ROOT` isn't touched mid-run either. Within a single process the in-memory list always suppresses duplicates; across processes the window/on-disk mtime applies.
- `LOG_MACHINE_NAME` — default from `hostnamectl --pretty`.

### Helpers

- `log_file()` — returns the currently-active path (temp during the run, final after finalize).
- `log_finalize()` — manual cleanup hook.

### CLI wrapper

`bin/dlog` (added to `$PATH` via `path.zsh`; named `dlog` rather than `log` because zsh has a `log` builtin that shadows PATH entries). Each CLI invocation is an independent "run".

### Misc

- Notification body is just the raw `msg` (no timestamp/tag/level prefix — those live in the title and the notifier's UI shows the time).
- Notifications reference the FINAL log path (even before finalize) so the link opens the file after the process exits.
- Interactive stderr is colored by level (dim/plain/yellow/red/bold-red).
- Context sanitization strips slashes, whitespace, and leading `.`/`-` from `LOG_CONTEXT` so filenames stay clean.

Test harness: `script/logger/test_log.sh` (49 assertions; run with `bash script/logger/test_log.sh`).

## Notification backends (`script/logger/backends/`)

Each backend defines `notify_send TITLE PRIORITY URL MESSAGE`. `bin/notify-webhook` selects one (see `bin/AGENTS.md`).

- **`telegram.sh`** — reads `TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID` from `private-dotfiles/telegram.env`; posts to Telegram Bot API with HTML formatting; `low` priority → `disable_notification=true`, `high`/`urgent` add 🟠/🔴 to the title; 5s curl timeout.
- **`none.sh`** — no-op default.
- **`mock.sh`** — test helper; writes TSV lines to `$NOTIFY_MOCK_FILE`.

## Telegram setup

Bot via `@BotFather` (`/newbot`); chat id from `getUpdates` API after sending the bot a message; save `TELEGRAM_BOT_TOKEN` + `TELEGRAM_CHAT_ID` in `~/.dotfiles/private-dotfiles/telegram.env` (chmod 600). Test: `notify-webhook -t test -p high "hello"`.

## Push notification choices (rationale)

- Google Chat webhooks blocked by org admin.
- Slack requires workspace admin.
- KakaoTalk "나에게 보내기" doesn't trigger a push.
- Chose Telegram bot. ntfy.sh remains a viable alternative via a new backend under `script/logger/backends/`.
