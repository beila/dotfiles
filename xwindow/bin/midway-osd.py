"""
midway-osd — persistent, click-through overlay shown on every monitor while
the local Midway session is invalid (expired, missing, unreadable, malformed,
or otherwise without a future session-cookie expiry).

State source: `midway-genmon --status`, which prints `valid <expiry-epoch>` /
`invalid` and exits 0/1 using the SAME cookie parser as the xfce4-genmon panel.
This daemon never opens or parses `~/.midway/cookie` itself — there is exactly
one parser. It never runs `mwinit`, contacts Midway, or reads cookie/token
contents.

Triggering is event-driven so the OSD appears effectively instantly, without
busy-polling:
  1. Cookie create/delete/replace — a Gio.FileMonitor (inotify) on the cookie
     *directory* re-evaluates within milliseconds. Watching the directory (not
     just the file) catches the delete+recreate an `mwinit` refresh performs.
  2. Time-based expiry with the file untouched — the `valid <epoch>` word lets
     the daemon arm a one-shot GLib timer to fire the instant the session
     crosses expiry. No filesystem event happens then, so this scheduled timer
     (re-armed on every change) is what makes pure expiry instant.
  3. Startup (login/reboot) — evaluated once immediately before the loop.
  4. A slow safety-net poll (SAFETY_POLL_SEC) is only a backstop for events the
     above can miss — chiefly suspend/resume, where GLib's monotonic timer
     under-counts slept wall-clock time.
Gio/GLib are already dependencies (pygobject3) and inotify is desktop-agnostic,
so none of this adds a package or ties the daemon to GNOME.

Visual: a pre-outlined vector SVG asset (Cinzel Decorative Black "MW" — ornate
engraved Roman capitals — with the LEGO colour 21 "Bright Red" #B40000 baked
in) painted at 0.5 alpha, no background, no outline, no shadow. No font is
loaded at runtime — the glyph is stored as paths and rasterised by librsvg at
the exact per-monitor pixel size, so it is crisp at any DPI (the font
dependency moved to asset-authoring time; see xwindow/osd/assets/generate.py).
The box is sized to the asset's aspect, vertically centred inside the 70 mm
Hangul 한 slot and seated 2 mm to its LEFT so both stay on-screen at the
top-right. Adjacency and centring are derived from the shared HANGUL_SLOT_*
constants via osd.sibling_offset_mm() and a physical mm offset, so nothing
drifts across monitor sizes or DPI.

Lifecycle mirrors hangul-osd: a long-lived daemon that fork()s one child
running display_on_all_monitors(...) while invalid, and SIGTERMs it when valid
again. Show/hide are idempotent — repeated invalid observations do not spawn a
second child, repeated valid observations do not double-kill.

Deps (via home-manager wrapper): osd (pycairo + python-xlib), pygobject3 for
the GLib main loop, GLib timers, and the Gio.FileMonitor cookie watch, the GI
typelibs Rsvg (SVG rasterisation) and cairo,
and MIDWAY_OSD_IMAGE pointing at the packaged mw.svg. No font, fontconfig, or
Pango at runtime, and MIDWAY_GENMON pointing at the midway-genmon script.
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys

from osd import (
    HANGUL_SLOT_HEIGHT_MM,
    HANGUL_SLOT_OFFSET_X_FRAC,
    HANGUL_SLOT_OFFSET_Y_FRAC,
    HANGUL_SLOT_WIDTH_MM,
    OSDStyle,
    display_on_all_monitors,
    render_surface,
    sibling_offset_mm,
)


TEXT = "MW"

# Physical gap between the MW box's right edge and the 한 box's left edge.
GAP_MM = 2.0

# The MW box is sized to the mw.svg asset's intrinsic aspect ratio so the
# vector glyph fills it exactly with no letterboxing. The asset (Cinzel
# Decorative Black "MW", 939×481) is ~1.95:1; at 42 mm tall that is ~82 mm
# wide. 42 mm height keeps the box shorter than the 70 mm 한 slot so it can sit
# vertically centred inside it.
BOX_HEIGHT_MM = 42.0
_MW_ASSET_ASPECT = 939.0 / 481.0
BOX_WIDTH_MM = round(BOX_HEIGHT_MM * _MW_ASSET_ASPECT, 1)   # ≈ 82.0 mm

# The 42 mm box is vertically centred inside the 70 mm 한 slot rather than
# top-aligned: it shares the slot's top offset, then steps down by half the
# height difference so equal margins sit above and below it.
_VERTICAL_CENTER_MM = (HANGUL_SLOT_HEIGHT_MM - BOX_HEIGHT_MM) / 2

# Reference box the MW sibling seats beside: the exact Hangul slot geometry.
# Built from the shared constants so both OSDs share one right-edge inset and
# top offset.
_HANGUL_REF = OSDStyle(
    width_mm=HANGUL_SLOT_WIDTH_MM,
    height_mm=HANGUL_SLOT_HEIGHT_MM,
    anchor_x="right",
    offset_x_frac=HANGUL_SLOT_OFFSET_X_FRAC,
)

# Visual style: a pre-outlined vector SVG (Cinzel Decorative Black "MW" ornate
# engraved Roman capitals, baked LEGO colour 21 "Bright Red" #B40000) painted
# at 0.5 alpha. No font is
# loaded at runtime — the glyph is stored as paths in the asset and rasterised
# by librsvg at the exact per-monitor pixel size, so it stays crisp at any DPI.
# The box is sized to the asset aspect, vertically centred inside the 70 mm 한
# slot and seated 2 mm to its LEFT (shares the slot's right-edge inset and top
# offset, plus a fixed-mm leftward sibling offset). MIDWAY_OSD_IMAGE points at
# the packaged mw.svg.
STYLE = OSDStyle(
    fill_alpha=0.5,                    # exactly 50% opacity
    outline_rgb=None,
    shadow_rgba=None,
    image_file=os.environ.get("MIDWAY_OSD_IMAGE"),
    width_mm=BOX_WIDTH_MM,
    height_mm=BOX_HEIGHT_MM,
    text_pad_w_frac=0.85,
    text_pad_h_frac=0.85,
    anchor_x="right",
    # Shares the 한 box's right-edge inset, then steps left by
    # (한 width + gap) millimetres so its right edge sits GAP_MM left of the
    # 한 box's left edge — independent of monitor px size / DPI.
    offset_x_frac=HANGUL_SLOT_OFFSET_X_FRAC,
    offset_x_mm=sibling_offset_mm(_HANGUL_REF, GAP_MM),
    anchor_y="top",
    # Shares the 한 slot's top offset, then steps down by half the 70→42 mm
    # height difference so the shorter MW box is vertically centred inside the
    # slot instead of top-aligned. mm (not frac) keeps the centring identical
    # across mixed-DPI monitors.
    offset_y_frac=HANGUL_SLOT_OFFSET_Y_FRAC,
    offset_y_mm=_VERTICAL_CENTER_MM,
    per_monitor_size=True,
)

# Long enough to be effectively infinite (~32 years). The osd library's
# SIGTERM handler is what actually ends a child run.
FOREVER_SEC = 10**9

# Slow safety-net poll. The daemon is event-driven (file-watch + a one-shot
# timer scheduled to the exact expiry instant), so this is only a backstop for
# events those miss — chiefly a suspend/resume where the monotonic scheduled
# timer under-counts wall-clock time. Deliberately slow: instant response comes
# from the events, not this.
SAFETY_POLL_SEC = 300


# Cookie file whose directory the daemon watches for create/delete/replace.
# The parser (midway-genmon) is the authority on *validity*; this path is used
# only to place the inotify watch. Mirrors midway-genmon's default and its
# MIDWAY_COOKIE_FILE override so the two never point at different files.
def _cookie_file() -> str:
    return os.environ.get(
        "MIDWAY_COOKIE_FILE", os.path.expanduser("~/.midway/cookie")
    )


def _genmon_cmd() -> list[str]:
    """Command that prints the machine-readable Midway status word.

    MIDWAY_GENMON is set by the home-manager wrapper to the packaged
    midway-genmon path; falls back to PATH lookup for local runs.
    """
    genmon = os.environ.get("MIDWAY_GENMON", "midway-genmon")
    return [genmon, "--status"]


def midway_status(run=subprocess.run) -> tuple[bool, int | None]:
    """Return (invalid, expiry_epoch) from `midway-genmon --status`.

    Output contract: `valid <epoch>` when a session-cookie expiry lies strictly
    in the future, `invalid` otherwise. Delegates entirely to the shared parser
    so semantics match the panel genmon exactly. `expiry_epoch` is the absolute
    epoch second the session goes invalid (only when valid) — the daemon uses
    it to schedule a one-shot timer to that instant. Any failure to obtain a
    clean `valid <epoch>` — non-zero exit, missing binary, unexpected output —
    is treated as invalid (fail-safe: show the reminder rather than hide a real
    expiry), with expiry None.
    """
    try:
        proc = run(
            _genmon_cmd(),
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, ValueError) as e:
        sys.stderr.write(f"midway-osd: cannot run midway-genmon: {e}\n")
        return True, None
    parts = proc.stdout.split()
    if not parts or parts[0] != "valid":
        return True, None
    expiry: int | None = None
    if len(parts) >= 2:
        try:
            expiry = int(parts[1])
        except ValueError:
            expiry = None
    return False, expiry


def midway_is_invalid(run=subprocess.run) -> bool:
    """Back-compat boolean wrapper around midway_status()."""
    return midway_status(run)[0]


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
            sys.stderr.write(f"midway-osd[child]: {e}\n")
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


class MidwayIndicator:
    """Apply only real valid↔invalid transitions to the OSD.

    Idempotent: the OSD is shown on the first invalid observation and hidden
    on the first valid observation after being shown; repeated same-state
    observations are no-ops, so windows are never duplicated and never
    double-torn-down. The indicator starts in the valid/hidden state, so a
    startup-invalid session shows immediately on the first poll while a
    startup-valid session shows nothing.
    """

    def __init__(self, show_osd=show, hide_osd=hide):
        self._show = show_osd
        self._hide = hide_osd
        # Start in the valid/hidden state: nothing is shown yet, so the first
        # invalid observation shows and the first valid observation is a
        # no-op (mirrors hangul-osd's ModeIndicator). Startup-invalid still
        # shows on the very first poll because invalid != False.
        self._invalid: bool = False

    def observe(self, invalid: bool) -> None:
        if invalid == self._invalid:
            return
        self._invalid = invalid
        if invalid:
            self._show()
        else:
            self._hide()


def _run_daemon() -> int:
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("midway-osd: $DISPLAY not set\n")
        return 1

    signal.signal(signal.SIGCHLD, _on_sigchld)

    def _cleanup(*_a):
        hide()
        sys.exit(0)
    signal.signal(signal.SIGTERM, _cleanup)
    signal.signal(signal.SIGINT, _cleanup)

    from gi.repository import Gio, GLib

    indicator = MidwayIndicator()

    # Handle to the pending one-shot expiry timer so we can cancel/replace it
    # whenever we re-evaluate (a new cookie means a new expiry instant).
    expiry_source: dict[str, int | None] = {"id": None}

    def _evaluate() -> None:
        """Re-read status, drive the OSD, and (re)arm the expiry timer.

        This is the single choke point every trigger funnels through:
        startup, the file-watch, the scheduled-expiry fire, and the safety
        poll all call it. Because MidwayIndicator is idempotent, calling it
        redundantly is harmless.
        """
        invalid, expiry = midway_status()
        indicator.observe(invalid)

        # Cancel any previously-scheduled expiry timer; we recompute below.
        if expiry_source["id"] is not None:
            GLib.source_remove(expiry_source["id"])
            expiry_source["id"] = None

        # While valid, schedule a one-shot timer to fire the instant the
        # session crosses expiry — no polling for the time-based case. +1 s so
        # the shell-out re-reads *after* the boundary (genmon uses `>`).
        if not invalid and expiry is not None:
            import time
            delay = expiry - int(time.time()) + 1
            if delay < 1:
                delay = 1
            expiry_source["id"] = GLib.timeout_add_seconds(delay, _on_expiry)

    def _on_expiry() -> bool:
        expiry_source["id"] = None
        _evaluate()
        return False  # one-shot

    # 1) Instant on cookie create/delete/replace: watch the *directory* (a
    #    refresh is usually delete+recreate, which a file-only watch misses).
    #    Gio.FileMonitor is GLib/Gio — already a dependency, and inotify-based,
    #    so this is desktop-agnostic (no GNOME, no extra package).
    cookie_dir = os.path.dirname(_cookie_file()) or "."
    monitor = None
    try:
        gfile = Gio.File.new_for_path(cookie_dir)
        monitor = gfile.monitor_directory(Gio.FileMonitorFlags.WATCH_MOVES, None)

        def _on_dir_change(_m, _f, _other, _event):
            _evaluate()

        monitor.connect("changed", _on_dir_change)
    except Exception as e:
        # If the watch can't be established (dir missing, etc.) the safety
        # poll below still catches changes; degrade, don't crash.
        sys.stderr.write(f"midway-osd: file watch unavailable: {e}\n")

    # 2) Slow safety-net poll: only a backstop for events the watch + scheduled
    #    timer can miss (chiefly suspend/resume, where the monotonic expiry
    #    timer under-counts slept wall-clock time). Instant response does NOT
    #    depend on this.
    def _safety_poll() -> bool:
        _evaluate()
        return True

    _evaluate()  # 3) evaluate once at startup (login/reboot is immediate)
    GLib.timeout_add_seconds(SAFETY_POLL_SEC, _safety_poll)
    GLib.MainLoop().run()
    if monitor is not None:
        monitor.cancel()
    return 0


def _run_once() -> int:
    """Show the OSD on every monitor without watching Midway. Ctrl-C or
    SIGTERM to clear. Useful for visual sanity checks; reads no credentials."""
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("midway-osd: $DISPLAY not set\n")
        return 1
    display_on_all_monitors(TEXT, FOREVER_SEC, STYLE)
    return 0


def _render_png(path: str, screen: str) -> int:
    """Offline preview PNG. Reads no credentials — renders the fixed MW box."""
    try:
        sw, sh = (int(s) for s in screen.split("x"))
    except ValueError:
        sys.stderr.write(f"midway-osd: invalid --screen: {screen}\n")
        return 2
    render_surface(TEXT, sw, sh, STYLE, monitor_mm=(518, 324)).write_to_png(path)
    return 0


def main() -> int:
    p = argparse.ArgumentParser(
        prog="midway-osd",
        description="Persistent OSD while the local Midway session is invalid.",
    )
    p.add_argument("--render-png", metavar="PATH",
                   help="render an offline preview PNG and exit")
    p.add_argument("--screen", metavar="WxH", default="1920x1200",
                   help="screen size for --render-png (default 1920x1200)")
    p.add_argument("--once", action="store_true",
                   help="show OSD on every monitor without watching Midway "
                        "(Ctrl-C / SIGTERM to clear)")
    args = p.parse_args()

    if args.render_png:
        return _render_png(args.render_png, args.screen)
    if args.once:
        return _run_once()
    return _run_daemon()


if __name__ == "__main__":
    sys.exit(main())
