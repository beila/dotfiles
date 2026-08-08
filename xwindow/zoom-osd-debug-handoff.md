# zoom-osd debugging handoff — 2026-08-08

Continuation notes for the next session. Task: make `zoom-osd` fire a
battery-osd-style overlay when Zoom shows a meeting notification. Delete
this file when the work is done and documented in `xwindow/AGENTS.md`.

## Feature summary

`xwindow/bin/zoom-osd.py` — daemon with TWO trigger paths:

1. **freedesktop notifications** (WORKS, verified end-to-end): spawns
   `dbus-monitor "type='method_call',interface='org.freedesktop.Notifications',member='Notify'"`
   and parses stdout. When Notify `app_name` matches `$ZOOM_OSD_APP_REGEX`
   (default `zoom`, case-insensitive), forks a child running
   `display_on_all_monitors()` (osd library, same as battery-osd).
   Verified: `notify-send --app-name=Zoom "..." "..."` → overlay renders
   on all 3 monitors (screenshot confirmed 2026-07-29 and again after
   restart on 2026-08-08).
   - Historical dead end: dbus-python `BecomeMonitor` +
     `add_message_filter` on a private connection received the monitor
     grant but NEVER delivered the Notify method calls (only its own
     NameAcquired/NameLost). That approach was abandoned for parsing
     dbus-monitor text output. Do not retry it.

2. **X window watcher** (NEW, debugging IN PROGRESS): Zoom's Linux client
   does NOT use org.freedesktop.Notifications for meeting invites — user
   confirmed: real meeting started, no Notify call was made, instead Zoom
   drew its own X window `zoom_linux_float_message_reminder`
   (override-ish 358x202 utility window, WM_CLASS "zoom","zoom",
   `_NET_WM_WINDOW_TYPE_UTILITY`). A daemon thread (`_watch_windows`)
   opens its own Display, selects SubstructureNotify on root, and fires
   `_show()` on MapNotify of windows first seen in CreateNotify whose
   title (`_NET_WM_NAME` → WM_NAME fallback) matches
   `$ZOOM_OSD_WINDOW_REGEX` (default `zoom_linux_float_message_reminder`).
   The created-set handshake exists because xmonad's `copyToAllHook` on
   that popup (xmonad.hs:262) unmaps/remaps it on EVERY workspace switch —
   only CreateNotify→MapNotify sequences count, remaps are ignored.
   `_show`/`_hide` got a `threading.Lock` (`_show_lock`) with `_show_locked`
   / `_hide_locked` inner functions because both the dbus loop (main
   thread) and the watcher thread call them.

## CURRENT BUG — where debugging stopped

Test: `timeout 6 nix run nixpkgs#xterm -- -T zoom_linux_float_message_reminder -geometry 20x5+100+100`
(xterm not installed; use nix run) against the running service.

Observed: `pgrep -P <daemon-pid> -a` showed `[Thread-1 (_watc] <defunct>`
— i.e. the fork happened INSIDE the watcher thread and the OSD child
died immediately; no overlay appeared. `/proc/<pid>/status` showed
Threads: 2, so the watcher thread itself is alive and the title match
DID fire (the fork proves it).

Working hypothesis (NOT yet verified): forking from the non-main thread
is the problem —

- The child inherits only the calling thread; it then calls
  `display_on_all_monitors()` which opens a fresh X Display, that part
  should be fine.
- BUT `sys.stderr.write` in `_on_window` runs before fork, fine; the
  child's exception handler writes to stderr and exits 0 — the defunct
  status means nobody waitpid'ed it: SIGCHLD is delivered to the MAIN
  thread's handler `_on_sigchld` which should reap... it clearly didn't
  reap (defunct persisted). Possible: main thread was blocked in
  `for ... in proc.stdout` readline and the signal handler did run but
  `_child_pid` bookkeeping raced, or the child ACTUALLY crashed before
  os.\_exit (e.g. `display_on_all_monitors` raised at import/connect
  time inside a forked-from-thread process — cairo/xlib state cloned
  from the watcher thread's Display could be corrupt).
- The last foreground run to capture the child's stderr
  (`timeout 20 zoom-osd --duration 5 > /tmp/zoom-osd-fg5.log 2>&1` then
  spawning the xterm) was interrupted before the log could be read.
  /tmp/zoom-osd-fg5.log may still exist — READ IT FIRST.

## Next debugging steps (in order)

1. `cat /tmp/zoom-osd-fg5.log` — if the foreground run captured a
   `zoom-osd[child]: ...` line, that's the child crash reason.
2. If empty, rerun: start `timeout 20 zoom-osd --duration 5 >/tmp/log 2>&1`
   in background, `sleep 3`, spawn the fake xterm (nix run, command
   above — run as SEPARATE Bash calls, the bash-gate hook rejects
   mixing them), read /tmp/log. Expect `zoom-osd: window: <title>` from
   `_on_window` plus any child error.
3. Likely fix if fork-from-thread is confirmed broken: don't fork in the
   watcher thread. Instead have `_watch_windows` push events into a
   `queue.Queue` / write to a pipe that the MAIN loop selects on
   alongside dbus-monitor stdout (e.g. use `selectors` over
   `proc.stdout` + an `os.pipe()` written by the thread), so all
   fork/exec happens on the main thread. Alternative: subprocess
   (`subprocess.Popen([sys.executable-ish zoom-osd wrapper, "--show",
text])`) instead of os.fork — cleaner across threads; `zoom-osd
--show` already exists and works (verified). NOTE: the impl binary
   path is `zoom-osd-impl` inside the writeShellScriptBin wrapper;
   `shutil.which("zoom-osd")` resolves the wrapper which re-execs impl —
   spawning `zoom-osd --show <text> --duration N` via Popen is the
   simplest robust fix.
4. ALSO unverified: whether a REAL Zoom meeting reminder produces a
   CreateNotify at all — user says "I still have that notification
   window open", i.e. Zoom may keep ONE reminder window alive and
   re-populate/remap it for later notifications. If so the created-set
   handshake will miss every notification after the first. Check with a
   real meeting once the fake-xterm path works: if no OSD, relax the
   logic (e.g. also trigger on MapNotify without CreateNotify but
   debounce with a per-window-id cooldown timestamp instead of the
   created set; or watch PropertyNotify for title/geometry changes on
   an existing reminder window — needs
   `w.change_attributes(event_mask=PropertyChangeMask)` per matching
   window).
5. After it works: restart service, real-meeting test, update
   `xwindow/AGENTS.md` "Zoom notification OSD" section (it currently
   documents the window watcher as if finished — the "Limitation" line
   about in-place updates is already there but verify wording matches
   final implementation), delete this handoff file, commit.

## File/state inventory

- `xwindow/bin/zoom-osd.py` — all logic. Committed across several jj
  commits on main (latest relevant: "feat: run X window watcher thread
  in zoom-osd with lock-guarded show/hide", plus an uncommitted-then-
  squashed flake8 fix removing a stray `global _child_pid` from the
  outer `_show`). Current file state: `_show` outer has NO global (F824
  fixed); verified via rg before last rebuild.
- `home-manager.configsymlink/home.nix` — `zoom-osd` =
  writeShellScriptBin wrapper exporting
  `ZOOM_OSD_DBUS_MONITOR=${pkgs.dbus}/bin/dbus-monitor`, exec'ing inner
  `writePython3Bin "zoom-osd-impl"` with libraries pycairo, xlib + osd
  (flakeIgnore E501 E731 W503). NOTE: python-xlib import added for the
  watcher (`from Xlib import X, Xatom, display`) — xlib lib was already
  in the list. dbus-python/pygobject3 were REMOVED when BecomeMonitor
  was abandoned... actually check: the lib list may still carry them
  harmlessly; current list per last read was [pycairo xlib] + osd.
- `home-manager.configsymlink/gnome.nix` — `systemd.user.services.zoom-osd`
  (PartOf/After graphical-session.target, Restart=on-failure,
  ExecStart=${config.home.profileDirectory}/bin/zoom-osd). Service is
  loaded+enabled+active. Last `home-manager switch` succeeded
  (2026-08-08) and service was manually restarted; MainPID at that
  point was 1417178 (stale by now if machine/service restarted).
- `xwindow/AGENTS.md` — "Zoom notification OSD" section between
  "Battery OSD" and "Hangul (Korean input) OSD" documents both paths.
- Rebuild loop: `jj -R ~/.dotfiles st` (snapshot! flake reads git index
  via jj — without a snapshot the new file "does not exist"), then
  `home-manager switch --impure --flake ~/.dotfiles/home-manager.configsymlink`,
  then `systemctl --user restart zoom-osd.service` (path change alone
  doesn't restart it).

## Environment gotchas for the next session

- bash-gate hook (`~/.claude/hooks/bash-gate.py`): no `find`/`grep`
  (use fd/rg), no `$(...)` substitution, no for/while loops, no piping
  into mutating xargs, no mixing review-needed + safe commands in one
  call, no leading `cd &&`, inline scripts ≤8 lines. Split commands
  accordingly.
- journalctl is NOT readable (LDAP user, no adm group) — capture daemon
  output by running zoom-osd in foreground redirected to /tmp instead.
- `timeout N zoom-osd ...` exits 124 — that's the timeout, not a crash.
- Verify visually with `scrot -o /tmp/x.png` + Read (multi-monitor:
  3 screens, overlay appears on all).
- Zoom windows for reference: reminder popup title
  `zoom_linux_float_message_reminder` (WM_CLASS zoom.zoom, UTILITY,
  358x202); in-meeting floating video `zoom_linux_float_video_window`;
  meeting window title `Meeting`; xmonad rules at
  xwindow/xmonad.symlink/xmonad.hs:252-268 (manageHook: reminder →
  doFloat + copyToAllHook + insertPosition Below Older; meetingRules
  shift zoom to "8:meeting").
- xmonad ALSO has stripZoomFullscreenHook + rescueOffscreenHook event
  hooks (xmonad.hs:58) — user asked earlier to check whether the
  reminder window is filtered by multiple handlers; the manageHook
  reminder rule (copyToAllHook) is what causes remap storms on
  workspace switches, hence the created-set. No other handler touches
  the reminder window (checked meetingRules + fsHook + logHook
  followToCurrentWorkspace only matches float_video_window).
- OSD style: Zoom blue #2D8CFF fill_rgb=(0.176,0.549,1.0), alpha 0.8,
  height_frac 0.25, centered; text "summary — body" whitespace-
  collapsed, truncated at 60 chars; DEFAULT_DURATION 6.0s;
  `--show TEXT`/`--render-png PATH` test modes work.
- User instructions doc (rule 4/5): end responses with `요약:` Korean
  paragraph in 존댓말; no first-person; CLI-style output.

## Quick smoke tests

- Display path: `zoom-osd --show "test" --duration 3` → overlay, exit 0.
- Notification path: with service running,
  `notify-send --app-name=Zoom "who" "what"` → child process under the
  service MainPID + overlay for 6s.
- Window path (currently broken): fake window via
  `timeout 6 nix run nixpkgs#xterm -- -T zoom_linux_float_message_reminder -geometry 20x5+100+100`.
