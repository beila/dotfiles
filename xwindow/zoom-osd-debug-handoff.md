# zoom-osd sign-off handoff — 2026-08-08

Status: implementation and synthetic end-to-end verification are complete.
Do not delete this file until the user explicitly signs off.

## Implemented

`xwindow/bin/zoom-osd.py` has two push trigger paths:

1. Freedesktop `org.freedesktop.Notifications.Notify` calls observed through
   `dbus-monitor`, filtered by `$ZOOM_OSD_APP_REGEX` (default `zoom`).
2. X `CreateNotify`→`MapNotify` events for windows whose title matches
   `$ZOOM_OSD_WINDOW_REGEX` (default
   `zoom_linux_float_message_reminder`). The created-window handshake avoids
   retriggering on xmonad `copyToAllHook` workspace remaps.

Each match now starts the installed script as a fresh `--show` subprocess.
The previous `os.fork()` call ran from the X watcher thread; Python 3.14 warned
that forking the multi-threaded daemon could deadlock, and the child became
defunct before rendering. A reentrant lock now serializes display replacement,
and a daemon reaper thread waits for normal child exit. New triggers terminate
and wait for the prior display process before starting another.

## Verification completed

- `ruff check xwindow/bin/zoom-osd.py` passes.
- `home-manager switch --impure --flake ~/.dotfiles/home-manager.configsymlink`
  rebuilt and activated the new `zoom-osd` package successfully.
- `zoom-osd.service` was restarted and remains active.
- Synthetic X-window trigger:
  `timeout 8 nix run nixpkgs#xterm -- -T zoom_linux_float_message_reminder
  -geometry 20x5+100+100` produced live, non-defunct `zoom-osd-impl --show`
  children under both a foreground daemon and the systemd service.
- The active screenshot differed from the pre-trigger screenshot by about
  1.24 million pixels, consistent with the large overlay on all monitors.
- After the configured duration, the display children were reaped and the
  service stayed active.
- Freedesktop trigger:
  `notify-send --app-name=Zoom "zoom-osd regression test" "notification path"`
  was parsed by a foreground daemon and produced the expected live
  `zoom-osd-impl --show ... --duration 30.0` subprocess.
- Interrupting the foreground daemon terminated its active display child.
- Two consecutive notifications preempted correctly: the first child exited,
  exactly one second-notification child remained, and no Zoom OSD zombie was
  created.

## Pending sign-off

Test one real Zoom meeting reminder. The synthetic window proves the X event,
matching, subprocess, and rendering path, but Zoom may reuse an already-created
reminder window and update it in place. The current watcher intentionally does
not fire for such in-place updates; this limitation is documented in
`xwindow/AGENTS.md`.

After explicit user sign-off, delete this file and record that deletion with
`jj`.
