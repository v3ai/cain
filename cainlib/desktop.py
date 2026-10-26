"""Desktop look: wallpaper, dark mode, and (Cinnamon only) the full dconf settings dump."""

import re

from . import util
from .util import ROOT, expand, info, output, run, warn, which, write_text

CINNAMON_DUMP = ROOT / "files/cinnamon/cinnamon-settings"


def _copy_wallpaper(settings):
    src = ROOT / settings["wallpaper"]
    if not src.exists():
        warn("wallpaper %s not found" % src)
        return None
    dest = expand("~/.config/cain/wallpaper" + src.suffix)
    util.copy_file(src, dest)
    return dest


def set_wallpaper(os_name, desktop, settings):
    if not settings.get("wallpaper"):
        return
    path = _copy_wallpaper(settings)
    if not path:
        return
    uri = "'file://%s'" % path
    if os_name == "windows":
        if not util.DRY_RUN:
            import ctypes
            ctypes.windll.user32.SystemParametersInfoW(20, 0, str(path), 3)  # SPI_SETDESKWALLPAPER
    elif os_name == "macos":
        run(["osascript", "-e",
             'tell application "System Events" to tell every desktop to set picture to "%s"' % path])
    elif desktop == "cinnamon":
        run(["gsettings", "set", "org.cinnamon.desktop.background", "picture-uri", uri])
    elif desktop == "gnome":
        run(["gsettings", "set", "org.gnome.desktop.background", "picture-uri", uri])
        run(["gsettings", "set", "org.gnome.desktop.background", "picture-uri-dark", uri])
    elif desktop == "mate":
        run(["gsettings", "set", "org.mate.background", "picture-filename", str(path)])
    elif desktop == "kde":
        run(["plasma-apply-wallpaperimage", str(path)])
    elif desktop == "xfce":
        for prop in output(["xfconf-query", "-c", "xfce4-desktop", "-l"]).split():
            if prop.endswith("/last-image"):
                run(["xfconf-query", "-c", "xfce4-desktop", "-p", prop, "-s", str(path)])
    else:
        warn("don't know how to set the wallpaper here; it's at " + str(path))


def set_dark_mode(os_name, desktop, settings):
    if not settings.get("dark_mode"):
        return
    if os_name == "windows":
        if util.DRY_RUN:
            info("  [dry-run] set AppsUseLightTheme/SystemUsesLightTheme = 0")
            return
        import winreg
        key = winreg.CreateKey(winreg.HKEY_CURRENT_USER,
                               r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize")
        for name in ("AppsUseLightTheme", "SystemUsesLightTheme"):
            winreg.SetValueEx(key, name, 0, winreg.REG_DWORD, 0)
    elif os_name == "macos":
        run(["osascript", "-e",
             'tell application "System Events" to tell appearance preferences to set dark mode to true'])
    elif desktop in ("gnome", "cinnamon"):
        run(["gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"])
    elif desktop == "kde":
        run(["plasma-apply-colorscheme", "BreezeDark"])
    elif desktop == "xfce":
        run(["xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName", "-s", "Adwaita-dark"])


def _filtered_cinnamon_dump():
    """The saved dconf dump minus keybindings (cain.json owns those) and machine paths."""
    out, skip = [], False
    for line in CINNAMON_DUMP.read_text(encoding="utf-8").splitlines():
        if line.startswith("["):
            skip = line.startswith("[org/cinnamon/desktop/keybindings")
        if skip or re.match(r"picture-uri=", line):
            continue
        out.append(line)
    return "\n".join(out) + "\n"


def load_cinnamon_settings():
    if not CINNAMON_DUMP.exists() or not which("dconf"):
        return
    run(["dconf", "load", "/"], input=_filtered_cinnamon_dump())


def collect_cinnamon_settings():
    """dconf dump into the repo. Returns True if it changed."""
    dump = output(["dconf", "dump", "/"])
    if not dump:
        return False
    old = CINNAMON_DUMP.read_text(encoding="utf-8") if CINNAMON_DUMP.exists() else ""
    if dump == old:
        return False
    write_text(CINNAMON_DUMP, dump)
    return True


def apply(os_name, desktop, settings):
    if os_name == "linux" and desktop == "cinnamon":
        load_cinnamon_settings()
    set_wallpaper(os_name, desktop, settings)
    set_dark_mode(os_name, desktop, settings)
