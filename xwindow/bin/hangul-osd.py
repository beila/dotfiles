"""
hangul-osd — persistent overlay shown on every monitor while ibus's
current engine is the Korean (hangul) one.

Subscribes to ibus's `global-engine-changed` D-Bus signal via PyGObject;
on transition into hangul, fork()s a child that calls
display_on_all_monitors("한", duration=∞, style); on transition out,
SIGTERMs the child (the osd library tears windows down on SIGTERM).

Idle when no engine changes — no polling, no work between signals.

Sized in physical mm (style.width_mm / height_mm) so the OSD looks the
same physical size on monitors with different pixel densities; GNOME's
display-scaling factor doesn't matter because we render directly with
Xlib in native pixels.

Deps (via home-manager: writers.writePython3Bin with libraries=[osd, pygobject3, ...]):
    osd (pycairo + python-xlib transitively)
    pygobject3 + ibus typelib

Usage:
    hangul-osd                          # daemon mode (needs $DISPLAY + ibus)
    hangul-osd --render-png /tmp/p.png  # offline preview render
    hangul-osd --once                   # show OSD without watching ibus (for visual check)
"""

from __future__ import annotations

import argparse
import os
import signal
import sys

from osd import OSDStyle, display_on_all_monitors, render_surface


# Visual style: warm amber/mustard, top-right corner, sized in mm so it
# looks the same physical size everywhere.
STYLE = OSDStyle(
    fill_rgb=(0.91, 0.64, 0.24),       # ~#E8A33D — warm amber
    outline_rgb=None,                  # no black ring around the glyph
    shadow_rgba=None,                  # no drop shadow either; keep just the glyph
    font_family="LXGW WenKai Mono",
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
    """Spawn a child that displays the OSD until killed."""
    global _child_pid
    if _child_pid is not None:
        return
    pid = os.fork()
    if pid == 0:
        # Child: hand off to the osd library. It installs SIGTERM/SIGINT
        # handlers that destroy the X windows cleanly before exiting.
        try:
            display_on_all_monitors(TEXT, FOREVER_SEC, STYLE)
        except Exception as e:
            sys.stderr.write(f"hangul-osd[child]: {e}\n")
        os._exit(0)
    _child_pid = pid


def hide() -> None:
    """Tell the OSD child to exit and reap it."""
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
    """Reap any exited children (defensive: child can also die on its own,
    e.g. X server restart)."""
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


def _on_engine_changed(_bus, name) -> None:
    # `name` may arrive as a GLib string or a plain str depending on the
    # binding; coerce defensively.
    n = str(name) if name is not None else ""
    if "hangul" in n.lower():
        show()
    else:
        hide()


def _run_daemon() -> int:
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("hangul-osd: $DISPLAY not set; can't open X display\n")
        return 1

    signal.signal(signal.SIGCHLD, _on_sigchld)

    def _cleanup(*_a):
        hide()
        sys.exit(0)

    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    import gi
    gi.require_version("IBus", "1.0")
    from gi.repository import GLib, IBus

    bus = IBus.Bus()
    if not bus.is_connected():
        sys.stderr.write("hangul-osd: not connected to ibus daemon\n")
        return 1

    bus.connect("global-engine-changed", _on_engine_changed)

    # Initial state — ibus may already be in hangul when we start.
    try:
        engine = bus.get_global_engine()
    except Exception:
        engine = None
    if engine is not None:
        _on_engine_changed(bus, engine.get_name())

    GLib.MainLoop().run()
    return 0


def _run_once() -> int:
    """Show the OSD until the user kills us with Ctrl-C / SIGTERM. For
    visual sanity-checking without ibus."""
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
    # Approximate the laptop's reported mm size for the preview so the
    # PNG looks like what you'd see on screen. Override with --mm if needed.
    render_surface(TEXT, sw, sh, STYLE, monitor_mm=(518, 324)).write_to_png(path)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        prog="hangul-osd",
        description="Persistent OSD shown while ibus is in the hangul engine.",
    )
    p.add_argument("--render-png", metavar="PATH",
                   help="render an offline preview PNG and exit")
    p.add_argument("--screen", metavar="WxH", default="1920x1200",
                   help="screen size for --render-png (default 1920x1200)")
    p.add_argument("--once", action="store_true",
                   help="show the OSD on every monitor without watching ibus "
                        "(visual sanity check; Ctrl-C to exit)")
    args = p.parse_args()

    if args.render_png:
        return _render_png(args.render_png, args.screen)
    if args.once:
        return _run_once()
    return _run_daemon()


if __name__ == "__main__":
    sys.exit(main())
