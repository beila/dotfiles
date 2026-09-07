"""
hangul-osd — persistent overlay shown on every monitor while ibus's
hangul engine is in Hangul (not English) input mode.

Signal source: the IBus private message bus returned by
`IBus.get_address()`, object `/org/freedesktop/IBus/Panel`, interface
`com.canonical.IBus.Panel.Private`. The existing panel emits:

    PropertyUpdated(v)       on an engine-internal mode toggle
    PropertiesRegistered(v) when focus changes to an input context

Both payloads contain a serialized `IBusProperty` named `InputMode`.
Its state is 0 for English and 1 for Hangul. The gnome-flashback
`GetInputSources()` result cannot be used here: its `icon-text` says
which engine is selected and stays `한` even while ibus-hangul is in
English mode.

On transition into hangul, fork() a child running
display_on_all_monitors("한", duration=∞, style); on transition out,
SIGTERM the child (the osd library installs a SIGTERM handler that
tears its X windows down cleanly). Idle when no toggles happen.
Startup stays hidden until the panel reports an `InputMode` property.

Deps (via home-manager wrapper):
    osd (pycairo + python-xlib transitively)
    pygobject3
    GI typelibs: Rsvg (SVG rasterisation), cairo (gobject-introspection),
        IBus, harfbuzz — set on GI_TYPELIB_PATH by the wrapper
    HANGUL_OSD_IMAGE points at the packaged hangul.svg. No font,
        fontconfig, or Pango at runtime — the glyph is a pre-outlined
        vector asset (see xwindow/osd/assets/generate.py).
"""

from __future__ import annotations

import argparse
import os
import signal
import sys

from osd import (
    HANGUL_SLOT_HEIGHT_MM,
    HANGUL_SLOT_OFFSET_X_FRAC,
    HANGUL_SLOT_OFFSET_Y_FRAC,
    HANGUL_SLOT_WIDTH_MM,
    OSDStyle,
    display_on_all_monitors,
    render_surface,
)


# Visual style: a pre-outlined vector SVG (JejuHallasan "한" with the LEGO
# Bright Light Orange #F8BB3D baked in) painted at 0.8 alpha. No font at
# runtime — the glyph is stored as paths and rasterised by librsvg at the exact
# per-monitor pixel size, crisp at any DPI (font dependency moved to
# asset-authoring time; see xwindow/osd/assets/generate.py). Position derives
# from the shared HANGUL_SLOT_* constants in the osd library so the Midway MW
# sibling OSD can anchor beside this exact box without the two drifting apart.
# HANGUL_OSD_IMAGE points at the packaged hangul.svg.
STYLE = OSDStyle(
    fill_alpha=0.8,
    outline_rgb=None,
    shadow_rgba=None,
    image_file=os.environ.get("HANGUL_OSD_IMAGE"),
    width_mm=HANGUL_SLOT_WIDTH_MM,
    height_mm=HANGUL_SLOT_HEIGHT_MM,
    text_pad_w_frac=0.85,
    text_pad_h_frac=0.85,
    anchor_x="right",
    offset_x_frac=HANGUL_SLOT_OFFSET_X_FRAC,
    anchor_y="top",
    offset_y_frac=HANGUL_SLOT_OFFSET_Y_FRAC,
    per_monitor_size=True,
)

TEXT = "한"

# Long enough to be effectively infinite (~32 years). The osd library's
# SIGTERM handler is what actually ends the run.
FOREVER_SEC = 10**9

IBUS_PANEL_PATH = "/org/freedesktop/IBus/Panel"
IBUS_PANEL_PRIVATE_IFACE = "com.canonical.IBus.Panel.Private"


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


def _deep_unpack(value):
    """Convert nested GLib.Variant containers into Python values."""
    unpack = getattr(value, "unpack", None)
    if unpack is not None:
        return _deep_unpack(unpack())
    if isinstance(value, dict):
        return {key: _deep_unpack(item) for key, item in value.items()}
    if isinstance(value, (list, tuple)):
        return type(value)(_deep_unpack(item) for item in value)
    return value


def _input_mode_from_payload(payload) -> bool | None:
    """Return the serialized InputMode state, or None when absent."""
    value = _deep_unpack(payload)

    def find_input_mode(item):
        if isinstance(item, dict):
            children = item.values()
        elif isinstance(item, (list, tuple)):
            if (
                len(item) >= 10
                and item[0] == "IBusProperty"
                and item[2] == "InputMode"
            ):
                state = item[9]
                if type(state) is int and state in (0, 1):
                    return bool(state)
                return None
            children = item
        else:
            return None

        for child in children:
            mode = find_input_mode(child)
            if mode is not None:
                return mode
        return None

    return find_input_mode(value)


class ModeIndicator:
    """Apply only real English/Hangul transitions to the OSD."""

    def __init__(self, show_osd=show, hide_osd=hide):
        self._show = show_osd
        self._hide = hide_osd
        self._mode = False

    def observe(self, mode: bool | None) -> None:
        if mode is None or mode == self._mode:
            return
        self._mode = mode
        if mode:
            self._show()
        else:
            self._hide()


_indicator = ModeIndicator()


def _on_property_signal(
    connection,
    sender,
    path,
    iface,
    signal_name,
    params,
    _user_data,
):
    _indicator.observe(_input_mode_from_payload(params))


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

    import gi

    gi.require_version("IBus", "1.0")
    from gi.repository import Gio, GLib, IBus

    address = IBus.get_address()
    if not address:
        sys.stderr.write("hangul-osd: IBus private-bus address not found\n")
        return 1

    flags = (
        Gio.DBusConnectionFlags.AUTHENTICATION_CLIENT
        | Gio.DBusConnectionFlags.MESSAGE_BUS_CONNECTION
    )
    bus = Gio.DBusConnection.new_for_address_sync(
        address,
        flags,
        None,  # observer
        None,  # cancellable
    )
    bus.signal_subscribe(
        None,                       # sender: the private bus is already scoped
        IBUS_PANEL_PRIVATE_IFACE,
        None,                       # both supported signal members
        IBUS_PANEL_PATH,
        None,                       # arg0
        Gio.DBusSignalFlags.NONE,
        _on_property_signal,
        None,                       # user_data
    )

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
