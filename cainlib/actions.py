"""What each shortcut action means on each OS.

Window-manager actions (close_window, minimize, ...) are handled natively by each
backend. Everything else is a *launch* action that boils down to a shell command,
resolved here.
"""

import shlex
import sys
from pathlib import Path

from .util import which, expand

WM_ACTIONS = ["close_window", "minimize", "toggle_maximize", "tile_left", "tile_right",
              "show_desktop", "switch_windows", "lock_screen"]

LINUX_TERMINALS = ["x-terminal-emulator", "gnome-terminal", "konsole", "xfce4-terminal",
                   "mate-terminal", "kitty", "alacritty", "wezterm", "foot", "tilix", "xterm"]
LINUX_CALCULATORS = ["gnome-calculator", "kcalc", "galculator", "mate-calc",
                     "qalculate-gtk", "xcalc"]


def bin_dir(os_name):
    """Where cain installs its scripts (booklister, listlauncher, ...)."""
    return expand("~/.local/bin")


def python_for_gui(os_name):
    exe = Path(sys.executable)
    if os_name == "windows":
        w = exe.with_name("pythonw.exe")
        return str(w if w.exists() else exe)
    return str(exe)


def script_command(name, os_name):
    script = bin_dir(os_name) / (name + ".py" if os_name == "windows" else name)
    if os_name == "windows":
        return '"%s" "%s"' % (python_for_gui(os_name), script)
    return "%s %s" % (shlex.quote(python_for_gui(os_name)), shlex.quote(str(script)))


def _first(cmds, fallback):
    for c in cmds:
        if which(c):
            return c
    return fallback


def launch_command(shortcut, os_name, settings):
    """Return the command line for a launch shortcut, or None if it is a WM action."""
    action = shortcut["action"]
    if action in WM_ACTIONS:
        return None
    if "run" in shortcut:
        run = shortcut["run"]
        return run.get(os_name) if isinstance(run, dict) else run
    if action.startswith("script:"):
        return script_command(action.split(":", 1)[1], os_name)

    home = str(expand("~"))
    url = settings.get("homepage", "https://www.google.com")
    table = {
        "linux": {
            "terminal": lambda: _first(LINUX_TERMINALS, "xterm"),
            "calculator": lambda: _first(LINUX_CALCULATORS, "xcalc"),
            "browser": lambda: "xdg-open " + shlex.quote(url),
            "file_manager": lambda: "xdg-open " + shlex.quote(home),
        },
        "macos": {
            "terminal": lambda: "open -a Terminal",
            "calculator": lambda: "open -a Calculator",
            "browser": lambda: "open " + shlex.quote(url),
            "file_manager": lambda: "open " + shlex.quote(home),
        },
        "windows": {
            "terminal": lambda: "wt.exe",
            "calculator": lambda: "calc.exe",
            "browser": lambda: url,
            "file_manager": lambda: 'explorer.exe "%s"' % home,
        },
    }
    try:
        return table[os_name][action]()
    except KeyError:
        raise ValueError("unknown shortcut action %r (add a \"run\" command for it)" % action)


def friendly(shortcut):
    return shortcut.get("name") or shortcut["action"].split(":")[-1].replace("_", " ")
