#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import types
import unittest


def load_module():
    xlib = types.ModuleType("Xlib")
    xlib.X = types.SimpleNamespace(Above=1, Unsorted=0)
    xlib.display = types.SimpleNamespace()
    xlib.error = types.SimpleNamespace(BadWindow=RuntimeError)
    xlib_ext = types.ModuleType("Xlib.ext")
    xlib_ext.shape = types.SimpleNamespace(
        SO=types.SimpleNamespace(Set=0),
        SK=types.SimpleNamespace(Input=2),
    )
    sys.modules["Xlib"] = xlib
    sys.modules["Xlib.ext"] = xlib_ext

    path = pathlib.Path(__file__).with_name("bin") / "osd-click-through.py"
    spec = importlib.util.spec_from_file_location("osd_click_through", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


osd_click_through = load_module()


class FakeWindow:
    def __init__(self, title=None, vanished=False, rectangles=(), wm_class=None):
        self.title = title
        self.vanished = vanished
        self.rectangles = rectangles
        self.wm_class = wm_class
        self.shape_args = None
        self.configure_args = None

    def get_wm_name(self):
        if self.vanished:
            raise RuntimeError
        return self.title

    def shape_rectangles(self, *args):
        self.shape_args = args

    def shape_get_rectangles(self, _kind):
        return types.SimpleNamespace(rectangles=self.rectangles)

    def set_wm_class(self, resource_name, resource_class):
        self.wm_class = (resource_name, resource_class)

    def get_wm_class(self):
        return self.wm_class

    def configure(self, **kwargs):
        self.configure_args = kwargs


class ClickThroughTest(unittest.TestCase):
    def test_sets_empty_input_region(self):
        window = FakeWindow()

        osd_click_through.make_click_through(window)

        self.assertEqual(window.shape_args, (0, 2, 0, 0, 0, []))

    def test_configures_osd_class_input_and_stacking(self):
        window = FakeWindow()

        osd_click_through.configure_osd_window(window, "vol-osd")

        self.assertEqual(window.wm_class, ("vol-osd", "osd"))
        self.assertEqual(window.shape_args, (0, 2, 0, 0, 0, []))
        self.assertEqual(window.configure_args, {"stack_mode": 1})

    def test_matches_exact_title_and_ignores_vanished_windows(self):
        target = FakeWindow("vol-osd")
        root = types.SimpleNamespace(
            query_tree=lambda: types.SimpleNamespace(
                children=[
                    FakeWindow("other"),
                    FakeWindow(vanished=True),
                    target,
                ]
            )
        )

        self.assertEqual(
            osd_click_through.matching_windows(root, "vol-osd"),
            [target],
        )

    def test_checks_input_region(self):
        self.assertTrue(
            osd_click_through.input_region_is_empty(FakeWindow(rectangles=[]))
        )
        self.assertFalse(
            osd_click_through.input_region_is_empty(FakeWindow(rectangles=[object()]))
        )

    def test_checks_osd_class(self):
        self.assertTrue(
            osd_click_through.has_osd_class(
                FakeWindow(wm_class=("vol-osd", "osd"))
            )
        )
        self.assertFalse(
            osd_click_through.has_osd_class(
                FakeWindow(wm_class=("dzen2", "Dzen2"))
            )
        )


if __name__ == "__main__":
    unittest.main()
