"""
zoom-osd — huge overlay when a Zoom desktop notification appears.

Small notification bubbles (gnome-flashback's daemon, top edge) are easy
to miss when focused elsewhere; this mirrors battery-osd's look for Zoom
events (meeting started, chat message, waiting room) so they can't be
missed.

Mechanism: a long-lived daemon (systemd user service, like hangul-osd)
opens a private session-bus connection and calls
`org.freedesktop.DBus.Monitoring.BecomeMonitor` for
`org.freedesktop.Notifications.Notify` method calls — the same primitive
dbus-monitor uses, so it observes every notification regardless of which
daemon displays them, without replacing that daemon. Falls back to the
legacy `eavesdrop=true` match rule for pre-BecomeMonitor dbus daemons.
When the Notify app_name matches $ZOOM_OSD_APP_REGEX (default: zoom,
case-insensitive), fork a child running display_on_all_monitors() for a
few seconds — fork-per-show exactly like hangul-osd, so a crash in the
X/render path never takes down the monitor loop.

Deps (via home-manager: writers.writePython3Bin with libraries=[osd]):
    osd (pycairo + python-xlib transitively)
    dbus-python (BecomeMonitor + message filter)
    pygobject3 (GLib main loop for dbus-python)

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
import signal
import sys

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

# Notify(app_name s, replaces_id u, app_icon s, summary s, body s,
#        actions as, hints a{sv}, expire_timeout i)
ARG_APP_NAME = 0
ARG_SUMMARY = 3
ARG_BODY = 4

MATCH_RULE = ("type='method_call',"
              "interface='org.freedesktop.Notifications',member='Notify'")

MAX_TEXT_CHARS = 60


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
    """Reap children that finished their display duration."""
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


def _run_daemon(duration: float) -> int:
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("zoom-osd: $DISPLAY not set; can't open X display\n")
        return 1

    app_re = re.compile(os.environ.get("ZOOM_OSD_APP_REGEX", DEFAULT_APP_REGEX),
                        re.IGNORECASE)

    signal.signal(signal.SIGCHLD, _on_sigchld)

    def _cleanup(*_a):
        _hide()
        sys.exit(0)
    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    import dbus
    import dbus.lowlevel
    import dbus.mainloop.glib
    from gi.repository import GLib

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    # Private connection: BecomeMonitor makes it receive-only, so it must
    # not be the shared instance other code might reuse.
    bus = dbus.SessionBus(private=True)

    def _on_message(_conn, msg):
        if (isinstance(msg, dbus.lowlevel.MethodCallMessage)
                and msg.get_interface() == "org.freedesktop.Notifications"
                and msg.get_member() == "Notify"):
            args = msg.get_args_list()
            app_name = str(args[ARG_APP_NAME])
            if app_re.search(app_name):
                text = _format_text(str(args[ARG_SUMMARY]), str(args[ARG_BODY]))
                sys.stderr.write(f"zoom-osd: {app_name}: {text.strip()}\n")
                _show(text, duration)
        return dbus.lowlevel.HANDLER_RESULT_NOT_YET_HANDLED

    bus.add_message_filter(_on_message)
    try:
        bus.call_blocking("org.freedesktop.DBus", "/org/freedesktop/DBus",
                          "org.freedesktop.DBus.Monitoring", "BecomeMonitor",
                          "asu", ([MATCH_RULE], dbus.UInt32(0)))
    except dbus.exceptions.DBusException as e:
        # Pre-1.9.10 dbus daemon: fall back to the deprecated eavesdrop rule.
        sys.stderr.write(f"zoom-osd: BecomeMonitor failed ({e}); "
                         "falling back to eavesdrop match rule\n")
        bus.add_match_string(f"eavesdrop=true,{MATCH_RULE}")

    GLib.MainLoop().run()
    return 0


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
