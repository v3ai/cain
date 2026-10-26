#!/usr/bin/env python3
"""cain - Collects And INstalls dotfiles, keybindings and programs on Linux, macOS and Windows.

    cain                 ask whether to collect or install
    cain -c | collect    copy this machine's configs into the repo, commit and push
    cain -i | install    install programs, configs, keybindings and desktop settings
    cain install keys    run only some install steps (see STEPS below)
    cain keys            shorthand for `cain install keys`
    cain generate [os]   print the keybinding config cain would write for linux/macos/windows
    -n, --dry-run        show what would happen without changing anything
"""

import argparse
import datetime
import json
import stat
import sys

if sys.version_info < (3, 7):
    sys.exit("cain needs Python 3.7 or newer")

from cainlib import ahk, desktop, karabiner, keyd, linux_desktop, packages, util
from cainlib.actions import bin_dir
from cainlib.manifest import Manifest
from cainlib.util import ROOT, expand, info, run, step

ASCII = r'''
                         db

      ,p6"bo   ,6"Yb.  `7MM  `7MMpMMMb.
     6M'  OO  8)   MM    MM    MM    MM
     8M        ,pm9MM    MM    MM    MM
     YM.    , 8M   MM    MM    MM    MM
      YMbmd'  `Moo9^Yo..JMML..JMML  JMML.
'''

STEPS = ["packages", "git", "files", "scripts", "shell", "keys", "desktop"]


# ------------------------------------------------------------------ install steps

def install_packages(m, os_name, de):
    packages.install(m, os_name)


def install_git(m, os_name, de):
    for key in ("name", "email"):
        if m.git.get(key):
            run(["git", "config", "--global", "user." + key, m.git[key]])


def install_files(m, os_name, de):
    backup = expand("~/.cain-backup/" + datetime.datetime.now().strftime("%Y%m%d-%H%M%S"))
    for f in m.files(os_name, de):
        src, dest = ROOT / f["src"], expand(f["dest"])
        if util.same_file(src, dest):
            info("  SAME:    " + f["dest"])
            continue
        util.copy_file(src, dest, backup_dir=backup)
        info("  INSTALLED: " + f["dest"])
    if backup.exists():
        info("  (previous versions backed up in %s)" % backup)


def install_scripts(m, os_name, de):
    target = bin_dir(os_name)
    for s in m.scripts(os_name):
        src = ROOT / s["src"]
        if os_name == "windows":
            util.copy_file(src, target / (s["name"] + ".py"))
            util.write_text(target / (s["name"] + ".cmd"),
                            '@"%s" "%%~dp0%s.py" %%*\r\n' % (sys.executable, s["name"]))
        else:
            dest = target / s["name"]
            util.copy_file(src, dest)
            if not util.DRY_RUN:
                dest.chmod(dest.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
        info("  INSTALLED: " + s["name"])
    if os_name == "windows":
        _windows_add_to_path(target)


def _windows_add_to_path(folder):
    if util.DRY_RUN:
        info("  [dry-run] add %s to the user PATH" % folder)
        return
    import winreg
    with winreg.OpenKey(winreg.HKEY_CURRENT_USER, "Environment", 0, winreg.KEY_ALL_ACCESS) as key:
        try:
            current, kind = winreg.QueryValueEx(key, "Path")
        except FileNotFoundError:
            current, kind = "", winreg.REG_EXPAND_SZ
        if str(folder).lower() not in current.lower().split(";"):
            winreg.SetValueEx(key, "Path", 0, kind, (current.rstrip(";") + ";" + str(folder)).lstrip(";"))
            info("  added %s to your PATH (new terminals will see it)" % folder)


def install_shell(m, os_name, de):
    if os_name == "windows":
        block = '$env:CAIN_DIR = "%s"\nif (Test-Path "$HOME\\.config\\cain\\cain.ps1") { . "$HOME\\.config\\cain\\cain.ps1" }' % ROOT
        profiles = set()
        for shell in ("powershell", "pwsh"):
            if util.which(shell):
                p = util.output([shell, "-NoProfile", "-Command", "$PROFILE"]).strip()
                if p:
                    profiles.add(p)
        for p in profiles:
            util.upsert_block(p, block)
        # Windows refuses to run profile scripts until this is relaxed for the user.
        run(["powershell", "-NoProfile", "-Command",
             "Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force"])
        return
    block = ('export CAIN_DIR="%s"\n'
             'case ":$PATH:" in *":$HOME/.local/bin:"*) ;; *) export PATH="$HOME/.local/bin:$PATH" ;; esac\n'
             '[ -f "$HOME/.config/cain/cain.sh" ] && . "$HOME/.config/cain/cain.sh"' % ROOT)
    rcs = [expand("~/.bashrc"), expand("~/.zshrc")]
    for rc in rcs:
        # macOS defaults to zsh, Linux to bash: always do bash, do zsh if it's in use.
        if rc.name == ".bashrc" or rc.exists() or os_name == "macos":
            util.upsert_block(rc, block)


def install_keys(m, os_name, de):
    remaps, shortcuts = m.remaps(os_name), m.shortcuts(os_name)
    if os_name == "linux":
        keyd.apply(remaps, packages.detect_linux_pm())
        linux_desktop.apply(de, shortcuts, m.settings)
    elif os_name == "windows":
        ahk.apply(remaps, shortcuts, m.settings)
    else:
        karabiner.apply(remaps, shortcuts, m.settings)


def install_desktop(m, os_name, de):
    desktop.apply(os_name, de, m.settings)


def install(m, steps):
    os_name, de = util.current_os(), util.linux_desktop()
    info("INSTALLING on %s%s" % (os_name, " (%s)" % de if de else ""))
    for name in steps:
        step(name)
        globals()["install_" + name](m, os_name, de)
    info("\nDone. Log out and back in (or reboot) so every change takes effect.")
    if "keys" in steps or "desktop" in steps:
        if util.ask("Reboot now?", default=False):
            if os_name == "windows":
                run(["shutdown", "/r", "/t", "0"])
            else:
                run(["reboot"], sudo=(os_name == "macos"))


# ------------------------------------------------------------------ collect

def collect(m):
    os_name, de = util.current_os(), util.linux_desktop()
    changed = []
    print("Files Changed:\n")

    def track(name, system, repo):
        if not system.exists():
            print("    MISSING: " + name)
        elif util.same_file(system, repo):
            print("    SAME: " + name)
        else:
            util.copy_file(system, repo)
            changed.append(name)
            print("    CHANGED: " + name)

    for f in m.files(os_name, de):
        track(f["dest"], expand(f["dest"]), ROOT / f["src"])
    for s in m.scripts(os_name):
        track(s["name"], bin_dir(os_name) / (s["name"] + (".py" if os_name == "windows" else "")),
              ROOT / s["src"])
    if de == "cinnamon":
        if desktop.collect_cinnamon_settings():
            changed.append("cinnamonSettings")
            print("    CHANGED: cinnamonSettings")
        else:
            print("    SAME: cinnamonSettings")

    if not changed:
        print("\nALL FILES ARE THE SAME\n")
        return
    git = ["git", "-C", str(ROOT)]
    run(git + ["add", "-A"])
    if util.ok(run(git + ["commit", "-m", "CHANGED: " + " ".join(changed)])):
        run(git + ["push"])


# ------------------------------------------------------------------ generate

def generate(m, os_name):
    remaps, shortcuts = m.remaps(os_name), m.shortcuts(os_name)
    if os_name == "linux":
        print("# ---- %s\n%s" % (keyd.CONFIG, keyd.generate(remaps)))
        print("# ---- desktop shortcuts (applied with gsettings / kwriteconfig / xfconf)")
        for sc, combos in shortcuts:
            print("#   %-30s %s" % (", ".join(map(str, combos)), sc["action"]))
    elif os_name == "windows":
        print(ahk.generate(remaps, shortcuts, m.settings))
    else:
        print(json.dumps(karabiner.generate(remaps, shortcuts, m.settings), indent=2))


# ------------------------------------------------------------------ CLI

def main():
    p = argparse.ArgumentParser(prog="cain", description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("command", nargs="?", help="collect, install, keys or generate")
    p.add_argument("args", nargs="*", help="install steps, or the OS for generate")
    p.add_argument("-c", "--collect", action="store_true", help="same as `cain collect`")
    p.add_argument("-i", "--install", action="store_true", help="same as `cain install`")
    p.add_argument("-n", "--dry-run", action="store_true", help="don't change anything")
    a = p.parse_args()
    util.DRY_RUN = a.dry_run

    command = a.command or ("collect" if a.collect else "install" if a.install else None)
    m = Manifest()

    if command == "generate":
        generate(m, a.args[0] if a.args else util.current_os())
        return

    print(ASCII)
    while command is None:
        choice = input("Would you like to Collect (C) or Install (I)?: ").strip().lower()
        command = {"c": "collect", "i": "install"}.get(choice)
        if command is None:
            print("\nNon valid input, please try again\n")

    if command in ("collect", "c"):
        collect(m)
    elif command in ("install", "i", "keys"):
        steps = a.args or (["keys"] if command == "keys" else STEPS)
        bad = [s for s in steps if s not in STEPS]
        if bad:
            p.error("unknown step(s) %s; choose from %s" % (", ".join(bad), ", ".join(STEPS)))
        install(m, steps)
    else:
        p.error("unknown command %r" % command)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print()
