"""macOS key remaps + shortcuts through Karabiner-Elements complex modifications."""

import json

from .actions import launch_command
from .keys import Combo, karabiner_from, karabiner_to
from .util import expand, info, warn, write_text

CONFIG = "~/.config/karabiner/karabiner.json"
TAG = "cain: "

MISSION_CONTROL = "'/System/Applications/Mission Control.app/Contents/MacOS/Mission Control'"

# How each window-manager action is done on macOS (key combo, extra modifiers) or shell.
WM = {
    "close_window": (Combo(["super"], "w"), ()),
    "minimize": (Combo(["super"], "m"), ()),
    "toggle_maximize": (Combo(["ctrl"], "f"), ("fn",)),      # Window > Fill (macOS 15+)
    "tile_left": (Combo(["ctrl"], "left"), ("fn",)),          # Window > Move & Resize > Left
    "tile_right": (Combo(["ctrl"], "right"), ("fn",)),
    "switch_windows": (Combo(["super"], "tab"), ()),
    "lock_screen": (Combo(["ctrl", "super"], "q"), ()),
    "show_desktop": MISSION_CONTROL + " 1",
}


def _manipulator(frm, to):
    return {"type": "basic", "from": frm, "to": to}


def generate(remaps, shortcuts, settings):
    """Return the list of Karabiner rules cain owns."""
    remap_rules = []
    for src, dst in remaps:
        optional = ["any"] if not src.mods else (["caps_lock", "shift"] if not dst.mods else ["caps_lock"])
        remap_rules.append({
            "description": "%s%s -> %s" % (TAG, src, dst),
            "manipulators": [_manipulator(karabiner_from(src, optional), [karabiner_to(dst)])],
        })

    shortcut_rules = []
    for sc, combos in shortcuts:
        action = sc["action"]
        if action in WM and not isinstance(WM[action], str):
            combo, extra = WM[action]
            to = [karabiner_to(combo, extra)]
        else:
            cmd = WM.get(action) or launch_command(sc, "macos", settings)
            to = [{"shell_command": cmd}]
        shortcut_rules.append({
            "description": "%s%s (%s)" % (TAG, action, ", ".join(map(str, combos))),
            "manipulators": [_manipulator(karabiner_from(c), to) for c in combos],
        })
    return remap_rules + shortcut_rules


def apply(remaps, shortcuts, settings):
    from .packages import brew_install
    if not expand("/Applications/Karabiner-Elements.app").exists():
        brew_install(["--cask karabiner-elements"])
    path = expand(CONFIG)
    config = {"profiles": [{"name": "Default profile", "selected": True}]}
    if path.exists():
        try:
            config = json.loads(path.read_text(encoding="utf-8"))
        except ValueError:
            warn("%s isn't valid JSON; leaving it alone" % path)
            return
    profiles = config.setdefault("profiles", [{"name": "Default profile", "selected": True}])
    profile = next((p for p in profiles if p.get("selected")), profiles[0])
    rules = profile.setdefault("complex_modifications", {}).setdefault("rules", [])
    kept = [r for r in rules if not r.get("description", "").startswith(TAG)]
    profile["complex_modifications"]["rules"] = generate(remaps, shortcuts, settings) + kept
    write_text(path, json.dumps(config, indent=4) + "\n")
    info("  Karabiner reloads this automatically. The first time, open Karabiner-Elements and\n"
         "  allow its Input Monitoring / driver permissions in System Settings > Privacy & Security.")
