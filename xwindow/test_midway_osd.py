#!/usr/bin/env python3
"""Regression tests for the Midway-invalid OSD.

Split into two tiers:

- Pure-logic tests (parser delegation, valid↔invalid transitions,
  idempotency) run against `midway-osd.py` with the real `osd` library. They
  never touch X or credentials — `midway_is_invalid` is driven with a fake
  subprocess runner.
- Geometry / style / font tests exercise the real `osd` library math so the
  MW box's physical height, top alignment, fixed gap, no-overlap, and
  on-screen placement are checked on concrete 1920×1200 and 4K/mixed-DPI
  monitor data, and the decorative font is proven to render M/W rather than a
  generic fallback.

The font-resolution test needs Pango/PangoCairo typelibs (GI_TYPELIB_PATH) and
the JejuHallasan ttf (MIDWAY_OSD_FONT_FILE); it skips cleanly when either is
unavailable so the rest of the suite still runs.
"""

import importlib.util
import os
import pathlib
import unittest


def load_module():
    path = pathlib.Path(__file__).with_name("bin") / "midway-osd.py"
    spec = importlib.util.spec_from_file_location("midway_osd", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


try:
    import cairo  # noqa: F401  -- real cairo required for the osd library
    import osd  # noqa: F401
    midway_osd = load_module()
    _OSD_AVAILABLE = True
    _OSD_IMPORT_ERROR = None
except Exception as e:  # pragma: no cover - env without cairo/osd
    _OSD_AVAILABLE = False
    _OSD_IMPORT_ERROR = e


@unittest.skipUnless(_OSD_AVAILABLE, f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
class StatusParserTest(unittest.TestCase):
    """midway_is_invalid delegates entirely to `midway-genmon --status`."""

    def _runner(self, stdout, returncode=0, raises=None):
        import subprocess

        def run(cmd, **_kwargs):
            # Confirms the daemon calls the shared parser in --status mode.
            self.assertEqual(cmd[-1], "--status")
            if raises is not None:
                raise raises
            return subprocess.CompletedProcess(cmd, returncode, stdout=stdout)

        return run

    def test_valid_word_is_valid(self):
        self.assertFalse(midway_osd.midway_is_invalid(self._runner("valid\n")))

    def test_invalid_word_is_invalid(self):
        self.assertTrue(midway_osd.midway_is_invalid(self._runner("invalid\n")))

    def test_expired_missing_malformed_unreadable_all_invalid(self):
        # The genmon collapses every non-future-expiry state to `invalid`;
        # the daemon just trusts that single word.
        for word in ("invalid\n", "invalid", "  invalid  \n"):
            self.assertTrue(midway_osd.midway_is_invalid(self._runner(word)))

    def test_unexpected_output_is_treated_as_invalid(self):
        # Fail-safe: anything that isn't a clean `valid` shows the reminder.
        self.assertTrue(midway_osd.midway_is_invalid(self._runner("")))
        self.assertTrue(midway_osd.midway_is_invalid(self._runner("wat\n")))

    def test_missing_binary_is_invalid_not_a_crash(self):
        self.assertTrue(
            midway_osd.midway_is_invalid(self._runner("", raises=OSError("no genmon")))
        )


@unittest.skipUnless(_OSD_AVAILABLE, f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
class MidwayIndicatorTest(unittest.TestCase):
    def _indicator(self):
        events = []
        ind = midway_osd.MidwayIndicator(
            lambda: events.append("show"),
            lambda: events.append("hide"),
        )
        return ind, events

    def test_startup_invalid_shows_once_and_does_not_duplicate(self):
        ind, events = self._indicator()
        ind.observe(True)   # startup already invalid → show once
        ind.observe(True)   # repeated invalid → no duplicate window
        ind.observe(True)
        self.assertEqual(events, ["show"])

    def test_startup_valid_shows_nothing(self):
        ind, events = self._indicator()
        ind.observe(False)
        ind.observe(False)
        self.assertEqual(events, [])

    def test_valid_to_invalid_and_back_shows_and_hides_exactly_once(self):
        ind, events = self._indicator()
        ind.observe(False)  # valid: nothing
        ind.observe(True)   # → invalid: show
        ind.observe(True)   # idempotent
        ind.observe(False)  # → valid: hide
        ind.observe(False)  # idempotent
        ind.observe(True)   # → invalid again: show
        self.assertEqual(events, ["show", "hide", "show"])

    def test_expiry_crossing_without_file_change_flips_to_invalid(self):
        # Two consecutive polls of the SAME cookie file: still-valid, then the
        # clock has crossed expiry (file unchanged). The indicator must show.
        ind, events = self._indicator()
        ind.observe(False)  # first poll: valid
        ind.observe(True)   # later poll: now past expiry, no file change
        self.assertEqual(events, ["show"])


@unittest.skipUnless(_OSD_AVAILABLE, f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
class StyleTest(unittest.TestCase):
    def test_text_is_MW(self):
        self.assertEqual(midway_osd.TEXT, "MW")

    def test_fill_is_pure_red_at_half_alpha(self):
        s = midway_osd.STYLE
        self.assertEqual(s.fill_rgb, (1.0, 0.0, 0.0))
        self.assertEqual(s.fill_alpha, 0.5)

    def test_no_outline_or_shadow(self):
        s = midway_osd.STYLE
        self.assertIsNone(s.outline_rgb)
        self.assertIsNone(s.shadow_rgba)

    def test_uses_decorative_font_via_pango_appfont(self):
        s = midway_osd.STYLE
        self.assertEqual(s.font_family, "JejuHallasan")
        self.assertTrue(s.use_pango)

    def test_same_physical_height_as_hangul_slot(self):
        self.assertEqual(midway_osd.STYLE.height_mm, osd.HANGUL_SLOT_HEIGHT_MM)

    def test_wider_than_one_glyph_hangul_box(self):
        # Two Latin letters need more physical width than the 60 mm 한 box.
        self.assertGreater(midway_osd.STYLE.width_mm, osd.HANGUL_SLOT_WIDTH_MM)


# --- Geometry helpers -------------------------------------------------------

# Monitor tuples: (x, y, w_px, h_px, w_mm, h_mm).
MON_1920x1200 = (0, 0, 1920, 1200, 518, 324)         # 24" 16:10, ~94 DPI
MON_4K = (0, 0, 3840, 2160, 600, 340)                # 27.5" 4K, ~163 DPI


def _hangul_style():
    """The exact Hangul OSD style, rebuilt from the shared slot constants."""
    return osd.OSDStyle(
        width_mm=osd.HANGUL_SLOT_WIDTH_MM,
        height_mm=osd.HANGUL_SLOT_HEIGHT_MM,
        anchor_x="right",
        offset_x_frac=osd.HANGUL_SLOT_OFFSET_X_FRAC,
        anchor_y="top",
        offset_y_frac=osd.HANGUL_SLOT_OFFSET_Y_FRAC,
        per_monitor_size=True,
    )


def _box(style, mon):
    """Return the on-monitor pixel rect (x, y, w, h) of `style` on `mon`,
    using the real osd geometry (surface size + anchor math)."""
    _mx, _my, mw, mh, mm_w, mm_h = mon
    surf = osd.render_surface(midway_osd.TEXT, mw, mh, style, monitor_mm=(mm_w, mm_h))
    iw, ih = surf.get_width(), surf.get_height()
    x = osd._anchor_x(mw, iw, style, mm_w)
    y = osd._anchor_y(mh, ih, style, mm_h)
    return x, y, iw, ih


@unittest.skipUnless(_OSD_AVAILABLE, f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
class GeometryTest(unittest.TestCase):
    def _pair(self, mon):
        hangul = _box(_hangul_style(), mon)
        mw = _box(midway_osd.STYLE, mon)
        return hangul, mw

    def _mm_px(self, mm, mon_px, mon_mm):
        return mm * mon_px / mon_mm

    def test_same_physical_height_both_monitors(self):
        for mon in (MON_1920x1200, MON_4K):
            hh = _box(_hangul_style(), mon)[3]
            mh = _box(midway_osd.STYLE, mon)[3]
            # Both boxes are 70 mm tall → identical pixel height on a monitor.
            self.assertEqual(hh, mh, f"height mismatch on {mon}")
            # And that height equals 70 mm in that monitor's px (±1 px round).
            want = self._mm_px(70.0, mon[3], mon[5])
            self.assertLessEqual(abs(mh - want), 1, f"height≠70mm on {mon}")

    def test_top_edges_aligned(self):
        for mon in (MON_1920x1200, MON_4K):
            (_hx, hy, _hw, _hh), (_mx, my, _mw, _mh) = self._pair(mon)
            self.assertEqual(hy, my, f"top edge misaligned on {mon}")

    def test_fixed_physical_gap_no_overlap(self):
        for mon in (MON_1920x1200, MON_4K):
            (hx, _hy, _hw, _hh), (mx, _my, mwid, _mh) = self._pair(mon)
            mw_right = mx + mwid
            gap_px = hx - mw_right
            want_gap = self._mm_px(midway_osd.GAP_MM, mon[2], mon[4])
            # Gap is positive (no overlap) and matches GAP_MM physically.
            self.assertGreater(gap_px, 0, f"MW overlaps 한 on {mon}")
            self.assertLessEqual(
                abs(gap_px - want_gap), 2, f"gap≠{midway_osd.GAP_MM}mm on {mon}"
            )

    def test_fully_on_screen(self):
        for mon in (MON_1920x1200, MON_4K):
            (_hx, _hy, _hw, _hh), (mx, my, mwid, mh) = self._pair(mon)
            self.assertGreaterEqual(mx, 0, f"MW left off-screen on {mon}")
            self.assertGreaterEqual(my, 0, f"MW top off-screen on {mon}")
            self.assertLessEqual(mx + mwid, mon[2], f"MW right off-screen on {mon}")
            self.assertLessEqual(my + mh, mon[3], f"MW bottom off-screen on {mon}")

    def test_gap_is_dpi_independent(self):
        # The physical gap must be the same mm on both DPIs (the whole point
        # of deriving it from mm, not a fixed pixel or fraction).
        (hx1, *_), (mx1, _y1, w1, _h1) = self._pair(MON_1920x1200)
        (hx2, *_), (mx2, _y2, w2, _h2) = self._pair(MON_4K)
        gap1_mm = (hx1 - (mx1 + w1)) / (MON_1920x1200[2] / MON_1920x1200[4])
        gap2_mm = (hx2 - (mx2 + w2)) / (MON_4K[2] / MON_4K[4])
        self.assertLessEqual(abs(gap1_mm - gap2_mm), 0.5)


@unittest.skipUnless(_OSD_AVAILABLE, f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
class SiblingOffsetTest(unittest.TestCase):
    def test_offset_is_negative_reference_width_plus_gap(self):
        ref = _hangul_style()
        self.assertEqual(
            osd.sibling_offset_mm(ref, 6.0),
            -(osd.HANGUL_SLOT_WIDTH_MM + 6.0),
        )

    def test_requires_mm_reference(self):
        with self.assertRaises(ValueError):
            osd.sibling_offset_mm(osd.OSDStyle(), 6.0)


@unittest.skipUnless(_OSD_AVAILABLE, f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
class OfflineRenderTest(unittest.TestCase):
    def test_render_png_writes_a_valid_png_without_credentials(self):
        import tempfile

        with tempfile.TemporaryDirectory() as d:
            out = os.path.join(d, "mw.png")
            # No DISPLAY, no cookie file — offline render must still succeed.
            rc = midway_osd._render_png(out, "1920x1200")
            self.assertEqual(rc, 0)
            self.assertTrue(os.path.exists(out))
            with open(out, "rb") as f:
                self.assertEqual(f.read(8), b"\x89PNG\r\n\x1a\n")

    def test_render_png_rejects_bad_screen(self):
        self.assertEqual(midway_osd._render_png("/dev/null", "nonsense"), 2)


class FontResolutionTest(unittest.TestCase):
    """Prove M and W are rendered by JejuHallasan, not a generic fallback."""

    def setUp(self):
        if not _OSD_AVAILABLE:
            self.skipTest(f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
        self.ttf = os.environ.get("MIDWAY_OSD_FONT_FILE")
        if not self.ttf or not os.path.exists(self.ttf):
            self.skipTest("MIDWAY_OSD_FONT_FILE not set / missing")
        try:
            import gi

            gi.require_version("Pango", "1.0")
            gi.require_version("PangoCairo", "1.0")
            from gi.repository import Pango, PangoCairo  # noqa: F401
        except Exception as e:
            self.skipTest(f"Pango/PangoCairo unavailable: {e}")

    def test_MW_glyphs_come_from_jejuhallasan(self):
        import gi

        gi.require_version("Pango", "1.0")
        gi.require_version("PangoCairo", "1.0")
        from gi.repository import Pango, PangoCairo

        osd._fc_app_font_add(self.ttf)
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 800, 400)
        ctx = cairo.Context(surface)
        desc = Pango.FontDescription()
        desc.set_family("JejuHallasan")
        desc.set_absolute_size(200 * Pango.SCALE)
        layout = PangoCairo.create_layout(ctx)
        layout.set_font_description(desc)
        layout.set_text("MW", -1)

        it = layout.get_iter()
        families = []
        while True:
            run = it.get_run_readonly()
            if run is not None:
                families.append(run.item.analysis.font.describe().get_family())
            if not it.next_run():
                break
        self.assertTrue(families, "no glyph runs produced for MW")
        for fam in families:
            self.assertEqual(
                fam, "JejuHallasan", f"MW fell back to {fam!r}, not JejuHallasan"
            )


@unittest.skipUnless(_OSD_AVAILABLE, f"osd/cairo unavailable: {_OSD_IMPORT_ERROR}")
class ClickThroughTest(unittest.TestCase):
    """The MW window is click-through via the shared osd empty-Input region.

    midway-osd shows through display_on_all_monitors → _create_osd_window →
    _make_click_through, the exact same path every osd-library window uses.
    Assert that path installs an empty XShape Input region.
    """

    def test_shared_path_sets_empty_input_region(self):
        from Xlib import X
        from Xlib.ext import shape

        class FakeWindow:
            def __init__(self):
                self.args = None

            def shape_rectangles(self, *args):
                self.args = args

        win = FakeWindow()
        osd._make_click_through(win)
        self.assertEqual(
            win.args,
            (shape.SO.Set, shape.SK.Input, X.Unsorted, 0, 0, []),
        )


if __name__ == "__main__":
    unittest.main()
