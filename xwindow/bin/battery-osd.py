"""
battery-osd — huge "󰂃 X%" overlay for low-battery alerts.

Thin wrapper around the `osd` library: parses a percentage, picks the
visual style, and either shows the OSD on all monitors or renders a
preview PNG (test mode).

Deps (via home-manager: writers.writePython3Bin with libraries=[osd]):
    osd (which transitively depends on pycairo + python-xlib)

Usage:
    battery-osd <percent>
    battery-osd <percent> --duration 5
    battery-osd <percent> --render-png /tmp/preview.png   # offline test
"""

from __future__ import annotations

import argparse
import os
import sys

from osd import OSDStyle, display_on_all_monitors, render_surface


# Battery alert styling. Other OSDs (volume, brightness, audio) will pick
# different fill colours / anchors when they migrate to this library.
STYLE = OSDStyle(
    fill_rgb=(1.0, 0.19, 0.19),  # #ff3030
)


def _format_text(percent: int) -> str:
    # \U000F0083 = 󰂃 (nf-md-battery_alert in Nerd Fonts).
    return f"  \U000F0083  {percent}%  "


def main() -> int:
    p = argparse.ArgumentParser(
        prog="battery-osd",
        description="Huge pseudo-transparent battery OSD (cairo + XShape).",
    )
    p.add_argument("percent", type=int, help="battery percentage to display")
    p.add_argument("--duration", type=float, default=10.0,
                   help="visible seconds (default 10)")
    p.add_argument("--render-png", metavar="PATH",
                   help="render to PNG instead of displaying (test mode)")
    p.add_argument("--screen", metavar="WxH", default="3840x2400",
                   help="screen size for --render-png mode (default 3840x2400)")
    args = p.parse_args()

    if not (0 <= args.percent <= 100):
        sys.stderr.write(f"battery-osd: percent out of range: {args.percent}\n")
        return 2

    text = _format_text(args.percent)

    if args.render_png:
        try:
            sw, sh = (int(s) for s in args.screen.split("x"))
        except ValueError:
            sys.stderr.write(f"battery-osd: invalid --screen: {args.screen}\n")
            return 2
        render_surface(text, sw, sh, STYLE).write_to_png(args.render_png)
        return 0

    if not os.environ.get("DISPLAY"):
        sys.stderr.write("battery-osd: $DISPLAY not set; can't open X display\n")
        return 1

    display_on_all_monitors(text, args.duration, STYLE)
    return 0


if __name__ == "__main__":
    sys.exit(main())
