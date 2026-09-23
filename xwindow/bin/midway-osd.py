"""
midway-osd — persistent, click-through MW overlay while work auth is unusable.

The daemon consumes the same `midway-status` TSV result as midway-genmon.
Only definite Midway invalid states show the overlay; AEA-only failures are
left to the genmon tooltip and the authentication guard. An explicit unknown
state preserves the last definite state, avoiding a false transition during a
transient network failure.

Cookie and status-cache directory watches make authentication changes visible
immediately. A one-shot timer catches local expiry without a file change, and
a slow poll checks for server-side revocation when neither file changes.
"""

from __future__ import annotations

import argparse
import os
import signal
import subprocess
import sys
import time

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
RESOURCE_NAME = "midway-osd"
GAP_MM = 2.0
BOX_HEIGHT_MM = 42.0
BOX_WIDTH_MM = round(BOX_HEIGHT_MM * (939.0 / 481.0), 1)
FOREVER_SEC = 10**9
SAFETY_POLL_SEC = 60
DISPLAY_HEALTH_POLL_SEC = 5

_HANGUL_REFERENCE = OSDStyle(
    width_mm=HANGUL_SLOT_WIDTH_MM,
    height_mm=HANGUL_SLOT_HEIGHT_MM,
    anchor_x="right",
    offset_x_frac=HANGUL_SLOT_OFFSET_X_FRAC,
)

STYLE = OSDStyle(
    fill_alpha=0.5,
    outline_rgb=None,
    shadow_rgba=None,
    image_file=os.environ.get("MIDWAY_OSD_IMAGE"),
    width_mm=BOX_WIDTH_MM,
    height_mm=BOX_HEIGHT_MM,
    anchor_x="right",
    offset_x_frac=HANGUL_SLOT_OFFSET_X_FRAC,
    offset_x_mm=sibling_offset_mm(_HANGUL_REFERENCE, GAP_MM),
    anchor_y="top",
    offset_y_frac=HANGUL_SLOT_OFFSET_Y_FRAC,
    offset_y_mm=(HANGUL_SLOT_HEIGHT_MM - BOX_HEIGHT_MM) / 2,
    per_monitor_size=True,
)


def _status_command() -> str:
    return os.environ.get(
        "MIDWAY_STATUS_COMMAND",
        os.path.expanduser("~/.dotfiles/bin/midway-status"),
    )


def _cookie_file() -> str:
    return os.environ.get(
        "MIDWAY_COOKIE_FILE",
        os.path.expanduser("~/.midway/cookie"),
    )


def _status_cache_file() -> str:
    default_dir = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
    return os.environ.get(
        "MIDWAY_STATUS_CACHE_FILE",
        os.path.join(default_dir, f"midway-status-{os.getuid()}.cache"),
    )


def midway_status(
    run=subprocess.run,
) -> tuple[bool | None, int | None]:
    """Return (invalid, next_expiry).

    invalid=True means a definite Midway failure, False means the OSD should
    stay hidden, and None means live verification is unavailable. AEA-only
    failures hide the OSD but remain invalid to other status consumers.
    Malformed output or an execution failure is fail-safe invalid.
    """
    try:
        proc = run(
            [_status_command()],
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
        )
    except (OSError, ValueError) as error:
        sys.stderr.write(f"midway-osd: cannot run midway-status: {error}\n")
        return True, None

    lines = proc.stdout.splitlines()
    if not lines:
        return True, None
    fields = lines[0].split("\t")
    if len(fields) < 2:
        return True, None

    state = fields[0]
    try:
        expiry = int(fields[1])
    except ValueError:
        expiry = None
    reason = fields[3] if len(fields) >= 4 else ""

    if state == "valid" and proc.returncode == 0 and expiry is not None:
        return False, expiry
    if state == "invalid" and reason in {
        "aea-cookie",
        "aea-missing",
        "aea-posture",
    }:
        return False, expiry
    if state in {"invalid", "expired", "missing"}:
        return True, expiry
    if state == "unknown":
        return None, expiry
    return True, None


_child_process: subprocess.Popen | None = None


def _child_is_running() -> bool:
    global _child_process
    if _child_process is None:
        return False
    if _child_process.poll() is None:
        return True
    _child_process = None
    return False


def _display() -> None:
    display_on_all_monitors(
        TEXT,
        FOREVER_SEC,
        STYLE,
        resource_name=RESOURCE_NAME,
        follow_monitor_changes=True,
    )


def show() -> None:
    global _child_process
    if _child_is_running():
        return
    _child_process = subprocess.Popen(
        [sys.executable, os.path.abspath(__file__), "--once"],
        stdin=subprocess.DEVNULL,
    )


def hide() -> None:
    global _child_process
    if not _child_is_running():
        return
    process = _child_process
    _child_process = None
    try:
        process.terminate()
    except ProcessLookupError:
        pass
    try:
        process.wait()
    except ChildProcessError:
        pass


class MidwayIndicator:
    """Keep the display aligned with the latest definite status."""

    def __init__(self, show_osd=show, hide_osd=hide):
        self._show = show_osd
        self._hide = hide_osd
        self._invalid = False

    def observe(self, invalid: bool | None) -> None:
        if invalid is None:
            return
        if invalid:
            self._invalid = True
            self._show()
        elif self._invalid:
            self._invalid = False
            self._hide()

    def ensure_display(self) -> None:
        if self._invalid:
            self._show()


def _run_daemon() -> int:
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("midway-osd: $DISPLAY not set\n")
        return 1

    def cleanup(*_args):
        hide()
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    from gi.repository import Gio, GLib

    indicator = MidwayIndicator()
    expiry_source: int | None = None

    def on_expiry() -> bool:
        nonlocal expiry_source
        expiry_source = None
        evaluate()
        return False

    def evaluate() -> None:
        nonlocal expiry_source
        invalid, expiry = midway_status()
        indicator.observe(invalid)

        if expiry_source is not None:
            GLib.source_remove(expiry_source)
            expiry_source = None

        if invalid is not True and expiry is not None and expiry > 0:
            delay = max(1, expiry - int(time.time()) + 1)
            expiry_source = GLib.timeout_add_seconds(delay, on_expiry)

    targets = {
        os.path.abspath(_cookie_file()),
        os.path.abspath(_status_cache_file()),
    }
    monitors = []

    def on_directory_change(_monitor, changed, other, _event) -> None:
        changed_paths = {
            os.path.abspath(path)
            for item in (changed, other)
            if item is not None
            for path in [item.get_path()]
            if path
        }
        if targets & changed_paths:
            evaluate()

    for directory in sorted({os.path.dirname(path) or "." for path in targets}):
        try:
            monitor = Gio.File.new_for_path(directory).monitor_directory(
                Gio.FileMonitorFlags.WATCH_MOVES,
                None,
            )
            monitor.connect("changed", on_directory_change)
            monitors.append(monitor)
        except Exception as error:  # noqa: BLE001
            sys.stderr.write(
                f"midway-osd: file watch unavailable for {directory}: {error}\n"
            )

    def safety_poll() -> bool:
        evaluate()
        return True

    def display_health_poll() -> bool:
        indicator.ensure_display()
        return True

    evaluate()
    GLib.timeout_add_seconds(SAFETY_POLL_SEC, safety_poll)
    GLib.timeout_add_seconds(DISPLAY_HEALTH_POLL_SEC, display_health_poll)
    GLib.MainLoop().run()
    for monitor in monitors:
        monitor.cancel()
    return 0


def _run_once() -> int:
    if not os.environ.get("DISPLAY"):
        sys.stderr.write("midway-osd: $DISPLAY not set\n")
        return 1
    _display()
    return 0


def _render_png(path: str, screen: str) -> int:
    try:
        width, height = (int(value) for value in screen.split("x"))
    except ValueError:
        sys.stderr.write(f"midway-osd: invalid --screen: {screen}\n")
        return 2
    render_surface(
        TEXT,
        width,
        height,
        STYLE,
        monitor_mm=(518, 324),
    ).write_to_png(path)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(
        prog="midway-osd",
        description="Persistent OSD while Midway is definitely unusable.",
    )
    parser.add_argument("--render-png", metavar="PATH")
    parser.add_argument("--screen", default="1920x1200", metavar="WxH")
    parser.add_argument("--once", action="store_true")
    args = parser.parse_args()

    if args.render_png:
        return _render_png(args.render_png, args.screen)
    if args.once:
        return _run_once()
    return _run_daemon()


if __name__ == "__main__":
    sys.exit(main())
