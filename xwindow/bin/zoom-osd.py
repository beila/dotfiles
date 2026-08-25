"""
zoom-osd — huge overlay when a Zoom desktop notification appears.

Small notification bubbles (gnome-flashback's daemon, top edge) are easy
to miss when focused elsewhere; this mirrors battery-osd's look for Zoom
events (meeting started, chat message, waiting room) so they can't be
missed.

Mechanism: a long-lived daemon (systemd user service, like hangul-osd)
spawns `dbus-monitor "type='method_call',...member='Notify'"` and parses
its stdout — observing every org.freedesktop.Notifications.Notify call
regardless of which daemon displays them, without replacing that daemon.
(dbus-python's BecomeMonitor + message filter was tried first and never
delivered the method calls — libdbus auto-replies to unhandled method
calls, which a monitor may not do — so the proven dbus-monitor text
output is parsed instead.)

When the Notify app_name matches $ZOOM_OSD_APP_REGEX (default: zoom,
case-insensitive), spawn this program in --show mode for a few seconds.
The subprocess isolates X/render failures from the monitor loop and is
safe to launch from either the main thread or the X watcher thread.

Second trigger — Zoom's own popup windows: the Linux client does NOT call
org.freedesktop.Notifications for meeting invites or the meeting startup
window. A daemon thread watches newly created root windows and fires the
OSD as soon as their properties or first map reveal either:

* its title matches $ZOOM_OSD_WINDOW_REGEX (default:
  `zoom_linux_float_message_reminder`), or
* it has the new meeting-window signature: title `Zoom Workplace`, Zoom
  WM_CLASS, and `_KDE_NET_WM_WINDOW_TYPE_OVERRIDE`.

The full signature avoids matching Zoom's ordinary main window, which
uses the same generic title. Property watching is required because xmonad
can shift the meeting window to a hidden workspace before it is ever
mapped. The created-set handshake keeps workspace-switch remaps (xmonad
unmaps/remaps the copyToAllHook'd popup on every switch) from retriggering.
Limitation: if Zoom updates an already-open reminder window in place for
a later notification, no event fires.

Deps (via home-manager: writers.writePython3Bin with libraries=[osd]):
    osd (pycairo + python-xlib transitively)
    dbus-monitor binary ($ZOOM_OSD_DBUS_MONITOR, else PATH)

Usage:
    zoom-osd                                  # daemon (systemd service)
    zoom-osd --show "Meeting started"         # visual sanity check
    zoom-osd --show "text" --duration 3
    zoom-osd --render-png /tmp/preview.png    # offline test
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import signal
import subprocess
import sys
import threading

from osd import OSDStyle, display_on_all_monitors, render_surface
from Xlib import X, Xatom, display


# Zoom brand blue (#2D8CFF), same alpha/geometry family as battery-osd
# (centered, fraction-sized — OSDStyle defaults).
STYLE = OSDStyle(
    fill_rgb=(0.176, 0.549, 1.0),
    fill_alpha=0.8,
    height_frac=0.25,
)

DEFAULT_DURATION = 6.0
DEFAULT_APP_REGEX = "zoom"
DEFAULT_WINDOW_REGEX = "zoom_linux_float_message_reminder"
ZOOM_WORKPLACE_TITLE = "Zoom Workplace"
KDE_OVERRIDE_WINDOW_TYPE = "_KDE_NET_WM_WINDOW_TYPE_OVERRIDE"

MATCH_RULE = ("type='method_call',"
              "interface='org.freedesktop.Notifications',member='Notify'")

MAX_TEXT_CHARS = 60

# dbus-monitor argument lines: `   string "..."` / `   uint32 0` etc.
# For a Notify call the string args appear in order: app_name, app_icon,
# summary, body (replaces_id/actions/hints don't print as bare strings
# before the `array [` that ends the fixed args).
_STRING_LINE = re.compile(r'^\s+string "(.*)"$')


def _format_text(summary: str, body: str) -> str:
    summary = " ".join(summary.split())
    body = " ".join(body.split())
    text = f"{summary} — {body}" if summary and body else (summary or body or "Zoom")
    if len(text) > MAX_TEXT_CHARS:
        text = text[:MAX_TEXT_CHARS - 1] + "…"
    return f"  {text}  "


_child_proc: subprocess.Popen | None = None
# _show/_hide are called from the dbus-monitor loop (main thread) AND the
# X window-watcher thread.
_show_lock = threading.RLock()


def _show(text: str, duration: float) -> None:
    with _show_lock:
        _show_locked(text, duration)


def _show_locked(text: str, duration: float) -> None:
    global _child_proc
    _hide_locked()
    program = shutil.which(sys.argv[0]) or os.path.abspath(sys.argv[0])
    try:
        proc = subprocess.Popen([
            sys.executable,
            program,
            "--show",
            text,
            "--duration",
            str(duration),
        ])
    except OSError as e:
        sys.stderr.write(f"zoom-osd: failed to start display subprocess: {e}\n")
        return
    _child_proc = proc
    threading.Thread(target=_reap_child, args=(proc,), daemon=True).start()


def _reap_child(proc: subprocess.Popen) -> None:
    global _child_proc
    returncode = proc.wait()
    with _show_lock:
        if proc is not _child_proc:
            return
        _child_proc = None
    if returncode != 0:
        sys.stderr.write(
            f"zoom-osd: display subprocess exited {returncode}\n"
        )


def _hide() -> None:
    with _show_lock:
        _hide_locked()


def _hide_locked() -> None:
    global _child_proc
    if _child_proc is None:
        return
    proc = _child_proc
    _child_proc = None
    try:
        proc.terminate()
    except ProcessLookupError:
        pass
    proc.wait()


def _dbus_monitor_bin() -> str | None:
    return (os.environ.get("ZOOM_OSD_DBUS_MONITOR")
            or shutil.which("dbus-monitor"))


def _window_title(dpy, win) -> str:
    """_NET_WM_NAME with WM_NAME fallback; '' on any race with a window
    that's already gone."""
    try:
        net_wm_name = dpy.get_atom("_NET_WM_NAME")
        utf8 = dpy.get_atom("UTF8_STRING")
        prop = win.get_full_property(net_wm_name, utf8)
        if prop is None:
            prop = win.get_full_property(Xatom.WM_NAME, Xatom.STRING)
        if prop is None or not prop.value:
            return ""
        raw = prop.value
        return raw.decode("utf-8", "replace") if isinstance(raw, bytes) else str(raw)
    except Exception:
        return ""


def _is_zoom_popup(dpy, win, title: str, win_re: re.Pattern) -> bool:
    """Match legacy title-based popups and Zoom's generic-titled meeting
    startup window without treating the ordinary main window as a popup."""
    if win_re.search(title):
        return True
    if title != ZOOM_WORKPLACE_TITLE:
        return False

    try:
        wm_class = win.get_wm_class() or ()
        if not any(str(value).lower() == "zoom" for value in wm_class):
            return False

        type_atom = dpy.get_atom("_NET_WM_WINDOW_TYPE")
        override_atom = dpy.get_atom(KDE_OVERRIDE_WINDOW_TYPE,
                                     only_if_exists=True)
        prop = win.get_full_property(type_atom, Xatom.ATOM)
        return (override_atom != X.NONE
                and prop is not None
                and override_atom in prop.value)
    except Exception:
        # The client may disappear between MapNotify and the property reads.
        return False


def _stop_tracking_window(win, pending: set[int]) -> None:
    pending.discard(win.id)
    try:
        win.change_attributes(event_mask=X.NoEventMask)
    except Exception:
        pass


def _match_pending_window(dpy, win, win_re: re.Pattern,
                          pending: set[int], on_match) -> bool:
    """Match a newly created window once and stop tracking it."""
    if win.id not in pending:
        return False
    title = _window_title(dpy, win)
    if not _is_zoom_popup(dpy, win, title, win_re):
        return False
    _stop_tracking_window(win, pending)
    on_match(title)
    return True


def _handle_window_event(dpy, ev, win_re: re.Pattern,
                         pending: set[int], on_match) -> None:
    """Update watcher state for one root/child event."""
    if ev.type == X.CreateNotify:
        pending.add(ev.window.id)
        try:
            # Hidden-workspace clients may never map, so observe the
            # identifying properties directly. sync() closes the race where
            # Zoom set them before this client selected PropertyChangeMask.
            ev.window.change_attributes(event_mask=X.PropertyChangeMask)
            dpy.sync()
        except Exception:
            pending.discard(ev.window.id)
            return
        _match_pending_window(dpy, ev.window, win_re, pending, on_match)
    elif ev.type == X.DestroyNotify:
        pending.discard(ev.window.id)
    elif ev.type == X.PropertyNotify:
        _match_pending_window(dpy, ev.window, win_re, pending, on_match)
    elif ev.type == X.MapNotify and ev.window.id in pending:
        if not _match_pending_window(dpy, ev.window, win_re,
                                     pending, on_match):
            _stop_tracking_window(ev.window, pending)


def _watch_windows(win_re: re.Pattern, on_match) -> None:
    """Watch newly created root windows for _is_zoom_popup matches.

    Runs in a daemon thread with its own Display connection (python-xlib
    connections aren't thread-safe to share). Properties are checked from
    creation until the first map, allowing a Zoom meeting window shifted
    directly to a hidden workspace to trigger without MapNotify. Only windows
    seen in a CreateNotify during our watch count: xmonad unmaps/remaps the
    copyToAllHook'd reminder popup on every workspace switch, and those
    remaps must not retrigger the OSD."""
    dpy = display.Display()
    root = dpy.screen().root
    root.change_attributes(event_mask=X.SubstructureNotifyMask)
    dpy.flush()
    pending: set[int] = set()
    while True:
        _handle_window_event(dpy, dpy.next_event(), win_re,
                             pending, on_match)


def _notify_events(stdout):
    """Yield (app_name, summary, body) per Notify call in dbus-monitor
    output. Collects the first 4 `string` argument lines after each
    method-call header; `array [` ends the fixed args early (bodies with
    literal newlines lose their tail — fine for a glanceable OSD)."""
    strings: list[str] | None = None
    for line in stdout:
        if "member=Notify" in line and "method call" in line:
            strings = []
            continue
        if strings is None:
            continue
        m = _STRING_LINE.match(line)
        if m is not None:
            strings.append(m.group(1))
            if len(strings) == 4:
                yield strings[0], strings[2], strings[3]
                strings = None
        elif line.lstrip().startswith("array ["):
            strings = None


def _run_daemon(duration: float) -> int:
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("zoom-osd: $DISPLAY not set; can't open X display\n")
        return 1

    monitor = _dbus_monitor_bin()
    if monitor is None:
        sys.stderr.write("zoom-osd: dbus-monitor not found "
                         "(set $ZOOM_OSD_DBUS_MONITOR)\n")
        return 1

    app_re = re.compile(os.environ.get("ZOOM_OSD_APP_REGEX", DEFAULT_APP_REGEX),
                        re.IGNORECASE)

    proc = subprocess.Popen([monitor, "--session", MATCH_RULE],
                            stdout=subprocess.PIPE, text=True)

    def _cleanup(*_a):
        _hide()
        proc.terminate()
        sys.exit(0)
    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    # Zoom's meeting-invite popup is its own X window, not a
    # freedesktop notification — watch for it in parallel.
    win_re = re.compile(os.environ.get("ZOOM_OSD_WINDOW_REGEX",
                                       DEFAULT_WINDOW_REGEX))

    def _on_window(title: str) -> None:
        sys.stderr.write(f"zoom-osd: window: {title}\n")
        summary = ("Zoom meeting" if title == ZOOM_WORKPLACE_TITLE
                   else "Zoom meeting reminder")
        _show(_format_text(summary, ""), duration)

    threading.Thread(target=_watch_windows, args=(win_re, _on_window),
                     daemon=True).start()

    for app_name, summary, body in _notify_events(proc.stdout):
        if app_re.search(app_name):
            text = _format_text(summary, body)
            sys.stderr.write(f"zoom-osd: {app_name}: {text.strip()}\n")
            _show(text, duration)

    # dbus-monitor exited (session bus went away): let systemd restart us.
    sys.stderr.write("zoom-osd: dbus-monitor exited\n")
    return 1


def main() -> int:
    p = argparse.ArgumentParser(
        prog="zoom-osd",
        description="Huge overlay for Zoom desktop notifications "
                    "(cairo + XShape, battery-osd style).",
    )
    p.add_argument("--duration", type=float, default=DEFAULT_DURATION,
                   help=f"visible seconds per notification (default {DEFAULT_DURATION:g})")
    p.add_argument("--show", metavar="TEXT",
                   help="display TEXT once and exit (visual sanity check)")
    p.add_argument("--render-png", metavar="PATH",
                   help="render to PNG instead of displaying (test mode)")
    p.add_argument("--screen", metavar="WxH", default="3840x2400",
                   help="screen size for --render-png mode (default 3840x2400)")
    args = p.parse_args()

    if args.render_png:
        try:
            sw, sh = (int(s) for s in args.screen.split("x"))
        except ValueError:
            sys.stderr.write(f"zoom-osd: invalid --screen: {args.screen}\n")
            return 2
        text = _format_text(args.show or "Meeting started", "")
        render_surface(text, sw, sh, STYLE).write_to_png(args.render_png)
        return 0

    if args.show is not None:
        if not os.environ.get("DISPLAY"):
            sys.stderr.write("zoom-osd: $DISPLAY not set; can't open X display\n")
            return 1
        display_on_all_monitors(_format_text(args.show, ""), args.duration, STYLE)
        return 0

    return _run_daemon(args.duration)


if __name__ == "__main__":
    sys.exit(main())
