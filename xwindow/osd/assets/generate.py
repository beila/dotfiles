#!/usr/bin/env python3
"""Regenerate the OSD glyph SVG assets from their source fonts.

The OSDs no longer render text with a font at runtime — they paint a static,
pre-outlined **vector** SVG (see osd.render_surface's image path). This script
is how those SVGs are produced: it lays out the glyph with Pango at a
reference size, converts it to vector paths on a cairo SVGSurface
(PangoCairo.layout_path → fill), and writes the result. Because the glyph is
stored as outlines, displaying it needs no font, no fontconfig, and no Pango —
only librsvg to rasterize the paths crisply at any per-monitor pixel size.

Run it only when changing a glyph or its face; the generated .svg files are
committed and are the runtime source of truth. It is NOT run at daemon start
or in the Nix build.

    python3 generate.py \
        --font /path/UnifrakturCook.ttf --family UnifrakturCook --weight bold \
        --text MW --color '#B40000' --out mw.svg

Deps: pycairo, PyGObject (Pango/PangoCairo), libfontconfig. Same environment
as the old runtime render path; here it is a one-off authoring tool.
"""

from __future__ import annotations

import argparse
import ctypes
import ctypes.util
import sys

import cairo
import gi

gi.require_version("Pango", "1.0")
gi.require_version("PangoCairo", "1.0")
from gi.repository import Pango, PangoCairo  # noqa: E402

# Reference layout size in px. Only the *ratio* of the resulting paths matters
# — the SVG is vector and is scaled to each monitor at display time — but a
# large reference keeps the emitted path coordinates precise.
_REFERENCE_PX = 400
_PAD = 8


def _app_font_add(path: str) -> None:
    lib = ctypes.util.find_library("fontconfig")
    if lib is None:
        sys.exit("libfontconfig not found")
    fc = ctypes.CDLL(lib)
    fc.FcConfigGetCurrent.restype = ctypes.c_void_p
    fc.FcConfigAppFontAddFile.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
    fc.FcConfigAppFontAddFile.restype = ctypes.c_int
    if not fc.FcConfigAppFontAddFile(fc.FcConfigGetCurrent(), path.encode()):
        sys.exit(f"FcConfigAppFontAddFile failed for {path}")


def _hex_to_rgb(h: str) -> tuple[float, float, float]:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255 for i in (0, 2, 4))


def _describe(family: str, weight: str) -> Pango.FontDescription:
    desc = Pango.FontDescription()
    desc.set_family(family)
    if weight == "bold":
        desc.set_weight(Pango.Weight.BOLD)
    desc.set_absolute_size(_REFERENCE_PX * Pango.SCALE)
    return desc


def generate(font: str, family: str, weight: str, text: str, color: str,
             out: str) -> None:
    _app_font_add(font)
    r, g, b = _hex_to_rgb(color)

    # Measure ink extents so the SVG viewBox hugs the glyph tightly.
    tmp = cairo.ImageSurface(cairo.FORMAT_ARGB32, 8, 8)
    mctx = cairo.Context(tmp)
    desc = _describe(family, weight)
    layout = PangoCairo.create_layout(mctx)
    layout.set_font_description(desc)
    layout.set_text(text, -1)
    ink, _log = layout.get_pixel_extents()
    w, h = ink.width + 2 * _PAD, ink.height + 2 * _PAD

    # Prove the glyph resolved to the requested family, not a fallback — a
    # fallback here would silently bake the wrong outlines into the asset.
    it = layout.get_iter()
    while True:
        run = it.get_run_readonly()
        if run is not None:
            fam = run.item.analysis.font.describe().get_family()
            if fam != family:
                sys.exit(f"glyph fell back to {fam!r}, not {family!r}")
        if not it.next_run():
            break

    svg = cairo.SVGSurface(out, w, h)
    ctx = cairo.Context(svg)
    layout2 = PangoCairo.create_layout(ctx)
    layout2.set_font_description(desc)
    layout2.set_text(text, -1)
    ctx.move_to(-ink.x + _PAD, -ink.y + _PAD)
    PangoCairo.layout_path(ctx, layout2)   # glyph → vector outline
    ctx.set_source_rgb(r, g, b)
    ctx.fill()
    svg.finish()
    print(f"wrote {out}  ({w}x{h}, family={family}, color={color})")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--font", required=True)
    p.add_argument("--family", required=True)
    p.add_argument("--weight", default="normal", choices=["normal", "bold"])
    p.add_argument("--text", required=True)
    p.add_argument("--color", required=True, help="#RRGGBB")
    p.add_argument("--out", required=True)
    a = p.parse_args()
    generate(a.font, a.family, a.weight, a.text, a.color, a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
