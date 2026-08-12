#!/usr/bin/env python3

import importlib.util
import pathlib
import sys
import types
import unittest


def load_module():
    cairo = types.ModuleType("cairo")
    cairo.FONT_WEIGHT_NORMAL = 0
    sys.modules["cairo"] = cairo

    osd = types.ModuleType("osd")
    osd.OSDStyle = lambda **_kwargs: object()
    osd.display_on_all_monitors = lambda *_args, **_kwargs: None
    osd.render_surface = lambda *_args, **_kwargs: None
    sys.modules["osd"] = osd

    path = pathlib.Path(__file__).with_name("bin") / "hangul-osd.py"
    spec = importlib.util.spec_from_file_location("hangul_osd", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


hangul_osd = load_module()


class FakeVariant:
    def __init__(self, value):
        self.value = value

    def unpack(self):
        return self.value


def ibus_text(text):
    return (
        "IBusText",
        {},
        text,
        ("IBusAttrList", {}, []),
    )


def ibus_property(name, state, symbol):
    return (
        "IBusProperty",
        {},
        name,
        1,
        ibus_text("Hangul mode"),
        "",
        ibus_text("Enable/Disable Hangul mode"),
        True,
        True,
        state,
        ("IBusPropList", {}, []),
        ibus_text(symbol),
    )


class InputModeParserTest(unittest.TestCase):
    def test_property_updated_states(self):
        english = FakeVariant((FakeVariant(ibus_property("InputMode", 0, "EN")),))
        hangul = FakeVariant((FakeVariant(ibus_property("InputMode", 1, "한")),))

        self.assertIs(hangul_osd._input_mode_from_payload(english), False)
        self.assertIs(hangul_osd._input_mode_from_payload(hangul), True)

    def test_properties_registered_finds_nested_input_mode(self):
        properties = (
            "IBusPropList",
            {},
            [
                FakeVariant(ibus_property("InputMode", 1, "한")),
                FakeVariant(ibus_property("setup", 0, "")),
            ],
        )

        self.assertIs(
            hangul_osd._input_mode_from_payload(
                FakeVariant((FakeVariant(properties),))
            ),
            True,
        )

    def test_missing_or_invalid_input_mode_is_unknown(self):
        empty = FakeVariant((FakeVariant(("IBusPropList", {}, [])),))
        invalid = FakeVariant(
            (FakeVariant(ibus_property("InputMode", 2, "?")),)
        )

        self.assertIsNone(hangul_osd._input_mode_from_payload(empty))
        self.assertIsNone(hangul_osd._input_mode_from_payload(invalid))


class ModeIndicatorTest(unittest.TestCase):
    def test_starts_hidden_and_applies_only_transitions(self):
        events = []
        indicator = hangul_osd.ModeIndicator(
            lambda: events.append("show"),
            lambda: events.append("hide"),
        )

        indicator.observe(None)
        indicator.observe(False)
        indicator.observe(False)
        self.assertEqual(events, [])

        indicator.observe(True)
        indicator.observe(True)
        indicator.observe(None)
        indicator.observe(False)
        indicator.observe(False)
        self.assertEqual(events, ["show", "hide"])


if __name__ == "__main__":
    unittest.main()
