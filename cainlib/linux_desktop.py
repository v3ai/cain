"""Window-manager shortcuts and app launchers for Linux desktops.

Key *remaps* are done by keyd for every distro; the shortcuts here (close window,
open terminal, ...) belong to the desktop environment, so each one needs its own
backend. Supported: Cinnamon, GNOME (and GNOME-based: Ubuntu, Pop, Budgie), KDE
Plasma, XFCE. Anything else gets a printed list to set up by hand.
"""

from .actions import friendly, launch_command
from .keys import gtk_accel, kde_accel
from .util import expand, info, output, run, warn, which, write_text


def gv_list(items):
    return "[" + ", ".join("'%s'" % i.replace("'", "\\'") for i in items) + "]"


def gsettings(schema, key, value):
    run(["gsettings", "set", schema, key, value])


def _custom_list(schema, key):
    """Existing custom-keybinding entries, minus the ones cain made earlier."""
    raw = output(["gsettings", "get", schema, key]).strip().replace("@as ", "")
    items = [x.strip().strip("'") for x in raw.strip("[]").split(",") if x.strip()]
    return [i for i in items if not i.rstrip("/").rsplit("/", 1)[-1].startswith("cain")]


# ---------------------------------------------------------------- GNOME

GNOME_WM = {
    "close_window": ("org.gnome.desktop.wm.keybindings", "close"),
    "minimize": ("org.gnome.desktop.wm.keybindings", "minimize"),
    "toggle_maximize": ("org.gnome.desktop.wm.keybindings", "toggle-maximized"),
    "tile_left": ("org.gnome.mutter.keybindings", "toggle-tiled-left"),
    "tile_right": ("org.gnome.mutter.keybindings", "toggle-tiled-right"),
    "show_desktop": ("org.gnome.desktop.wm.keybindings", "show-desktop"),
    "switch_windows": ("org.gnome.desktop.wm.keybindings", "switch-windows"),
    "lock_screen": ("org.gnome.settings-daemon.plugins.media-keys", "screensaver"),
}


def apply_gnome(shortcuts, settings):
    media = "org.gnome.settings-daemon.plugins.media-keys"
    base = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
    paths = _custom_list(media, "custom-keybindings")
    n = 0
    for sc, combos in shortcuts:
        accels = [gtk_accel(c) for c in combos]
        if sc["action"] in GNOME_WM:
            schema, key = GNOME_WM[sc["action"]]
            gsettings(schema, key, gv_list(accels))
            if sc["action"] == "switch_windows":  # free Alt+Tab from the app switcher
                gsettings("org.gnome.desktop.wm.keybindings", "switch-applications", gv_list(["<Super>Tab"]))
            continue
        cmd = launch_command(sc, "linux", settings)
        for accel in accels:  # GNOME custom shortcuts hold a single key each
            path = "%scain%d/" % (base, n)
            n += 1
            schema = media + ".custom-keybinding:" + path
            gsettings(schema, "name", "'cain %s'" % friendly(sc))
            gsettings(schema, "command", "'%s'" % cmd.replace("'", "\\'"))
            gsettings(schema, "binding", "'%s'" % accel)
            paths.append(path)
    gsettings(media, "custom-keybindings", gv_list(paths))


# ---------------------------------------------------------------- Cinnamon

CINNAMON_WM = {
    "close_window": ("org.cinnamon.desktop.keybindings.wm", "close"),
    "minimize": ("org.cinnamon.desktop.keybindings.wm", "minimize"),
    "toggle_maximize": ("org.cinnamon.desktop.keybindings.wm", "toggle-maximized"),
    "tile_left": ("org.cinnamon.desktop.keybindings.wm", "push-tile-left"),
    "tile_right": ("org.cinnamon.desktop.keybindings.wm", "push-tile-right"),
    "show_desktop": ("org.cinnamon.desktop.keybindings.wm", "show-desktop"),
    "switch_windows": ("org.cinnamon.desktop.keybindings.wm", "switch-windows"),
    "lock_screen": ("org.cinnamon.desktop.keybindings.media-keys", "screensaver"),
}


def apply_cinnamon(shortcuts, settings):
    root = "org.cinnamon.desktop.keybindings"
    base = "/org/cinnamon/desktop/keybindings/custom-keybindings/"
    names = _custom_list(root, "custom-list")
    n = 0
    for sc, combos in shortcuts:
        accels = [gtk_accel(c) for c in combos]
        if sc["action"] in CINNAMON_WM:
            gsettings(*CINNAMON_WM[sc["action"]], gv_list(accels))
            continue
        name = "cain%d" % n
        n += 1
        schema = root + ".custom-keybinding:" + base + name + "/"
        gsettings(schema, "name", "'%s'" % friendly(sc))
        gsettings(schema, "command", "'%s'" % launch_command(sc, "linux", settings).replace("'", "\\'"))
        gsettings(schema, "binding", gv_list(accels))
        names.append(name)
    gsettings(root, "custom-list", gv_list(names))


# ---------------------------------------------------------------- XFCE

XFCE_WM = {
    "close_window": "close_window_key", "minimize": "hide_window_key",
    "toggle_maximize": "maximize_window_key", "tile_left": "tile_left_key",
    "tile_right": "tile_right_key", "show_desktop": "show_desktop_key",
    "switch_windows": "cycle_windows_key",
}


def apply_xfce(shortcuts, settings):
    def setprop(prop, value):
        run(["xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop, "-n", "-t", "string", "-s", value])

    for sc, combos in shortcuts:
        for c in combos:
            accel = gtk_accel(c)
            if sc["action"] in XFCE_WM:
                setprop("/xfwm4/custom/" + accel, XFCE_WM[sc["action"]])
            elif sc["action"] == "lock_screen":
                setprop("/commands/custom/" + accel, "xflock4")
            else:
                setprop("/commands/custom/" + accel, launch_command(sc, "linux", settings))


# ---------------------------------------------------------------- KDE Plasma

KDE_WM = {
    "close_window": ("kwin", "Window Close"),
    "minimize": ("kwin", "Window Minimize"),
    "toggle_maximize": ("kwin", "Window Maximize"),
    "tile_left": ("kwin", "Window Quick Tile Left"),
    "tile_right": ("kwin", "Window Quick Tile Right"),
    "show_desktop": ("kwin", "Show Desktop"),
    "switch_windows": ("kwin", "Walk Through Windows"),
    "lock_screen": ("ksmserver", "Lock Session"),
}


def apply_kde(shortcuts, settings):
    kwrite = which("kwriteconfig6") or which("kwriteconfig5")
    if not kwrite:
        warn("kwriteconfig6/5 not found; can't set KDE shortcuts")
        return
    plasma6 = kwrite.endswith("6")

    def kw(groups, key, value):
        cmd = [kwrite, "--file", "kglobalshortcutsrc"]
        for g in groups:
            cmd += ["--group", g]
        run(cmd + ["--key", key, value])

    for sc, combos in shortcuts:
        accels = "\t".join(kde_accel(c) for c in combos)
        if sc["action"] in KDE_WM:
            group, key = KDE_WM[sc["action"]]
            # the value is a KConfig list "active,default,name": escape commas in keys
            kw([group], key, "%s,none,%s" % (accels.replace(",", "\\,"), key))
            continue
        desktop_id = "cain-%s.desktop" % sc["action"].replace(":", "-")
        write_text(expand("~/.local/share/applications/" + desktop_id),
                   "[Desktop Entry]\nType=Application\nName=cain %s\nExec=%s\nNoDisplay=true\n"
                   % (friendly(sc), launch_command(sc, "linux", settings)))
        if plasma6:
            kw(["services", desktop_id], "_launch", accels)
        else:
            kw([desktop_id], "_launch", "%s,none,%s" % (accels.replace(",", "\\,"), friendly(sc)))
    info("  KDE picks up new global shortcuts after you log out and back in.")


# ----------------------------------------------------------------

def apply(desktop, shortcuts, settings):
    backends = {"gnome": apply_gnome, "cinnamon": apply_cinnamon, "xfce": apply_xfce, "kde": apply_kde}
    if desktop in backends:
        backends[desktop](shortcuts, settings)
        return
    warn("don't know how to set shortcuts on this desktop (%r). Set these up by hand:"
         % (desktop or "unknown"))
    for sc, combos in shortcuts:
        cmd = launch_command(sc, "linux", settings) or "(window manager action)"
        info("    %-28s %-18s %s" % (", ".join(map(str, combos)), sc["action"], cmd))
