"""Loads cain.json and filters entries for the current OS / desktop."""

import json

from .keys import Combo, mac_swap_alt_cmd, mac_translate
from .util import ROOT

MANIFEST = ROOT / "cain.json"


class Manifest:
    def __init__(self, path=MANIFEST):
        self.path = path
        with open(path, encoding="utf-8") as f:
            self.data = json.load(f)
        self.settings = self.data.get("settings", {})
        self.git = self.data.get("git", {})

    @staticmethod
    def applies(entry, os_name, desktop=""):
        if "os" in entry and os_name not in entry["os"]:
            return False
        if "desktop" in entry and (os_name != "linux" or desktop not in entry["desktop"]):
            return False
        return True

    def packages(self, os_name):
        return [p for p in self.data.get("packages", []) if self.applies(p, os_name)]

    def files(self, os_name, desktop=""):
        return [f for f in self.data.get("files", []) if self.applies(f, os_name, desktop)]

    def scripts(self, os_name):
        return [s for s in self.data.get("scripts", []) if self.applies(s, os_name)]

    def remaps(self, os_name):
        """[(from Combo, to Combo)] with per-OS overrides and macOS translation applied."""
        out = []
        for r in self.data.get("remaps", []):
            if not self.applies(r, os_name):
                continue
            src = self._input(r["from"], os_name)
            if os_name in r:  # e.g. "macos": "cmd+shift+v" or "macos": null to skip
                if r[os_name] is None:
                    continue
                dst = Combo.parse(r[os_name])
            else:
                dst = Combo.parse(r["to"])
                if os_name == "macos" and self.settings.get("mac_translate", True):
                    dst = mac_translate(dst)
            if dst == src:  # e.g. Cmd+M -> Cmd+M after macOS translation
                continue
            out.append((src, dst))
        return out

    def _input(self, text, os_name):
        combo = Combo.parse(text)
        if os_name == "macos" and self.settings.get("mac_alt") == "command":
            combo = mac_swap_alt_cmd(combo)
        return combo

    def shortcuts(self, os_name):
        """[(shortcut dict, [Combo, ...])]"""
        return [(s, [self._input(k, os_name) for k in s["keys"]])
                for s in self.data.get("shortcuts", []) if self.applies(s, os_name)]
