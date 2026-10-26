"""Platform-neutral key combos and the tables that translate them for each backend.

Combos are written like "alt+h", "lalt+quote", "ctrl+shift+tab", "super+d".

Modifiers: alt, lalt, ralt, ctrl, lctrl, rctrl, shift, super, lsuper, rsuper
           (alt/ctrl/super = either side; super = Windows key / Cmd / Meta)
Keys:      a-z, 0-9, f1-f12, comma, period, slash, semicolon, quote,
           bracketleft, bracketright, backslash, minus, equal, grave,
           tab, enter, esc, backspace, delete, space, capslock,
           left, right, up, down, home, end, pageup, pagedown
"""

MODIFIERS = ["super", "lsuper", "rsuper", "ctrl", "lctrl", "rctrl", "alt", "lalt", "ralt", "shift"]
MOD_ORDER = {m: i for i, m in enumerate(MODIFIERS)}
SIDED = {"lalt", "ralt", "lctrl", "rctrl", "lsuper", "rsuper"}

PUNCT = ["comma", "period", "slash", "semicolon", "quote", "bracketleft",
         "bracketright", "backslash", "minus", "equal", "grave"]
NAMED = ["tab", "enter", "esc", "backspace", "delete", "space", "capslock",
         "left", "right", "up", "down", "home", "end", "pageup", "pagedown"]
LETTERS = [chr(c) for c in range(ord("a"), ord("z") + 1)]
DIGITS = [str(d) for d in range(10)]
FKEYS = ["f%d" % i for i in range(1, 13)]
KEYS = set(LETTERS + DIGITS + FKEYS + PUNCT + NAMED)

ALIASES = {"escape": "esc", "return": "enter", "dot": "period", "apostrophe": "quote",
           "leftbrace": "bracketleft", "rightbrace": "bracketright", "control": "ctrl",
           "win": "super", "cmd": "super", "meta": "super", "option": "alt",
           "caps": "capslock", "bksp": "backspace", "del": "delete"}


class Combo:
    def __init__(self, mods, key):
        self.mods = tuple(sorted(set(mods), key=MOD_ORDER.get))
        self.key = key

    @classmethod
    def parse(cls, text):
        parts = [ALIASES.get(p, p) for p in text.lower().replace(" ", "").split("+")]
        *mods, key = parts
        for m in mods:
            if m not in MOD_ORDER:
                raise ValueError("unknown modifier %r in %r" % (m, text))
        if key not in KEYS:
            raise ValueError("unknown key %r in %r" % (key, text))
        return cls(mods, key)

    def with_mods(self, mods):
        return Combo(mods, self.key)

    def generic_mods(self):
        """Modifiers with the left/right distinction dropped."""
        return tuple(sorted({m[1:] if m in SIDED else m for m in self.mods}, key=MOD_ORDER.get))

    def __eq__(self, other):
        return isinstance(other, Combo) and (self.mods, self.key) == (other.mods, other.key)

    def __hash__(self):
        return hash((self.mods, self.key))

    def __str__(self):
        return "+".join(self.mods + (self.key,))

    __repr__ = __str__


MAC_SWAP = {"alt": "super", "lalt": "lsuper", "ralt": "rsuper",
            "super": "alt", "lsuper": "lalt", "rsuper": "ralt"}


def mac_swap_alt_cmd(combo):
    """For *input* combos on a Mac keyboard: the key under your thumb is Command, so
    treat Command as the PC's Alt (and Option as the PC's Super)."""
    return Combo([MAC_SWAP.get(m, m) for m in combo.mods], combo.key)


def mac_translate(combo):
    """Rewrite a Linux/Windows-style *output* combo into the macOS equivalent.

    ctrl+c -> cmd+c, ctrl+left -> option+left, home -> cmd+left, end -> cmd+right.
    ctrl+tab / ctrl+shift+tab stay as they are (they switch tabs on macOS too).
    """
    mods, key = set(combo.mods), combo.key
    ctrl = mods & {"ctrl", "lctrl", "rctrl"}
    if not mods and key == "home":
        return Combo(["super"], "left")
    if not mods and key == "end":
        return Combo(["super"], "right")
    if ctrl and key in ("left", "right"):
        return Combo((mods - ctrl) | {"alt"}, key)
    if ctrl and key != "tab":
        return Combo((mods - ctrl) | {"super"}, key)
    return combo


# ---------------------------------------------------------------- keyd (Linux)

KEYD_KEYS = {"period": "dot", "quote": "apostrophe", "bracketleft": "leftbrace",
             "bracketright": "rightbrace"}
KEYD_MODS = {"ctrl": "C", "shift": "S", "alt": "A", "super": "M"}


def keyd_key(key):
    return KEYD_KEYS.get(key, key)


def keyd_output(combo):
    prefix = "".join(KEYD_MODS[m] + "-" for m in combo.generic_mods())
    return prefix + keyd_key(combo.key)


# ---------------------------------------------------------- AutoHotkey (Windows)

AHK_VK = {"comma": "vkBC", "period": "vkBE", "slash": "vkBF", "semicolon": "vkBA",
          "quote": "vkDE", "bracketleft": "vkDB", "bracketright": "vkDD",
          "backslash": "vkDC", "minus": "vkBD", "equal": "vkBB", "grave": "vkC0"}
AHK_NAMED = {"tab": "Tab", "enter": "Enter", "esc": "Esc", "backspace": "Backspace",
             "delete": "Delete", "space": "Space", "capslock": "CapsLock", "left": "Left",
             "right": "Right", "up": "Up", "down": "Down", "home": "Home", "end": "End",
             "pageup": "PgUp", "pagedown": "PgDn"}
AHK_HOTKEY_MODS = {"super": "#", "lsuper": "<#", "rsuper": ">#", "ctrl": "^", "lctrl": "<^", "rctrl": ">^", "alt": "!",
                   "lalt": "<!", "ralt": ">!", "shift": "+"}
AHK_SEND_MODS = {"super": "#", "ctrl": "^", "alt": "!", "shift": "+"}


def ahk_key(key):
    if key in AHK_VK:
        return AHK_VK[key]
    if key in AHK_NAMED:
        return AHK_NAMED[key]
    return key.upper() if key in FKEYS else key


def ahk_hotkey(combo):
    return "".join(AHK_HOTKEY_MODS[m] for m in combo.mods) + ahk_key(combo.key)


def ahk_send(combo):
    key = ahk_key(combo.key)
    if len(key) > 1:
        key = "{" + key + "}"
    return "".join(AHK_SEND_MODS[m] for m in combo.generic_mods()) + key


# ------------------------------------------------------ Karabiner-Elements (macOS)

KARABINER_KEYS = {"comma": "comma", "period": "period", "slash": "slash",
                  "semicolon": "semicolon", "quote": "quote", "bracketleft": "open_bracket",
                  "bracketright": "close_bracket", "backslash": "backslash",
                  "minus": "hyphen", "equal": "equal_sign", "grave": "grave_accent_and_tilde",
                  "tab": "tab", "enter": "return_or_enter", "esc": "escape",
                  "backspace": "delete_or_backspace", "delete": "delete_forward",
                  "space": "spacebar", "capslock": "caps_lock", "left": "left_arrow",
                  "right": "right_arrow", "up": "up_arrow", "down": "down_arrow",
                  "home": "home", "end": "end", "pageup": "page_up", "pagedown": "page_down"}
KARABINER_FROM_MODS = {"super": "command", "lsuper": "left_command",
                      "rsuper": "right_command", "ctrl": "control", "lctrl": "left_control",
                       "rctrl": "right_control", "alt": "option", "lalt": "left_option",
                       "ralt": "right_option", "shift": "shift"}
KARABINER_TO_MODS = {"super": "left_command", "ctrl": "left_control",
                     "alt": "left_option", "shift": "left_shift", "fn": "fn"}


def karabiner_key(key):
    return KARABINER_KEYS.get(key, key)


def karabiner_from(combo, optional=("caps_lock",)):
    out = {"key_code": karabiner_key(combo.key)}
    mods = {"optional": list(optional)}
    if combo.mods:
        mods["mandatory"] = [KARABINER_FROM_MODS[m] for m in combo.mods]
    out["modifiers"] = mods
    return out


def karabiner_to(combo, extra_mods=()):
    out = {"key_code": karabiner_key(combo.key)}
    mods = [KARABINER_TO_MODS[m] for m in combo.generic_mods()] + list(extra_mods)
    if mods:
        out["modifiers"] = mods
    return out


# ---------------------------------------------- GTK accelerators (GNOME, Cinnamon, XFCE)

GTK_KEYS = {"comma": "comma", "period": "period", "slash": "slash", "semicolon": "semicolon",
            "quote": "apostrophe", "bracketleft": "bracketleft", "bracketright": "bracketright",
            "backslash": "backslash", "minus": "minus", "equal": "equal", "grave": "grave",
            "tab": "Tab", "enter": "Return", "esc": "Escape", "backspace": "BackSpace",
            "delete": "Delete", "space": "space", "capslock": "Caps_Lock", "left": "Left",
            "right": "Right", "up": "Up", "down": "Down", "home": "Home", "end": "End",
            "pageup": "Page_Up", "pagedown": "Page_Down"}
GTK_MODS = {"super": "<Super>", "ctrl": "<Primary>", "alt": "<Alt>", "shift": "<Shift>"}


def gtk_accel(combo):
    key = GTK_KEYS.get(combo.key, combo.key.upper() if combo.key in FKEYS else combo.key)
    return "".join(GTK_MODS[m] for m in combo.generic_mods()) + key


# ----------------------------------------------------------------- KDE Plasma

KDE_KEYS = {"comma": ",", "period": ".", "slash": "/", "semicolon": ";", "quote": "'",
            "bracketleft": "[", "bracketright": "]", "backslash": "\\", "minus": "-",
            "equal": "=", "grave": "`", "tab": "Tab", "enter": "Return", "esc": "Esc",
            "backspace": "Backspace", "delete": "Del", "space": "Space",
            "capslock": "CapsLock", "left": "Left", "right": "Right", "up": "Up",
            "down": "Down", "home": "Home", "end": "End", "pageup": "PgUp",
            "pagedown": "PgDown"}
KDE_MODS = {"super": "Meta", "ctrl": "Ctrl", "alt": "Alt", "shift": "Shift"}


def kde_accel(combo):
    key = KDE_KEYS.get(combo.key, combo.key.upper())
    return "+".join([KDE_MODS[m] for m in combo.generic_mods()] + [key])
