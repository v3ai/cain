"""Run with: python3 -m unittest discover tests"""

import json
import unittest

from cainlib import ahk, karabiner, keyd
from cainlib.keys import Combo, mac_translate
from cainlib.manifest import Manifest


class KeysTest(unittest.TestCase):
    def test_parse(self):
        c = Combo.parse("Ctrl+Shift+Tab")
        self.assertEqual(c.mods, ("ctrl", "shift"))
        self.assertEqual(c.key, "tab")
        self.assertEqual(Combo.parse("cmd+escape"), Combo(["super"], "esc"))
        with self.assertRaises(ValueError):
            Combo.parse("alt+nope")

    def test_mac_translate(self):
        t = lambda s: str(mac_translate(Combo.parse(s)))
        self.assertEqual(t("ctrl+c"), "super+c")
        self.assertEqual(t("ctrl+tab"), "ctrl+tab")
        self.assertEqual(t("ctrl+left"), "alt+left")
        self.assertEqual(t("home"), "super+left")


class GenerateTest(unittest.TestCase):
    """Every entry in the real cain.json must generate for every OS."""

    def setUp(self):
        self.m = Manifest()

    def test_keyd(self):
        conf = keyd.generate(self.m.remaps("linux"))
        self.assertIn("[alt]\nh = left", conf)
        self.assertIn("capslock = esc", conf)

    def test_ahk(self):
        script = ahk.generate(self.m.remaps("windows"), self.m.shortcuts("windows"), self.m.settings)
        self.assertIn('!h::Send "{Left}"', script)
        self.assertIn("CapsLock::Esc", script)
        hotkeys = [l.split("::")[0] for l in script.splitlines() if "::" in l and not l.startswith(";")]
        self.assertEqual(len(hotkeys), len(set(hotkeys)), "duplicate AutoHotkey hotkeys")

    def test_karabiner(self):
        rules = karabiner.generate(self.m.remaps("macos"), self.m.shortcuts("macos"), self.m.settings)
        json.dumps(rules)
        self.assertTrue(all(r["description"].startswith(karabiner.TAG) for r in rules))


if __name__ == "__main__":
    unittest.main()
