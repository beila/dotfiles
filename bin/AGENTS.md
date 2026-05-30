# bin — Context for AI Agent

`~/.dotfiles/bin/`. Added to `$PATH`. Standalone CLIs/wrappers used both interactively and by scripts/timers.

## Output writer / decorator

`logrun` — wraps a command to tee its combined stdout/stderr into a timestamped log file (ANSI stripped) AND pipe the live stream through a decorator (`spacer` → visual break on output pauses, then `watchlog` → "idle for Ns" indicator; both fall back to `cat` if not installed).

Flags: `--name`, `--log-dir`, `--log-path`, `--decorator`/`--no-decorator`, `--fail-suffix` (default `FAILED.txt`; empty disables rename), `-c`/`--command` (run via `bash -c`), `--auto`, `--no-zshrc`.

`--auto` keeps logrun's chrome invisible until a threshold trips:
- No startup `Log:` banner. The decorator is `bin/logrun-decorator`: pure passthrough until a marker file (touched by the awk side-branch on threshold trip) appears, then prints spacer-style breaks at output pauses + an `idle Ns` indicator on stderr. Short `--auto` runs feel like a bare cmd; long ones get the visual aids. The strip-ansi + line-count + alt-screen-detect awk filter sits inside the `tee >(…)` side-branch (NOT on the foreground side, where gawk's block-buffered stdin would delay the first line of `cmd1; sleep N; cmd2` until the sleep ends). awk runs with `-W interactive` on mawk to defeat its 4KB block buffering — without it, threshold detection would be deferred until enough bytes accumulated, e.g. `echo a; echo b; sleep 3; echo done` (LOGRUN_AUTO_LINES=2) wouldn't trip until the post-sleep `done` arrived.
- The foreground stream is plain `cmd | tee /dev/fd/4 | cat`, with the side awk attached to fd 4 — so the user sees output the instant the inner shell flushes it.
- On either `≥LOGRUN_AUTO_SECONDS` (default 10s, wall-clock) or `≥LOGRUN_AUTO_LINES` (default 100) the parent prints `Log: <path>` to stderr exactly once. Threshold marker is a side-channel file (`/tmp/logrun-lines.*`), checked synchronously after the pipeline returns to bypass bash's async signal-trap timing.
- On under-threshold + exit==0: log file is `rm -f`'d so the prompt looks identical to a bare command.
- On exit≠0: failure always reveals — banner is reset and re-emitted with the post-rename `*.FAILED.txt` path so the user has the right path to debug.
- Alt-screen detection: if the awk filter saw `\x1b[?1049h` AND the resolved command name isn't in `LOGRUN_TUI_SKIPLIST`, logrun emits one `logrun: '<cmd>' looks like a TUI (alt-screen detected); add to LOGRUN_TUI_SKIPLIST` line on exit. The escape bytes are stripped from the log either way.
- **PTY layer for color** (all paths in `--auto`): the inner command is wrapped in `script -qefc` so its stdout is a real PTY. Color-aware tools (`eza`, `ls --color=auto`, `git`, `grep --color=auto`) see `isatty(stdout) == true` and emit color + multi-column layout, which logrun ferries through tee to the user's terminal. Falls back to bare exec when `script` (util-linux) is missing — color is lost but everything else works. The PTY's canonical mode adds `\r` before `\n`; the side awk strips it from the on-disk log. Original command name is captured pre-rewrite so log filenames stay readable (e.g. `log-echo-hi-...txt`, not `log-script-qefc-zsh-ic-...`).
- **fd 4 isolation** (`--auto`): the inner command is invoked with `4>&-` so the awk side-channel fd doesn't leak into descendants. Without this, `zsh -ic` helpers (gitstatus daemon, zsh-async workers) inherit fd 4 and — once reparented to systemd — keep the awk pipe writer alive past the user's command, so `wait $awk_pid` idles for several seconds. tee's own fd 4 (`tee /dev/fd/4`) is unaffected because the redirection only applies to `"$@"`.
- **Wallclock timer detached stdio** (`--auto`): the timer subshell starts with `exec </dev/null >/dev/null 2>&1` so its `sleep $auto_seconds` child can't hold the parent's stdio. `kill $auto_timer_pid` only signals the bash subshell, not the inner sleep — without the redirection, the orphaned sleep blocks any downstream pipe reader (e.g. `logrun … | cat`) for the full `$auto_seconds` even after a fast command finished.

`--no-zshrc` (paired with positional argv) makes logrun exec the command directly instead of via `zsh -ic`. The widget passes this for resolved external binaries to avoid ~800ms of zshrc replay per prompt. Aliases/functions wouldn't survive a fresh process anyway, so omitting `zsh -ic` is harmless for that case. In `--auto` mode the command is still wrapped in `script -qefc` (see "PTY layer for color" above).

Log path resolution (first match wins):
1. `--log-path PATH` flag or `log_path` env var → exact file path; skips name/dir derivation. Lets nested recipes inherit a parent's path.
2. `--log-dir DIR` flag → directory only; filename auto-derived as `log-<sanitized-cmd>-<YYYY-MM-DD-HH-MM-SS>.txt`.
3. `$build_dir` env var, if set and is an existing dir.
4. `./build/` if it exists in cwd.
5. `/tmp/` (last-resort fallback).

Filename sanitisation in cases 2-5: spaces, slashes, pipes, semicolons, etc. → `-`; truncated to 200 bytes (ext4/xfs filename limit is 255). On non-zero exit (and non-empty `--fail-suffix`, default `FAILED.txt`), the `.txt` is renamed to `.FAILED.txt`.

Other env: `LOGRUN_DECORATOR` overrides the decorator pipeline; `LOGRUN_AUTO_SECONDS` / `LOGRUN_AUTO_LINES` tune the `--auto` thresholds; `LOGRUN_TUI_SKIPLIST` (defined in `home-manager.configsymlink/home.nix` so it tracks installed TUI packages) suppresses the alt-screen hint for known-OK commands.

The accept-line widget at `zsh/zz-logrun-auto.zsh` is the user-facing entry point — it auto-wraps interactive prompt commands in `logrun --auto`. See `zsh/AGENTS.md` for widget details.

Companion `bin/logrun-move NEW_DIR` relocates the active logrun log to a different directory mid-run (preserves the filename); only works when invoked as a descendant of `logrun` since it talks to the wrapper via `$LOGRUN_PID` / `$LOGRUN_MOVE_FILE`.

Companion `bin/logrun-decorator` (Python stdlib only) is the `--auto` decorator: stays as plain `cat` until `--activate-when-exists <marker>` becomes truthy (or it receives `SIGUSR2`), then emits spacer-style horizontal lines at output pauses + an `idle Ns` stderr indicator. logrun's awk filter touches the marker synchronously when the threshold trips so the decorator activates mid-run (relying on bash's USR2 trap would defer activation until after the pipeline ends).

Test harness: `bin/test_logrun.sh` (naming, ANSI strip, fail-suffix rename, env inheritance, sanitisation, custom decorator, usage errors, `--auto` thresholds + invisibility + reveal + FAILED rename + alt-screen hint, `--no-zshrc` fast path).

## Commit message generator

`commit-msg` — provider chain: claude (`--print --tools "" --no-session-persistence`, skipped when `$CLAUDECODE` is set so a `claude` session never spawns a child claude) → kiro-cli (`--agent no-mcp`, stdin piping) → ollama + qwen2.5-coder:3b fallback (5s health check, started on demand) → capped file-list final fallback (first 3 files + `and N more`, 200-char hard cap; includes deleted files). jj-first / git-fallback. `VERBOSE=1` enables detailed output.

For jj merge commits (`parents.len() > 1`) the prompt is augmented per-parent: compute `unique_revset = (::P ~ ::others) ~ ::(merges() & (::P ~ ::others) ~ P)` (linear run on P's side since the previous merge), take the cumulative diff from `roots(unique_revset)-` (parent of the oldest unique commit = previous merge on that side) to P via `jj diff --from START --to P --git`. If that side diff is ≤ `MAX_MERGE_DIFF_LINES` (default 500, env-overridable) it goes into the prompt; else fall back to a per-commit description list. This gives the LLM code-level context for merges instead of commit-subject boilerplate.

## TTS dispatcher and backends

- **`say`** — routes by content language. Hangul (U+AC00–U+D7A3) → `say-ko`, otherwise → `say-en`. Accepts text as args or stdin. **Preempts** still-playing audio: spawns the backend under `setsid` (PID==PGID), records the PGID at `${SAY_STATE_FILE:-${XDG_RUNTIME_DIR:-/tmp}/say.pgid}`, and `TERM`s the previous PGID on the next call. A `TERM`/`INT`/`HUP` trap forwards to the backend session so external preemption (e.g. by `mcp-tts`) tears down the whole audio pipeline instead of orphaning aplay. Bypass with `SAY_NO_PREEMPT=1`. Test: `bash bin/test_say_preempt.sh`.
- **`say-en`** — piper-tts with `en_GB-alba-medium` voice, auto-downloads model; override voice with `$PIPER_MODEL`.
- **`say-ko`** — edge-tts with `ko-KR-SunHiNeural` voice (requires internet). Default rate `+50%`, override with `$EDGE_TTS_RATE`; override voice with `$EDGE_TTS_VOICE`.

## Claude Code hooks

- **`claude-stop-tts`** — Stop hook. Reads `last_assistant_message` from the Stop hook stdin JSON (authoritative current-turn text; the `transcript_path` file lags Stop firing by several seconds and would replay the *previous* turn). Picks the last paragraph starting with `요약:`, strips that prefix so TTS speaks only the summary content (the user doesn't want "summary" announced every turn), strips markdown, caps to `$CLAUDE_TTS_MAX_CHARS` (default 500), and pipes to `say` (which routes by language). Falls back to the last non-empty paragraph when no `요약` marker exists, and falls back to parsing `transcript_path` if `last_assistant_message` is missing (older Claude Code). Spawns via `setsid` so audio outlives the turn. Debug log at `~/.local/state/claude-stop-tts.log` (override via `$CLAUDE_TTS_LOG`; auto-trimmed to 1000 lines when over 2000). Wired into `~/.claude/settings.json` `hooks.Stop`.
- **`claude-notification-tts`** — Notification hook. Fires when Claude Code asks for permission to use a tool, or when the prompt has been idle. Reads `.message` from the hook's stdin JSON, classifies on `permission/idle/other` substring match, and speaks via `say`. Permission asks → `"도구 실행합니다. <tool> 사용 권한을 요청합니다."` (extracts the tool name from the standard message). Idle → `"입력을 기다리고 있습니다."` Replaces the previous flow where the assistant manually called `say_ko` before each tool call (it forgot, the hook never forgets). Returns `{"continue": true, "suppressOutput": true}` so the transcript stays clean. Debug log at `~/.local/state/claude-notification-tts.log` (override via `$CLAUDE_NOTIFY_TTS_LOG`; auto-trimmed). Wired into `~/.claude/settings.json` `hooks.Notification`.

## VPN supervisor

`vpn-up` + `vpn-watch` — generic openconnect-VPN supervision.

**Why**: openconnect installs DNS + routes pointing at the VPN concentrator. If the underlying network changes (Wi-Fi roam home → café → office) without first tearing down the tunnel, the box ends up with a dead tunnel that still claims to be the default route — every DNS lookup hangs and the network is effectively inaccessible until the user notices.

`vpn-up` bundles two things into one foreground command: (1) `vpn-watch` spawned in the background, (2) the configurable VPN start command (`vpn-up CMD ARGS…` or `$VPN_START_CMD`). When the start command exits, the watcher is reaped via EXIT trap. The VPN client itself is expected to prime sudo (do `sudo /bin/true` then `sudo openconnect …`); the watcher reuses that cache for its later `sudo -n pkill` and keeps it warm via background `sudo -nv` every `$VPN_SUDO_REFRESH` seconds (default 240).

`vpn-watch` monitors `org.freedesktop.NetworkManager` `Connectivity` via `gdbus`; transitions out of `FULL` (4) trigger a `$VPN_DEBOUNCE_SEC` (default 5) wait, and if connectivity is still lost, `sudo -n pkill -TERM <process>` (or `kill -TERM <PID>` when `VPN_PROCESS_PID` is set).

Public repo stays VPN-flavour-agnostic; site-specific glue (the actual VPN binary name) lives in a sibling repo's `vpn.zsh`.

Env: `VPN_PROCESS_NAME` (default `openconnect`), `VPN_PROCESS_PID` (preferred when known — name-based watch is fine for openconnect since it's a singleton in practice), `VPN_DEBOUNCE_SEC`, `VPN_SUDO_REFRESH`, `VPN_STARTUP_WAIT` (default 30).

No NOPASSWD sudoers entry needed: one prompt per VPN session (the client's own), watcher inherits the cache.

## Zellij session cycler

`zellij-cycle` — wraps `zellij attach --create` in a loop. On detach, cycles to the next active session. Supports session names with spaces. Numeric argument (e.g. `1`, `2`) attaches to the Nth existing session instead of a named one (used by xmonad scratchpads — see `xwindow/AGENTS.md`).

## zmx session picker

`zmx-select` — fzf picker over `zmx list`. Enter attaches highlighted, Ctrl-N creates a new session with the typed name (auto-suffixes `-2`, `-3`... if the name is already in use), Ctrl-C exits. Skips the picker and attaches directly to a default session (CLI arg, `$ZMX_DEFAULT_SESSION`, or `main`) when no sessions exist.

## Notify-webhook dispatcher

`notify-webhook` — dispatcher for structured alerts. Flags: `-t TITLE`, `-p {low|normal|high|urgent}`, `-u URL`. Backends live in `~/.dotfiles/script/logger/backends/<name>.sh` and must define `notify_send TITLE PRIORITY URL MESSAGE`. Selection priority: explicit `$NOTIFY_BACKEND` env var → auto-detect (`telegram.env` present → `telegram`) → `none`. Missing credentials or unknown backend = silent no-op (exit 0) so machines without configuration don't fail. See `script/logger/AGENTS.md` for backend details.

## MCP TTS server

`mcp-tts` — MCP server exposing `say` / `say_ko` tools to Kiro/Claude. Kills previous playback via `setsid` + `kill -PGID`. See `kiro.filesymlink/AGENTS.md` for the agent wiring. Test: `bash bin/test_mcp_tts.sh`.

## Other

- `jj-untrack-files` — selectively untrack files in jj while keeping the working copy.

## Known issues

- **kiro-cli** can't receive prompts as command-line arguments (hangs on large input) — `commit-msg` pipes via stdin.
- **kiro-cli `--agent default`** spawns MCP servers that become orphaned on exit — `commit-msg` uses `--agent no-mcp` to avoid this.
