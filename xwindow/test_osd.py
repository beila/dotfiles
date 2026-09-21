#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import types
import unittest


def load_module():
    cairo = types.ModuleType("cairo")
    cairo.FONT_SLANT_NORMAL = 0
    cairo.FONT_WEIGHT_BOLD = 0
    sys.modules["cairo"] = cairo

    xlib = types.ModuleType("Xlib")
    xlib.X = types.ModuleType("Xlib.X")
    xlib.display = types.ModuleType("Xlib.display")
    xlib.display.Display = lambda: None
    sys.modules["Xlib"] = xlib
    sys.modules["Xlib.X"] = xlib.X
    sys.modules["Xlib.display"] = xlib.display

    ext = types.ModuleType("Xlib.ext")
    randr = types.ModuleType("Xlib.ext.randr")
    randr.RRScreenChangeNotifyMask = 1
    randr.RRCrtcChangeNotifyMask = 2
    randr.RROutputChangeNotifyMask = 4
    randr.query_version = lambda _display: None
    shape = types.ModuleType("Xlib.ext.shape")
    ext.randr = randr
    ext.shape = shape
    sys.modules["Xlib.ext"] = ext
    sys.modules["Xlib.ext.randr"] = randr
    sys.modules["Xlib.ext.shape"] = shape

    path = pathlib.Path(__file__).with_name("osd") / "src" / "osd" / "__init__.py"
    spec = importlib.util.spec_from_file_location("osd_under_test", path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


osd = load_module()


class FakeWindow:
    def __init__(self, rect):
        self.rect = rect
        self.destroyed = False
        self.unmapped = False

    def unmap(self):
        self.unmapped = True

    def destroy(self):
        self.destroyed = True


class FakeRoot:
    def __init__(self):
        self.randr_mask = None

    def xrandr_select_input(self, mask):
        self.randr_mask = mask


class FakeDisplay:
    def __init__(self):
        self.root = FakeRoot()
        self.events = [object()]
        self.closed = False

    def screen(self):
        return types.SimpleNamespace(root=self.root)

    def sync(self):
        pass

    def close(self):
        self.closed = True

    def fileno(self):
        return 7

    def pending_events(self):
        return len(self.events)

    def next_event(self):
        return self.events.pop(0)


class MonitorTopologyTest(unittest.TestCase):
    def test_default_randr_event_rebuilds_windows_for_current_monitors(self):
        display = FakeDisplay()
        monitor_sets = iter(
            [
                [(0, 0, 1920, 1080, 510, 290)],
                [(1920, 0, 2560, 1440, 600, 340)],
            ]
        )
        created = []
        select_results = iter(
            [
                ([display.fileno()], [], []),
                ([], [], []),
            ]
        )

        originals = (
            osd.display.Display,
            osd.randr.query_version,
            osd.get_monitors,
            osd.render_surface,
            osd._create_osd_window,
            osd.select.select,
        )
        osd.display.Display = lambda: display
        osd.randr.query_version = lambda _display: None
        osd.get_monitors = lambda _display, _root: next(monitor_sets)
        osd.render_surface = lambda *_args, **_kwargs: object()

        def create_window(_display, _screen, _root, rect, *_args):
            window = FakeWindow(rect)
            created.append(window)
            return window

        osd._create_osd_window = create_window
        osd.select.select = lambda *_args, **_kwargs: next(select_results)
        try:
            osd.display_on_all_monitors(
                "MW",
                1,
            )
        finally:
            (
                osd.display.Display,
                osd.randr.query_version,
                osd.get_monitors,
                osd.render_surface,
                osd._create_osd_window,
                osd.select.select,
            ) = originals

        self.assertEqual(
            [window.rect for window in created],
            [
                (0, 0, 1920, 1080, 510, 290),
                (1920, 0, 2560, 1440, 600, 340),
            ],
        )
        self.assertTrue(all(window.unmapped for window in created))
        self.assertTrue(all(window.destroyed for window in created))
        self.assertEqual(display.root.randr_mask, 7)
        self.assertTrue(display.closed)


if __name__ == "__main__":
    unittest.main()
