"""
osd — cairo + ARGB/XShape OSD building blocks.

Renders text into a cairo ARGB32 surface (fill + outline + drop shadow),
then displays it in an override-redirect X window. With a compositor
(picom), uses a 32-bit ARGB visual for true alpha transparency — smooth
edges, semi-transparent fills, real drop shadows. Without a compositor,
falls back to an XShape mask (hard-clipped at alpha_threshold) for
pseudo-transparency. Works in both environments.

Multi-monitor: enumerates active CRTCs via Xrandr and shows one window
per monitor sized to that monitor; falls back to the whole virtual
screen if RandR is unavailable.

Public API:
    OSDStyle               — visual + layout config (dataclass)
    render_surface(...)    — text → cairo ImageSurface
    display_on_all_monitors(text, duration, style)  — one-shot show
    get_monitors(d, root)  — Xrandr-based active monitor list

Internal helpers (prefixed _) handle X11 plumbing: 1-bit mask packing,
chunked PutImage to dodge python-xlib's 16-bit length cap, per-monitor
window creation.

Performance caveat — designed for one-shot use only.
    Cold-start latency is ~700-800 ms (Python + cairo + import overhead +
    pure-Python pixel loop in _make_shape_mask + X plumbing). Fine for
    fire-and-forget alerts (battery, calendar reminders, build-failed
    flashes) where the user isn't expecting instant feedback.

    NOT suitable for keystroke-driven OSDs (volume / brightness / audio
    device cycle) without a daemon-mode addition. Those need < 100 ms
    perceived latency and rapid repeat handling, which today is provided
    by the dzen2 + FIFO scripts in xwindow/bin/. Migrating them here
    would require:
      - a long-running Python process per OSD type listening on a FIFO
      - re-render-into-existing-window on each new text (so the X window
        creation cost is paid once)
      - vectorising _make_shape_mask (currently ~50 ms in Python; numpy
        or bytes.translate would drop it to single-digit ms)
      - per-OSD systemd user service for lifecycle
    Roughly +150 LOC and four daemons to maintain — only worth it for
    the unified look, not as a goal in itself.
"""

from __future__ import annotations

import signal
import sys
import time
from dataclasses import dataclass, field

import cairo
from Xlib import X, display
from Xlib.ext import randr
from Xlib.ext import shape  # noqa: F401  -- import enables window.shape_* methods


# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------


@dataclass
class OSDStyle:
    """Visual + layout config for an OSD.

    Colours are RGB in 0..1; the shadow has an extra alpha component for the
    in-cairo composite (the final output is hard-clipped to opaque or fully
    transparent by the XShape mask).
    """
    # Colours
    fill_rgb: tuple[float, float, float] = (1.0, 0.19, 0.19)        # #ff3030
    # Alpha for the fill, 0..1. With picom (32-bit ARGB visual), this is
    # real transparency. Without a compositor, it acts as a brightness
    # multiplier (cairo premultiplies; X11 strips the alpha channel) and
    # pixels remain inside the XShape mask if alpha ≥ threshold.
    fill_alpha: float = 1.0
    outline_rgb: tuple[float, float, float] | None = (0.0, 0.0, 0.0)
    shadow_rgba: tuple[float, float, float, float] | None = (0.0, 0.0, 0.0, 0.7)

    # Font
    font_family: str = "JetBrainsMono Nerd Font"
    font_slant: int = cairo.FONT_SLANT_NORMAL
    font_weight: int = cairo.FONT_WEIGHT_BOLD

    # Box dimensions, as fractions of the target monitor.
    width_frac: float = 0.80
    height_frac: float = 0.35

    # Inside-the-box padding, so text never kisses the edge.
    text_pad_w_frac: float = 0.85
    text_pad_h_frac: float = 0.70

    # Anchor on the monitor: "top" | "center" | "bottom" plus an additional
    # vertical offset as a fraction of monitor height (negative is up).
    anchor_y: str = "center"
    offset_y_frac: float = 0.0

    # Horizontal anchoring (mirror of anchor_y).
    anchor_x: str = "center"   # "left" | "center" | "right"
    offset_x_frac: float = 0.0

    # Absolute size in millimetres. When BOTH are set, this overrides
    # width_frac / height_frac and the rendered OSD has the same physical
    # size across monitors with different pixel densities (uses Xrandr's
    # reported mm dimensions; falls back to 96 DPI if unavailable). Leave
    # None to keep the fractional-of-monitor behaviour.
    width_mm: float | None = None
    height_mm: float | None = None

    # Render text via Pango (PangoCairo) instead of cairo's toy font API.
    # The toy API's family-matching can silently fall through to a fallback
    # font when the requested family is hard to match against fontconfig's
    # generated fallback list (we hit this with `JejuHallasan` under
    # gnome-flashback — every Hangul codepoint became .notdef despite
    # `fc-match` resolving the family). Pango goes through the full
    # fontconfig + harfbuzz stack and matches reliably. Costs ~50–100 ms
    # extra per render (negligible vs. the 700-ms cold-start of the osd
    # library overall). Requires Pango / PangoCairo typelibs at runtime.
    use_pango: bool = False

    # Optional path to a ttf/otf file to register with fontconfig as an
    # application-private font (FcConfigAppFontAddFile) at render time.
    # Use this for fonts Pango's default fontmap hides — e.g. display
    # fonts whose `en` language coverage is incomplete (JejuHallasan is
    # missing 20 ASCII glyphs and gets dropped from
    # PangoCairo.FontMap.list_families() as a result, even though
    # fc-match resolves it). Only consulted when use_pango=True.
    font_file: str | None = None

    # Alpha threshold for the XShape mask (0..255). Pixels with alpha at or
    # above this become opaque; everything else is clipped.
    alpha_threshold: int = 128

    # Outline / shadow thickness as fractions of the chosen font size.
    # Override (set to floats > 0) to force specific values.
    outline_width_frac: float = 1.0 / 50
    shadow_offset_frac: float = 1.0 / 30

    # Multi-monitor behaviour:
    #   per_monitor_size=True  → render each monitor at its own dimensions
    #                           (battery-osd: laptop 4K + external 1080p both
    #                           look right because text scales to each panel)
    #   per_monitor_size=False → one fixed-size render, placed on each monitor
    per_monitor_size: bool = True


# Default singleton kept for callers who don't customise.
DEFAULT_STYLE = OSDStyle()


# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------


def render_surface(
    text: str,
    monitor_w: int,
    monitor_h: int,
    style: OSDStyle | None = None,
    monitor_mm: tuple[int, int] | None = None,
) -> cairo.ImageSurface:
    """Render `text` to an ARGB32 cairo surface.

    Output size is decided by `style`:
    - If `style.width_mm` and `style.height_mm` are both set AND `monitor_mm`
      is provided with non-zero values, the surface is sized so its physical
      mm dimensions match — output_px = monitor_px * style.X_mm / monitor_X_mm.
      Same physical size on a 4K laptop and a 1080p external.
    - If mm requested but `monitor_mm` unavailable, fall back to 96 DPI
      (output_px = mm / 25.4 * 96) so something sensible still renders.
    - Otherwise, use `style.width_frac` / `style.height_frac` against
      `monitor_w` / `monitor_h` (legacy battery-osd behaviour).

    Auto-picks the largest font size where the text fits both the width and
    height padding constraints. Draws shadow → outline → fill in that order.
    """
    s = style or DEFAULT_STYLE
    if s.width_mm is not None and s.height_mm is not None:
        if monitor_mm and monitor_mm[0] > 0 and monitor_mm[1] > 0:
            w = max(1, int(monitor_w * s.width_mm / monitor_mm[0]))
            h = max(1, int(monitor_h * s.height_mm / monitor_mm[1]))
        else:
            # No EDID mm info — assume 96 DPI so we still render *something*.
            w = max(1, int(s.width_mm / 25.4 * 96))
            h = max(1, int(s.height_mm / 25.4 * 96))
    else:
        w = int(monitor_w * s.width_frac)
        h = int(monitor_h * s.height_frac)

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
    ctx = cairo.Context(surface)

    if s.use_pango:
        _render_with_pango(ctx, text, w, h, s)
    else:
        _render_with_toy(ctx, text, w, h, s)

    surface.flush()
    return surface


def _render_with_toy(ctx, text, w, h, s):
    """Cairo's toy font API path. Fast, but family matching is fragile —
    use only when the family is well-known to fontconfig (e.g. JetBrainsMono
    Nerd Font, LXGW WenKai Mono)."""
    ctx.select_font_face(s.font_family, s.font_slant, s.font_weight)

    # Linear-grow + back-off — bisection would be cleaner but this is plenty
    # fast and avoids any FP edge cases at the boundary.
    size = 50
    last_good = size
    while size < 1000:
        ctx.set_font_size(size)
        ext = ctx.text_extents(text)
        if ext.width <= w * s.text_pad_w_frac and ext.height <= h * s.text_pad_h_frac:
            last_good = size
            size += 4
        else:
            break
    ctx.set_font_size(last_good)
    ext = ctx.text_extents(text)

    tx = (w - ext.width) / 2 - ext.x_bearing
    ty = (h - ext.height) / 2 - ext.y_bearing

    if s.shadow_rgba is not None:
        off = max(4, int(last_good * s.shadow_offset_frac))
        ctx.set_source_rgba(*s.shadow_rgba)
        ctx.move_to(tx + off, ty + off)
        ctx.show_text(text)

    if s.outline_rgb is not None:
        ow = max(2, int(last_good * s.outline_width_frac))
        ctx.set_source_rgb(*s.outline_rgb)
        ctx.move_to(tx, ty)
        ctx.text_path(text)
        ctx.set_line_width(ow * 2)
        ctx.set_line_join(cairo.LINE_JOIN_ROUND)
        ctx.stroke()

    ctx.set_source_rgba(*s.fill_rgb, s.fill_alpha)
    ctx.move_to(tx, ty)
    ctx.show_text(text)


def _render_with_pango(ctx, text, w, h, s):
    """PangoCairo path. Goes through fontconfig + harfbuzz, matches the
    requested family reliably even with elaborate fallback chains."""
    import gi
    gi.require_version("Pango", "1.0")
    gi.require_version("PangoCairo", "1.0")
    from gi.repository import Pango, PangoCairo

    if s.font_file is not None:
        _fc_app_font_add(s.font_file)

    desc = Pango.FontDescription()
    desc.set_family(s.font_family)
    if s.font_weight == cairo.FONT_WEIGHT_BOLD:
        desc.set_weight(Pango.Weight.BOLD)
    if s.font_slant == cairo.FONT_SLANT_ITALIC:
        desc.set_style(Pango.Style.ITALIC)
    elif s.font_slant == cairo.FONT_SLANT_OBLIQUE:
        desc.set_style(Pango.Style.OBLIQUE)

    def _layout_for(size_px):
        # set_absolute_size takes pango units (1024 = 1 device unit)
        desc.set_absolute_size(size_px * Pango.SCALE)
        layout = PangoCairo.create_layout(ctx)
        layout.set_font_description(desc)
        layout.set_text(text, -1)
        return layout

    # Linear-grow + back-off, mirroring the toy-API loop.
    size = 50
    last_good = size
    while size < 1000:
        layout = _layout_for(size)
        _ink, log = layout.get_pixel_extents()
        if log.width <= w * s.text_pad_w_frac and log.height <= h * s.text_pad_h_frac:
            last_good = size
            size += 4
        else:
            break

    layout = _layout_for(last_good)
    ink, log = layout.get_pixel_extents()
    # Centre using the *ink* extents so visual overhang (descenders, etc.)
    # doesn't bias the placement.
    tx = (w - ink.width) / 2 - ink.x
    ty = (h - ink.height) / 2 - ink.y

    if s.shadow_rgba is not None:
        off = max(4, int(last_good * s.shadow_offset_frac))
        ctx.set_source_rgba(*s.shadow_rgba)
        ctx.move_to(tx + off, ty + off)
        PangoCairo.show_layout(ctx, layout)

    if s.outline_rgb is not None:
        ow = max(2, int(last_good * s.outline_width_frac))
        ctx.set_source_rgb(*s.outline_rgb)
        ctx.move_to(tx, ty)
        PangoCairo.layout_path(ctx, layout)
        ctx.set_line_width(ow * 2)
        ctx.set_line_join(cairo.LINE_JOIN_ROUND)
        ctx.stroke()

    ctx.set_source_rgba(*s.fill_rgb, s.fill_alpha)
    ctx.move_to(tx, ty)
    PangoCairo.show_layout(ctx, layout)


# ---------------------------------------------------------------------------
# X11 plumbing
# ---------------------------------------------------------------------------


def _make_shape_mask(
    surface: cairo.ImageSurface, threshold: int
) -> tuple[bytes, int, int]:
    """Build a 1-bit XShape mask from `surface`'s alpha channel.

    Returns (mask_bytes, width, height). Bit packing: LSBFirst within each
    byte, rows padded to the X server's bitmap scanline unit (32 bits / 4
    bytes). The X11 PutImage protocol assumes every XYBitmap scanline is
    padded to `bitmap_format_scanline_pad` (32 on every modern server); the
    server computes the request's expected byte length from that padding, so
    a byte-only-padded buffer is shorter than the header claims and the
    request fails with BadLength (opcode 72 = PutImage). This only bit when
    the mask width wasn't already a multiple of 32 px — earlier glyph sizes
    happened to land on that boundary and masked the bug.
    """
    iw = surface.get_width()
    ih = surface.get_height()
    stride = surface.get_stride()
    data = bytes(surface.get_data())

    # Pad each row to a 4-byte (32-bit) boundary, matching X11's default
    # bitmap_format_scanline_pad. ((iw + 31) // 32) * 4 == round the
    # byte count up to the next multiple of 4.
    row_bytes = ((iw + 31) // 32) * 4
    mask = bytearray(row_bytes * ih)
    for y in range(ih):
        src_row = y * stride
        dst_row = y * row_bytes
        for x in range(iw):
            # Cairo ARGB32 little-endian byte order is BGRA; alpha is byte 3.
            a = data[src_row + x * 4 + 3]
            if a >= threshold:
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


def get_monitors(d, root) -> list[tuple[int, int, int, int, int, int]]:
    """Enumerate currently-active monitors as (x, y, w_px, h_px, w_mm, h_mm).

    Pixel rect comes from RandR's CRTC list (RandR 1.2+, available on every
    Linux desktop X server since ~2009). mm dimensions come from the first
    output attached to the CRTC (a CRTC drives ≥1 outputs; mirrored outputs
    share a CRTC and we just take the first). w_mm / h_mm are 0 when the
    output's EDID didn't report a physical size, when RandR isn't usable,
    or for the whole-virtual-screen fallback path.

    Mirrored displays naturally produce duplicate (x, y, w, h) tuples;
    we de-dup so we don't render the same OSD twice on top of itself.
    """
    try:
        randr.query_version(d)
        res = root.xrandr_get_screen_resources()
        ts = res.config_timestamp
        seen = set()
        out: list[tuple[int, int, int, int, int, int]] = []
        for crtc in res.crtcs:
            info = d.xrandr_get_crtc_info(crtc, ts)
            if info.width <= 0 or info.height <= 0 or info.mode == 0:
                continue
            rect = (info.x, info.y, info.width, info.height)
            if rect in seen:
                continue
            seen.add(rect)
            mm_w = mm_h = 0
            outputs = list(getattr(info, "outputs", []) or [])
            if outputs:
                try:
                    oi = d.xrandr_get_output_info(outputs[0], ts)
                    mm_w = int(getattr(oi, "mm_width", 0) or 0)
                    mm_h = int(getattr(oi, "mm_height", 0) or 0)
                    # Output mm is reported relative to the panel's natural
                    # orientation. If the CRTC rotates 90°/270°, swap.
                    rot = int(getattr(info, "rotation", 1) or 1)
                    # Rotation bits: 1=0°, 2=90°, 4=180°, 8=270°
                    if rot in (2, 8):
                        mm_w, mm_h = mm_h, mm_w
                except Exception:
                    pass
            out.append(rect + (mm_w, mm_h))
        if out:
            return out
    except Exception:
        pass
    s = d.screen()
    return [(0, 0, s.width_in_pixels, s.height_in_pixels, 0, 0)]


def _anchor_x(monitor_w: int, win_w: int, style: OSDStyle) -> int:
    """Compute the x-offset within a monitor for the OSD window."""
    if style.anchor_x == "left":
        base = 0
    elif style.anchor_x == "right":
        base = monitor_w - win_w
    else:
        base = (monitor_w - win_w) // 2
    return base + int(monitor_w * style.offset_x_frac)


def _anchor_y(monitor_h: int, win_h: int, style: OSDStyle) -> int:
    """Compute the y-offset within a monitor for the OSD window."""
    if style.anchor_y == "top":
        base = 0
    elif style.anchor_y == "bottom":
        base = monitor_h - win_h
    else:
        base = (monitor_h - win_h) // 2
    return base + int(monitor_h * style.offset_y_frac)


def _find_argb_visual(screen):
    """Find a 32-bit TrueColor visual with alpha, or return None."""
    for depth_info in screen.allowed_depths:
        if depth_info.depth != 32:
            continue
        for visual in depth_info.visuals:
            if visual.visual_class == X.TrueColor:
                return visual, depth_info.depth
    return None, None


def _create_osd_window(d, screen, root, rect, surface, style: OSDStyle):
    """Create one OSD window anchored (per style) on `rect`, showing
    `surface`. Returns the window so it can be destroyed later.

    When a 32-bit ARGB visual is available (compositor running), uses it
    for true alpha transparency — smooth edges, semi-transparent fills,
    real drop shadows. Falls back to XShape clipping on 24-bit servers.
    """
    mx, my, mw, mh = rect[:4]
    iw = surface.get_width()
    ih = surface.get_height()
    wx = mx + _anchor_x(mw, iw, style)
    wy = my + _anchor_y(mh, ih, style)

    argb_visual, argb_depth = _find_argb_visual(screen)
    use_argb = argb_visual is not None

    if use_argb:
        colormap = root.create_colormap(argb_visual.visual_id, X.AllocNone)
        win = root.create_window(
            wx, wy, iw, ih, 0,
            argb_depth,
            X.InputOutput,
            argb_visual.visual_id,
            border_pixel=0,
            background_pixel=0,
            colormap=colormap,
            override_redirect=1,
            event_mask=X.ExposureMask,
        )
    else:
        win = root.create_window(
            wx, wy, iw, ih, 0,
            screen.root_depth,
            X.InputOutput,
            X.CopyFromParent,
            background_pixel=screen.black_pixel,
            override_redirect=1,
            event_mask=X.ExposureMask,
        )

    win.set_wm_name("osd")
    win.set_wm_class("osd", "osd")

    if not use_argb:
        # Fallback: XShape mask for hard-clipped transparency.
        mask_bytes, smw, smh = _make_shape_mask(surface, style.alpha_threshold)
        pixmap = win.create_pixmap(smw, smh, 1)
        pgc = pixmap.create_gc(foreground=1, background=0)
        _chunked_put_image(pixmap, pgc, X.XYBitmap, 1, smw, smh, mask_bytes,
                           ((smw + 31) // 32) * 4)
        win.shape_mask(shape.SO.Set, shape.SK.Bounding, 0, 0, pixmap)
        pgc.free()
        pixmap.free()

    win.map()

    # Push pixel data. Cairo ARGB32 little-endian is BGRA in memory, which
    # matches X11's 32-bit ZPixmap format. With a 32-bit visual the alpha
    # channel is composited by picom; at 24-bit depth it's ignored and the
    # XShape mask decides visibility.
    depth = argb_depth if use_argb else screen.root_depth
    gc = win.create_gc()
    _chunked_put_image(win, gc, X.ZPixmap, depth, iw, ih,
                       bytes(surface.get_data()), iw * 4)
    gc.free()
    return win


def display_on_all_monitors(
    text: str, duration: float, style: OSDStyle | None = None
) -> None:
    """Show the OSD on every active monitor for `duration` seconds.

    Each monitor gets a window sized to its own dimensions when
    `style.per_monitor_size` is True (default), so text scales naturally
    on a 4K laptop and a 1080p external alike. Otherwise one render is
    used at the first monitor's size and re-placed on every monitor.
    """
    s = style or DEFAULT_STYLE
    d = display.Display()
    screen = d.screen()
    root = screen.root

    monitors = get_monitors(d, root)
    if not monitors:
        return

    if s.per_monitor_size:
        renders = [
            (
                rect,
                render_surface(text, rect[2], rect[3], s, monitor_mm=(rect[4], rect[5])),
            )
            for rect in monitors
        ]
    else:
        # Use the first monitor's size for everyone (e.g. fixed-banner OSDs).
        ref_rect = monitors[0]
        ref_w, ref_h = ref_rect[2], ref_rect[3]
        ref_mm = (ref_rect[4], ref_rect[5])
        shared = render_surface(text, ref_w, ref_h, s, monitor_mm=ref_mm)
        renders = [(rect, shared) for rect in monitors]

    windows = []
    for rect, surface in renders:
        try:
            windows.append(_create_osd_window(d, screen, root, rect, surface, s))
        except Exception as e:
            sys.stderr.write(f"osd: failed on monitor {rect}: {e}\n")
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


__all__ = [
    "OSDStyle",
    "DEFAULT_STYLE",
    "render_surface",
    "get_monitors",
    "display_on_all_monitors",
]


# ---------------------------------------------------------------------------
# Application-private fontconfig registration
# ---------------------------------------------------------------------------


_fc_app_font_added: set[str] = set()


def _fc_app_font_add(path: str) -> None:
    """Register `path` with the current fontconfig session as an
    application-private font, so Pango sees it via its default fontmap.

    Why bother: PangoCairo.FontMap.list_families() drops fonts whose
    `en` language coverage is incomplete (e.g. JejuHallasan is missing
    20 ASCII glyphs). fontconfig still resolves them via fc-match, but
    Pango's matcher won't pick them. FcConfigAppFontAddFile bypasses
    the global fontset's lang-coverage filter — application fonts are
    visible to Pango's matcher regardless.

    Implemented via ctypes to avoid pulling in another Python binding.
    Idempotent (fontconfig returns true even on duplicate adds, and we
    short-circuit to skip the syscall).
    """
    if path in _fc_app_font_added:
        return
    import ctypes
    import ctypes.util
    libname = ctypes.util.find_library("fontconfig")
    if libname is None:
        sys.stderr.write("osd: libfontconfig not found; skipping app-font add\n")
        return
    fc = ctypes.CDLL(libname)
    fc.FcConfigGetCurrent.restype = ctypes.c_void_p
    fc.FcConfigAppFontAddFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    fc.FcConfigAppFontAddFile.restype = ctypes.c_int
    config = fc.FcConfigGetCurrent()
    if not fc.FcConfigAppFontAddFile(config, path.encode("utf-8")):
        sys.stderr.write(f"osd: FcConfigAppFontAddFile failed for {path}\n")
        return
    _fc_app_font_added.add(path)


# ---------------------------------------------------------------------------
