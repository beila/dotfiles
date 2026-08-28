"""Make a named top-level X11 OSD window ignore pointer input."""

import argparse
import sys
import time

from Xlib import X, display, error
from Xlib.ext import shape


def make_click_through(window):
    window.shape_rectangles(
        shape.SO.Set,
        shape.SK.Input,
        X.Unsorted,
        0,
        0,
        [],
    )


def matching_windows(root, title):
    matches = []
    for window in root.query_tree().children:
        try:
            if window.get_wm_name() == title:
                matches.append(window)
        except error.BadWindow:
            # Short-lived OSDs can disappear between QueryTree and WM_NAME.
            continue
    return matches


def input_region_is_empty(window):
    return not window.shape_get_rectangles(shape.SK.Input).rectangles


def process_windows(title, timeout, check_only=False):
    connection = display.Display()
    root = connection.screen().root
    deadline = time.monotonic() + timeout

    try:
        while True:
            windows = matching_windows(root, title)
            if windows:
                try:
                    if check_only:
                        connection.sync()
                        return all(input_region_is_empty(window) for window in windows)
                    for window in windows:
                        make_click_through(window)
                    connection.sync()
                    return True
                except error.BadWindow:
                    # Retry if a matching popup expired during the request.
                    pass

            if time.monotonic() >= deadline:
                return False
            time.sleep(0.02)
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(
        description="Make a named top-level X11 OSD window click-through."
    )
    parser.add_argument("title", help="Exact WM_NAME of the OSD window")
    parser.add_argument(
        "--timeout",
        type=float,
        default=2.0,
        help="Seconds to wait for the window to appear (default: 2)",
    )
    parser.add_argument(
        "--check",
        action="store_true",
        help="Check for an empty input region without modifying the window",
    )
    args = parser.parse_args()

    if process_windows(args.title, args.timeout, args.check):
        return 0
    action = "verify" if args.check else "make click-through"
    sys.stderr.write(f"osd-click-through: could not {action}: {args.title}\n")
    return 1


if __name__ == "__main__":
    sys.exit(main())
