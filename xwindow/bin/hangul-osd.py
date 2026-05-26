"""
hangul-osd — persistent overlay shown on every monitor while ibus's
hangul engine is in Hangul (not English) input mode.

Signal source: `org.gnome.Flashback.InputSources` D-Bus interface,
member `Changed` (path `/org/gnome/Flashback/InputSources`). Emitted by
gnome-flashback whenever ibus's tray-state changes — including the
ibus-hangul engine-internal Hangul/English toggle (Shift+Space). The
signal carries no payload, so we follow each notification with a
synchronous `GetInputSources` call and inspect `icon-text`:

    icon-text == '한'  → Hangul mode → show OSD
    icon-text == 'EN' → English mode → hide OSD

Why this works under xmonad+gnome-flashback when other paths don't:

- The IBus library `IBus.Bus` doesn't expose a `global-engine-changed`
  PyGObject signal in this version (the binding raises
  `unknown signal name`), and the underlying ibus daemon only
  broadcasts on D-Bus when GNOME Shell drives source switches — which
  isn't happening for us.
- gnome-flashback runs in our session and synthesises its own
  InputSources view by listening to ibus engine state, so it sees the
  engine-internal Hangul/English toggle even when ibus stays on the
  same source.

On transition into hangul, fork() a child running
display_on_all_monitors("한", duration=∞, style); on transition out,
SIGTERM the child (the osd library installs a SIGTERM handler that
tears its X windows down cleanly). Idle when no toggles happen.

Deps (via home-manager wrapper):
    osd (pycairo + python-xlib transitively)
    pygobject3
    GI typelibs: Pango, PangoCairo, cairo (gobject-introspection),
        IBus, harfbuzz — set on GI_TYPELIB_PATH by the wrapper
    libfontconfig at runtime (loaded via ctypes for app-font
        registration; HANGUL_OSD_FONT_FILE points at the ttf)
"""

from __future__ import annotations

import argparse
import os
import signal
import sys

import cairo
from osd import OSDStyle, display_on_all_monitors, render_surface


# Visual style: warm amber/mustard, top-right corner, sized in mm so it
# looks the same physical size everywhere.
STYLE = OSDStyle(
    fill_rgb=(0.972, 0.733, 0.239),    # LEGO Bright Light Orange #F8BB3D
    fill_alpha=1.0,
    outline_rgb=None,
    shadow_rgba=None,
    font_family="JejuHallasan",
    # JejuHallasan only ships Regular — keep cairo weight at NORMAL.
    font_weight=cairo.FONT_WEIGHT_NORMAL,
    # Pango (vs cairo's toy API) for reliable family matching. JejuHallasan
    # itself doesn't appear in PangoCairo.FontMap.list_families() because
    # its English glyph coverage is incomplete (the ttf is missing 20
    # ASCII glyphs and gets dropped from the default fontmap). The
    # `font_file` below registers the ttf with fontconfig as an
    # application-private font, which bypasses that filter.
    use_pango=True,
    font_file=os.environ.get("HANGUL_OSD_FONT_FILE"),
    width_mm=60.0,
    height_mm=70.0,
    text_pad_w_frac=0.85,
    text_pad_h_frac=0.85,
    anchor_x="right",
    offset_x_frac=-0.015,
    anchor_y="top",
    offset_y_frac=0.02,
    per_monitor_size=True,
)

TEXT = "한"

# Long enough to be effectively infinite (~32 years). The osd library's
# SIGTERM handler is what actually ends the run.
FOREVER_SEC = 10**9


_child_pid: int | None = None


def show() -> None:
    global _child_pid
    if _child_pid is not None:
        return
    pid = os.fork()
    if pid == 0:
        try:
            display_on_all_monitors(TEXT, FOREVER_SEC, STYLE)
        except Exception as e:
            sys.stderr.write(f"hangul-osd[child]: {e}\n")
        os._exit(0)
    _child_pid = pid


def hide() -> None:
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
    """Reap any exited children (defensive)."""
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


def _is_hangul_mode(connection) -> bool:
    """Query gnome-flashback for the current input-source state and
    return True when the engine reports Hangul mode."""
    from gi.repository import Gio
    try:
        result = connection.call_sync(
            "org.gnome.Flashback",
            "/org/gnome/Flashback/InputSources",
            "org.gnome.Flashback.InputSources",
            "GetInputSources",
            None,
            None,  # reply type — auto
            Gio.DBusCallFlags.NONE,
            500,   # timeout ms
            None,  # cancellable
        )
    except Exception as e:
        sys.stderr.write(f"hangul-osd: GetInputSources failed: {e}\n")
        return False
    # Signature: (a(ussb), a{sv}). The second element holds icon-text /
    # InputMode property; the first element is the source list itself.
    _sources, current = result.unpack()
    return current.get("icon-text", "") == "한"


def _on_changed(connection, sender, path, iface, signal_name, params, _user_data):
    if _is_hangul_mode(connection):
        show()
    else:
        hide()


def _run_daemon() -> int:
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("hangul-osd: $DISPLAY not set\n")
        return 1

    signal.signal(signal.SIGCHLD, _on_sigchld)

    def _cleanup(*_a):
        hide()
        sys.exit(0)
    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    from gi.repository import Gio, GLib

    bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
    bus.signal_subscribe(
        "org.gnome.Flashback",                  # sender
        "org.gnome.Flashback.InputSources",     # interface
        "Changed",                              # member
        "/org/gnome/Flashback/InputSources",    # path
        None,                                   # arg0
        Gio.DBusSignalFlags.NONE,
        _on_changed,
        None,                                   # user_data
    )

    # Initial state: gnome-flashback may already be in hangul when we start.
    if _is_hangul_mode(bus):
        show()

    GLib.MainLoop().run()
    return 0


def _run_once() -> int:
    """Show the OSD on every monitor without watching anything. Ctrl-C
    or SIGTERM to clear. Useful for visual sanity checks."""
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("hangul-osd: $DISPLAY not set\n")
        return 1
    display_on_all_monitors(TEXT, FOREVER_SEC, STYLE)
    return 0


def _render_png(path: str, screen: str) -> int:
    try:
        sw, sh = (int(s) for s in screen.split("x"))
    except ValueError:
        sys.stderr.write(f"hangul-osd: invalid --screen: {screen}\n")
        return 2
    render_surface(TEXT, sw, sh, STYLE, monitor_mm=(518, 324)).write_to_png(path)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        prog="hangul-osd",
        description="Persistent OSD while ibus-hangul is in Hangul mode.",
    )
    p.add_argument("--render-png", metavar="PATH",
                   help="render an offline preview PNG and exit")
    p.add_argument("--screen", metavar="WxH", default="1920x1200",
                   help="screen size for --render-png (default 1920x1200)")
    p.add_argument("--once", action="store_true",
                   help="show OSD on every monitor without watching ibus "
                        "(Ctrl-C / SIGTERM to clear)")
    args = p.parse_args()

    if args.render_png:
        return _render_png(args.render_png, args.screen)
    if args.once:
        return _run_once()
    return _run_daemon()


if __name__ == "__main__":
    sys.exit(main())
