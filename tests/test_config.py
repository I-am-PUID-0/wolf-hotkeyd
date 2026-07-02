from __future__ import annotations

import unittest

from wolf_hotkeyd.config import ConfigError, parse_config


class ConfigParsingTests(unittest.TestCase):
    def test_parse_minimal_config(self) -> None:
        config = parse_config({})

        self.assertEqual(config.devices.include, ("gamepad",))
        self.assertEqual(config.devices.exclude, ())
        self.assertEqual(config.hotkeys, ())

    def test_parse_hotkey_normalizes_button_names(self) -> None:
        config = parse_config(
            {
                "hotkeys": [
                    {
                        "name": "force_close_game",
                        "buttons": ["btn_tl", "BTN_TR"],
                        "hold_time_seconds": 2,
                        "cooldown_seconds": 5,
                        "action": "/opt/wolf-hotkeyd/actions/force-close-game.sh",
                    }
                ]
            }
        )

        hotkey = config.hotkeys[0]
        self.assertEqual(hotkey.name, "force_close_game")
        self.assertEqual(hotkey.buttons, ("BTN_TL", "BTN_TR"))
        self.assertEqual(hotkey.hold_time_seconds, 2.0)
        self.assertEqual(hotkey.cooldown_seconds, 5.0)

    def test_rejects_missing_hotkey_name(self) -> None:
        with self.assertRaises(ConfigError):
            parse_config({"hotkeys": [{"buttons": ["BTN_TL"]}]})

    def test_rejects_non_positive_hold_time(self) -> None:
        with self.assertRaises(ConfigError):
            parse_config({"hotkeys": [{"name": "bad", "hold_time_seconds": 0}]})


if __name__ == "__main__":
    unittest.main()
