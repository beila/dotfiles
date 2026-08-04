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
case-insensitive), fork a child running display_on_all_monitors() for a
few seconds — fork-per-show exactly like hangul-osd, so a crash in the
X/render path never takes down the monitor loop.

Second trigger — Zoom's own popup window: the Linux client does NOT call
org.freedesktop.Notifications for meeting invites; it draws its own X
window titled `zoom_linux_float_message_reminder`. A daemon thread
watches root SubstructureNotify and fires the OSD on the first MapNotify
of a newly *created* window whose title matches $ZOOM_OSD_WINDOW_REGEX.
The created-set handshake keeps workspace-switch remaps (xmonad
unmaps/remaps the copyToAllHook'd popup on every switch) from
retriggering. Limitation: if Zoom updates an already-open reminder
window in place for a later notification, no event fires.

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


_child_pid: int | None = None


def _show(text: str, duration: float) -> None:
    global _child_pid
    _hide()
    pid = os.fork()
    if pid == 0:
        try:
            display_on_all_monitors(text, duration, STYLE)
        except Exception as e:
            sys.stderr.write(f"zoom-osd[child]: {e}\n")
        os._exit(0)
    _child_pid = pid


def _hide() -> None:
    global _child_pid
    if _child_pid is None:
        return
    pid = _child_pid
    _child_pid = None
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass


def _on_sigchld(*_a) -> None:
    """Reap children that finished their display duration (also reaps a
    dying dbus-monitor; its stdout EOF ends the main loop separately)."""
    global _child_pid
    while True:
        try:
            pid, _ = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        if pid == 0:
            return
        if pid == _child_pid:
            _child_pid = None


def _dbus_monitor_bin() -> str | None:
    return (os.environ.get("ZOOM_OSD_DBUS_MONITOR")
            or shutil.which("dbus-monitor"))


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

    signal.signal(signal.SIGCHLD, _on_sigchld)

    proc = subprocess.Popen([monitor, "--session", MATCH_RULE],
                            stdout=subprocess.PIPE, text=True)

    def _cleanup(*_a):
        _hide()
        proc.terminate()
        sys.exit(0)
    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

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
