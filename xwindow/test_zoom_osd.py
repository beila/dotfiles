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
    xlib.X = types.SimpleNamespace(
        NONE=0,
        CreateNotify=16,
        DestroyNotify=17,
        MapNotify=19,
        PropertyNotify=28,
        NoEventMask=0,
        PropertyChangeMask=1 << 22,
    )
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
        "_NET_WM_NAME": 12,
        "UTF8_STRING": 13,
    }

    def get_atom(self, name, only_if_exists=False):
        return self.atoms.get(name, 0)

    def sync(self):
        pass


class FakeWindow:
    def __init__(self, wm_class=("zoom", "zoom"), window_types=(11,),
                 title="", window_id=42):
        self.wm_class = wm_class
        self.window_types = window_types
        self.title = title
        self.id = window_id
        self.event_mask = None

    def get_wm_class(self):
        return self.wm_class

    def get_full_property(self, atom, property_type):
        del property_type
        if atom == FakeDisplay.atoms["_NET_WM_NAME"]:
            value = self.title.encode() if self.title else b""
            return types.SimpleNamespace(value=value)
        if atom != FakeDisplay.atoms["_NET_WM_WINDOW_TYPE"]:
            return None
        return types.SimpleNamespace(value=self.window_types)

    def change_attributes(self, event_mask):
        self.event_mask = event_mask


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


class ZoomWindowWatcherTests(unittest.TestCase):
    def setUp(self):
        self.display = FakeDisplay()
        self.window_re = re.compile(zoom_osd.DEFAULT_WINDOW_REGEX)
        self.pending = set()
        self.matches = []

    def handle(self, event_type, window):
        event = types.SimpleNamespace(type=event_type, window=window)
        zoom_osd._handle_window_event(
            self.display,
            event,
            self.window_re,
            self.pending,
            self.matches.append,
        )

    def test_hidden_workspace_match_does_not_require_map(self):
        window = FakeWindow()
        self.handle(zoom_osd.X.CreateNotify, window)
        self.assertEqual(self.pending, {window.id})
        self.assertEqual(self.matches, [])

        window.title = "Zoom Workplace"
        self.handle(zoom_osd.X.PropertyNotify, window)

        self.assertEqual(self.pending, set())
        self.assertEqual(self.matches, ["Zoom Workplace"])
        self.assertEqual(window.event_mask, zoom_osd.X.NoEventMask)

    def test_later_map_cannot_retrigger_property_match(self):
        window = FakeWindow(title="Zoom Workplace")
        self.handle(zoom_osd.X.CreateNotify, window)
        self.handle(zoom_osd.X.MapNotify, window)

        self.assertEqual(self.matches, ["Zoom Workplace"])

    def test_first_nonmatching_map_stops_tracking(self):
        window = FakeWindow(title="Zoom Workplace", window_types=(12,))
        self.handle(zoom_osd.X.CreateNotify, window)
        self.handle(zoom_osd.X.MapNotify, window)

        self.assertEqual(self.pending, set())
        self.assertEqual(self.matches, [])
        self.assertEqual(window.event_mask, zoom_osd.X.NoEventMask)


if __name__ == "__main__":
    unittest.main()
