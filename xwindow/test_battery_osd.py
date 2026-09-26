import importlib.util
import pathlib
import sys
import types
import unittest


class FakeStyle:
    def __init__(self, **kwargs):
        self.__dict__.update(kwargs)


def load_module():
    osd = types.ModuleType("osd")
    osd.OSDStyle = FakeStyle
    osd.display_on_all_monitors = lambda *_args, **_kwargs: None
    osd.render_surface = lambda *_args, **_kwargs: None
    sys.modules["osd"] = osd

    path = pathlib.Path(__file__).with_name("bin") / "battery-osd.py"
    spec = importlib.util.spec_from_file_location("battery_osd", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


battery_osd = load_module()


class BatteryStyleTests(unittest.TestCase):
    def test_uses_lego_alert_colours(self):
        self.assertEqual(
            battery_osd.STYLES["warn"].fill_rgb,
            (250 / 255, 200 / 255, 10 / 255),
        )
        self.assertEqual(
            battery_osd.STYLES["critical"].fill_rgb,
            (180 / 255, 0.0, 0.0),
        )


if __name__ == "__main__":
    unittest.main()
