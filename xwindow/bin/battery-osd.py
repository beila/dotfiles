"""
battery-osd — huge centred "󰂃 X%" overlay with no background block.

Renders the text with cairo (huge JetBrainsMono Nerd Font Bold, red fill,
black outline, drop shadow), then displays it in an override-redirect X
window whose XShape mask is derived from the rendered alpha. The result is
a pseudo-transparent overlay: only the text pixels (and their shadow) are
part of the window, everything else shows whatever's underneath. No
compositor needed.

On multi-monitor setups, one OSD window is shown per monitor, each rendered
to that monitor's own dimensions.

Deps (provided by home-manager: python3.withPackages [ pycairo xlib ]):
    pycairo>=1.20, python-xlib>=0.33

Usage:
    battery-osd <percent>
    battery-osd --render-png /tmp/preview.png <percent>   # offline test
    battery-osd <percent> --duration 5
"""

from __future__ import annotations

import argparse
import os
import signal
import sys
import time

import cairo
from Xlib import X, display
from Xlib.ext import randr  # for multi-monitor enumeration
from Xlib.ext import shape  # noqa: F401  -- import enables window.shape_* methods

# Visual tuning. Kept as constants so they're easy to tweak without
# rummaging through layout code.
WIDTH_FRAC = 0.80          # window width as fraction of screen width
HEIGHT_FRAC = 0.35         # window height as fraction of screen height
TEXT_PAD_FRAC = 0.85       # leave breathing room inside the box (width)
TEXT_HEIGHT_FRAC = 0.70    # ditto (height)
FILL_RGB = (1.0, 0.19, 0.19)   # #ff3030
OUTLINE_RGB = (0.0, 0.0, 0.0)
SHADOW_RGBA = (0.0, 0.0, 0.0, 0.7)
ALPHA_THRESHOLD = 128      # >= this alpha is "opaque" for the XShape mask


def render_surface(percent: int, screen_w: int, screen_h: int) -> cairo.ImageSurface:
    """Render the OSD onto an ARGB32 cairo surface and return it."""
    w = int(screen_w * WIDTH_FRAC)
    h = int(screen_h * HEIGHT_FRAC)

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surface)

    text = f"  \U000F0083  {percent}%  "  # 󰂃 = nf-md-battery_alert

    # Use Nerd Font Bold. Cairo resolves via fontconfig, so the font must be
    # in fontconfig's path (home-manager's copyFonts activation handles this).
    ctx.select_font_face(
        "JetBrainsMono Nerd Font", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD
    )

    # Pick the largest size that fits both width and height with margins.
    # Bisection would be cleaner but linear-grow + back-off is plenty fast
    # for a one-shot script and avoids floating-point edge cases.
    size = 50
    last_good = size
    while size < 1000:
        ctx.set_font_size(size)
        ext = ctx.text_extents(text)
        if ext.width <= w * TEXT_PAD_FRAC and ext.height <= h * TEXT_HEIGHT_FRAC:
            last_good = size
            size += 4
        else:
            break
    ctx.set_font_size(last_good)
    ext = ctx.text_extents(text)

    # Centre the text using its tight bounding box (x_bearing/y_bearing
    # account for the offset between the glyph origin and the bbox).
    tx = (w - ext.width) / 2 - ext.x_bearing
    ty = (h - ext.height) / 2 - ext.y_bearing

    # Drop shadow: re-render the same text offset down-right in semi-black.
    shadow_off = max(4, last_good // 30)
    ctx.set_source_rgba(*SHADOW_RGBA)
    ctx.move_to(tx + shadow_off, ty + shadow_off)
    ctx.show_text(text)

    # Outline: stroke the text path with double-width line so half is "outside"
    # the glyph (the inside half is overwritten by the fill below).
    outline_w = max(2, last_good // 50)
    ctx.set_source_rgb(*OUTLINE_RGB)
    ctx.move_to(tx, ty)
    ctx.text_path(text)
    ctx.set_line_width(outline_w * 2)
    ctx.set_line_join(cairo.LINE_JOIN_ROUND)
    ctx.stroke()

    # Fill: solid red text on top of the outline.
    ctx.set_source_rgb(*FILL_RGB)
    ctx.move_to(tx, ty)
    ctx.show_text(text)

    surface.flush()
    return surface


def make_shape_mask(surface: cairo.ImageSurface) -> tuple[bytes, int, int]:
    """Build a 1-bit XShape mask from the surface's alpha channel.

    Returns (mask_bytes, width, height). Bit packing: LSBFirst within each
    byte, rows padded to whole bytes (X11 default for XYBitmap data).
    """
    iw = surface.get_width()
    ih = surface.get_height()
    stride = surface.get_stride()  # bytes per row in the source surface
    data = bytes(surface.get_data())

    row_bytes = (iw + 7) // 8
    mask = bytearray(row_bytes * ih)
    for y in range(ih):
        src_row = y * stride
        dst_row = y * row_bytes
        for x in range(iw):
            # Cairo ARGB32 little-endian byte order is BGRA; alpha is byte 3.
            a = data[src_row + x * 4 + 3]
            if a >= ALPHA_THRESHOLD:
                mask[dst_row + (x >> 3)] |= 1 << (x & 7)
    return bytes(mask), iw, ih


def _chunked_put_image(target, gc, fmt, depth, w, h, data, bytes_per_row):
    """python-xlib's PutImage uses a 16-bit length field (no BIG-REQUESTS),
    capping a single request at ~256 KB. Split tall/wide images into row
    chunks so each fits comfortably (we target ~64 KB per chunk).
    """
    max_chunk = 64 * 1024
    rows_per_chunk = max(1, max_chunk // bytes_per_row)
    for y0 in range(0, h, rows_per_chunk):
        rows = min(rows_per_chunk, h - y0)
        chunk = data[y0 * bytes_per_row:(y0 + rows) * bytes_per_row]
        target.put_image(gc, 0, y0, w, rows, fmt, depth, 0, chunk)


def get_monitors(d, root) -> list[tuple[int, int, int, int]]:
    """Enumerate currently-active monitors as (x, y, w, h) rectangles.

    Uses RandR's CRTC list (RandR 1.2+, available on every Linux desktop X
    server since ~2009) and filters out CRTCs with no mode set. Falls back
    to the whole virtual screen if RandR isn't available — meaning the OSD
    still works on headless or unusual setups, just centered on the
    bounding rect rather than per-monitor.

    Mirrored displays naturally produce duplicate (x, y, w, h) tuples; we
    de-dup so we don't render the same OSD twice on top of itself.
    """
    try:
        randr.query_version(d)
        res = root.xrandr_get_screen_resources()
        seen = set()
        out: list[tuple[int, int, int, int]] = []
        for crtc in res.crtcs:
            info = d.xrandr_get_crtc_info(crtc, res.config_timestamp)
            if info.width <= 0 or info.height <= 0 or info.mode == 0:
                continue
            rect = (info.x, info.y, info.width, info.height)
            if rect in seen:
                continue
            seen.add(rect)
            out.append(rect)
        if out:
            return out
    except Exception:
        # Any RandR failure: fall through to the whole-screen fallback.
        pass
    s = d.screen()
    return [(0, 0, s.width_in_pixels, s.height_in_pixels)]


def _create_osd_window(d, screen, root, rect, surface):
    """Create one OSD window at `rect` showing `surface`. Returns the
    window so it can be destroyed later. The XShape mask is applied before
    the window is mapped so it's never drawn as a rectangle even briefly.
    """
    mx, my, mw, mh = rect
    iw = surface.get_width()
    ih = surface.get_height()
    wx = mx + (mw - iw) // 2
    wy = my + (mh - ih) // 2

    win = root.create_window(
        wx, wy, iw, ih, 0,
        screen.root_depth,
        X.InputOutput,
        X.CopyFromParent,
        background_pixel=screen.black_pixel,
        override_redirect=1,
        event_mask=X.ExposureMask,
    )
    win.set_wm_name("battery-osd")
    win.set_wm_class("battery-osd", "battery-osd")

    mask_bytes, smw, smh = make_shape_mask(surface)
    pixmap = win.create_pixmap(smw, smh, 1)
    pgc = pixmap.create_gc(foreground=1, background=0)
    _chunked_put_image(pixmap, pgc, X.XYBitmap, 1, smw, smh, mask_bytes,
                       (smw + 7) // 8)
    win.shape_mask(shape.SO.Set, shape.SK.Bounding, 0, 0, pixmap)
    pgc.free()
    pixmap.free()

    win.map()

    gc = win.create_gc()
    _chunked_put_image(win, gc, X.ZPixmap, screen.root_depth, iw, ih,
                       bytes(surface.get_data()), iw * 4)
    gc.free()
    return win


def display_osd(percent: int, duration: float) -> None:
    """Show the OSD on every attached monitor for `duration` seconds.

    Each monitor gets a window sized to its own dimensions so the text
    fits proportionally on a 4K laptop and a 1080p external alike.
    """
    d = display.Display()
    screen = d.screen()
    root = screen.root

    monitors = get_monitors(d, root)
    windows = []
    for rect in monitors:
        try:
            surface = render_surface(percent, rect[2], rect[3])
            windows.append(_create_osd_window(d, screen, root, rect, surface))
        except Exception as e:
            sys.stderr.write(f"battery-osd: failed on monitor {rect}: {e}\n")
    d.sync()

    # Clean up on SIGTERM/SIGINT so a `pkill` or systemd kill doesn't
    # leave stale windows mapped on the root.
    def cleanup(*_a):
        for w in windows:
            try:
                w.unmap()
                w.destroy()
            except Exception:
                pass
        try:
            d.sync()
            d.close()
        except Exception:
            pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, cleanup)
    signal.signal(signal.SIGINT, cleanup)

    time.sleep(duration)

    for w in windows:
        try:
            w.unmap()
            w.destroy()
        except Exception:
            pass
    d.sync()
    d.close()


def render_png(percent: int, path: str, screen_w: int, screen_h: int) -> None:
    """Test-mode: render to a PNG instead of opening a window."""
    surface = render_surface(percent, screen_w, screen_h)
    surface.write_to_png(path)


def main() -> int:
    p = argparse.ArgumentParser(
        prog="battery-osd",
        description="Huge pseudo-transparent battery OSD (uses XShape).",
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

    if args.render_png:
        try:
            sw, sh = (int(s) for s in args.screen.split("x"))
        except ValueError:
            sys.stderr.write(f"battery-osd: invalid --screen: {args.screen}\n")
            return 2
        render_png(args.percent, args.render_png, sw, sh)
        return 0

    if not os.environ.get("DISPLAY"):
        sys.stderr.write("battery-osd: $DISPLAY not set; can't open X display\n")
        return 1

    display_osd(args.percent, args.duration)
    return 0


if __name__ == "__main__":
    sys.exit(main())
