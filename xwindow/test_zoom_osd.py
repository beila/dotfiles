#!/usr/bin/env python3
"""Regression tests for Zoom X-window matching."""

import importlib.util
import pathlib
import re
import sys
import types
import unittest


def load_module():
    osd = types.ModuleType("osd")
    osd.OSDStyle = lambda **_kwargs: object()
    osd.display_on_all_monitors = lambda *_args, **_kwargs: None
    osd.render_surface = lambda *_args, **_kwargs: None
    sys.modules["osd"] = osd

    xlib = types.ModuleType("Xlib")
    xlib.X = types.SimpleNamespace(NONE=0)
    xlib.Xatom = types.SimpleNamespace(ATOM=4, WM_NAME=39, STRING=31)
    xlib.display = types.SimpleNamespace()
    sys.modules["Xlib"] = xlib

    path = pathlib.Path(__file__).with_name("bin") / "zoom-osd.py"
    spec = importlib.util.spec_from_file_location("zoom_osd", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


zoom_osd = load_module()


class FakeDisplay:
    atoms = {
        "_NET_WM_WINDOW_TYPE": 10,
        "_KDE_NET_WM_WINDOW_TYPE_OVERRIDE": 11,
    }

    def get_atom(self, name, only_if_exists=False):
        return self.atoms.get(name, 0)


class FakeWindow:
    def __init__(self, wm_class=("zoom", "zoom"), window_types=(11,)):
        self.wm_class = wm_class
        self.window_types = window_types

    def get_wm_class(self):
        return self.wm_class

    def get_full_property(self, atom, property_type):
        del property_type
        if atom != FakeDisplay.atoms["_NET_WM_WINDOW_TYPE"]:
            return None
        return types.SimpleNamespace(value=self.window_types)


class ZoomPopupMatcherTests(unittest.TestCase):
    def setUp(self):
        self.display = FakeDisplay()
        self.legacy_re = re.compile(zoom_osd.DEFAULT_WINDOW_REGEX)

    def match(self, title, window=None):
        return zoom_osd._is_zoom_popup(
            self.display,
            window or FakeWindow(),
            title,
            self.legacy_re,
        )

    def test_matches_legacy_reminder_title(self):
        self.assertTrue(self.match("zoom_linux_float_message_reminder"))

    def test_matches_generic_titled_kde_override_zoom_window(self):
        self.assertTrue(self.match("Zoom Workplace"))

    def test_rejects_ordinary_zoom_main_window(self):
        self.assertFalse(
            self.match("Zoom Workplace", FakeWindow(window_types=(12,)))
        )

    def test_rejects_override_window_from_another_application(self):
        self.assertFalse(
            self.match(
                "Zoom Workplace",
                FakeWindow(wm_class=("other", "Other")),
            )
        )

    def test_rejects_other_generic_titled_zoom_windows(self):
        self.assertFalse(self.match("Settings"))

    def test_property_race_does_not_break_watcher(self):
        class VanishedWindow:
            def get_wm_class(self):
                raise RuntimeError("window disappeared")

        self.assertFalse(self.match("Zoom Workplace", VanishedWindow()))


if __name__ == "__main__":
    unittest.main()
