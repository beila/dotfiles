#!/usr/bin/env python3

import importlib.util
import os
import pathlib
import subprocess
import sys
import tempfile
import types
import unittest


class FakeStyle:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


class FakeSurface:
    def write_to_png(self, path):
        pathlib.Path(path).write_bytes(b"\x89PNG\r\n\x1a\n")


def load_module():
    osd = types.ModuleType("osd")
    osd.HANGUL_SLOT_WIDTH_MM = 60.0
    osd.HANGUL_SLOT_HEIGHT_MM = 70.0
    osd.HANGUL_SLOT_OFFSET_X_FRAC = -0.015
    osd.HANGUL_SLOT_OFFSET_Y_FRAC = 0.02
    osd.OSDStyle = FakeStyle
    osd.display_on_all_monitors = lambda *_args, **_kwargs: None
    osd.render_surface = lambda *_args, **_kwargs: FakeSurface()
    osd.sibling_offset_mm = lambda reference, gap: -(reference.width_mm + gap)
    sys.modules["osd"] = osd

    asset = pathlib.Path(__file__).with_name("osd") / "assets" / "mw.svg"
    os.environ["MIDWAY_OSD_IMAGE"] = str(asset)
    path = pathlib.Path(__file__).with_name("bin") / "midway-osd.py"
    spec = importlib.util.spec_from_file_location("midway_osd", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


midway_osd = load_module()


class StatusTest(unittest.TestCase):
    def runner(self, output, returncode=0, error=None):
        def run(command, **_kwargs):
            self.assertEqual(command, [midway_osd._status_command()])
            if error is not None:
                raise error
            return subprocess.CompletedProcess(
                command,
                returncode,
                stdout=output,
            )

        return run

    def test_verified_valid(self):
        self.assertEqual(
            midway_osd.midway_status(self.runner("valid\t2000\t1000\tserver\n")),
            (False, 2000),
        )

    def test_definite_invalid_states(self):
        for state, expiry in (
            ("invalid", 2000),
            ("expired", 999),
            ("missing", 0),
        ):
            self.assertEqual(
                midway_osd.midway_status(
                    self.runner(
                        f"{state}\t{expiry}\t1000\tserver\n",
                        returncode=1,
                    )
                ),
                (True, expiry),
            )

    def test_unknown_is_neither_valid_nor_invalid(self):
        self.assertEqual(
            midway_osd.midway_status(
                self.runner(
                    "unknown\t2000\t1000\tnetwork\n",
                    returncode=2,
                )
            ),
            (None, 2000),
        )

    def test_malformed_or_missing_command_is_fail_safe_invalid(self):
        self.assertEqual(
            midway_osd.midway_status(self.runner("wat\n")),
            (True, None),
        )
        self.assertEqual(
            midway_osd.midway_status(self.runner("", error=OSError("missing"))),
            (True, None),
        )


class IndicatorTest(unittest.TestCase):
    def test_invalid_reasserts_display_and_unknown_preserves_state(self):
        events = []
        indicator = midway_osd.MidwayIndicator(
            lambda: events.append("show"),
            lambda: events.append("hide"),
        )

        indicator.observe(False)
        indicator.observe(True)
        indicator.observe(True)
        indicator.observe(None)
        indicator.observe(False)
        indicator.observe(False)

        self.assertEqual(events, ["show", "show", "hide"])

    def test_health_check_recovers_a_lost_invalid_display(self):
        events = []
        indicator = midway_osd.MidwayIndicator(
            lambda: events.append("show"),
            lambda: events.append("hide"),
        )

        indicator.observe(True)
        indicator.ensure_display()

        self.assertEqual(events, ["show", "show"])


class ChildSupervisionTest(unittest.TestCase):
    def test_reaped_child_is_reported_as_not_running(self):
        original_child_process = midway_osd._child_process
        midway_osd._child_process = types.SimpleNamespace(poll=lambda: 0)
        try:
            self.assertFalse(midway_osd._child_is_running())
            self.assertIsNone(midway_osd._child_process)
        finally:
            midway_osd._child_process = original_child_process

    def test_show_starts_one_fresh_renderer_process(self):
        calls = []
        process = types.SimpleNamespace(poll=lambda: None)
        original_popen = midway_osd.subprocess.Popen
        original_child_process = midway_osd._child_process
        midway_osd._child_process = None

        def popen(args, **kwargs):
            calls.append((args, kwargs))
            return process

        midway_osd.subprocess.Popen = popen
        try:
            midway_osd.show()
            midway_osd.show()
        finally:
            midway_osd.subprocess.Popen = original_popen
            midway_osd._child_process = original_child_process

        self.assertEqual(len(calls), 1)
        self.assertEqual(
            calls[0][0],
            [
                midway_osd.sys.executable,
                str(pathlib.Path(midway_osd.__file__).resolve()),
                "--once",
            ],
        )
        self.assertIs(calls[0][1]["stdin"], subprocess.DEVNULL)


class StyleTest(unittest.TestCase):
    def test_restored_asset_and_geometry(self):
        style = midway_osd.STYLE
        self.assertTrue(style.image_file.endswith("mw.svg"))
        self.assertTrue(pathlib.Path(style.image_file).exists())
        self.assertEqual(style.fill_alpha, 0.5)
        self.assertEqual(style.height_mm, 42.0)
        self.assertAlmostEqual(style.width_mm / style.height_mm, 939 / 481, 2)
        self.assertEqual(style.offset_x_mm, -62.0)
        self.assertEqual(style.offset_y_mm, 14.0)

    def test_display_uses_midway_resource_name(self):
        calls = []
        original = midway_osd.display_on_all_monitors
        midway_osd.display_on_all_monitors = lambda *args, **kwargs: calls.append(
            (args, kwargs)
        )
        try:
            midway_osd._display()
        finally:
            midway_osd.display_on_all_monitors = original

        self.assertEqual(
            calls[0][1]["resource_name"],
            midway_osd.RESOURCE_NAME,
        )
        self.assertTrue(calls[0][1]["follow_monitor_changes"])

    def test_offline_render(self):
        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "midway.png"
            self.assertEqual(
                midway_osd._render_png(str(output), "1920x1200"),
                0,
            )
            self.assertEqual(output.read_bytes()[:8], b"\x89PNG\r\n\x1a\n")


if __name__ == "__main__":
    unittest.main()
