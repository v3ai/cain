"""Installs programs with whatever package manager the machine has."""

from . import util
from .util import info, run, warn, which

LINUX_PMS = {
    "apt": ["apt-get", "install", "-y"],
    "dnf": ["dnf", "install", "-y"],
    "yum": ["yum", "install", "-y"],
    "pacman": ["pacman", "-S", "--needed", "--noconfirm"],
    "zypper": ["zypper", "--non-interactive", "install"],
    "apk": ["apk", "add"],
    "xbps": ["xbps-install", "-Sy"],
}
PM_BINARIES = {"apt": "apt-get", "xbps": "xbps-install"}

_refreshed = set()


def detect_linux_pm():
    for pm in LINUX_PMS:
        if which(PM_BINARIES.get(pm, pm)):
            return pm
    return None


def _refresh(pm):
    if pm in _refreshed:
        return
    _refreshed.add(pm)
    if pm == "apt":
        run(["apt-get", "update"], sudo=True)
    elif pm == "pacman":
        run(["pacman", "-Sy"], sudo=True)


def install_linux_packages(pm, names, quiet=False):
    if not pm:
        warn("no supported package manager found; install by hand: " + " ".join(names))
        return False
    _refresh(pm)
    all_ok = True
    for name in names:  # one at a time so one missing package doesn't sink the rest
        r = run(LINUX_PMS[pm] + [name], sudo=True, capture=quiet)
        if not util.ok(r):
            all_ok = False
            if not quiet:
                warn("couldn't install %s with %s" % (name, pm))
    return all_ok


def brew_install(names):
    if not which("brew"):
        if not util.ask("Homebrew isn't installed. Install it now?"):
            warn("skipping: " + " ".join(names))
            return
        run('/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"',
            shell=True)
    brew = which("brew") or "/opt/homebrew/bin/brew"
    for name in names:
        r = run([brew, "install"] + name.split())
        if not util.ok(r):
            warn("couldn't install " + name)


def winget_install(ids):
    if not which("winget"):
        warn("winget not found (it ships with Windows 10 21H2+/11 as 'App Installer'). "
             "Install by hand: " + " ".join(ids))
        return
    for pkg in ids:
        run(["winget", "install", "--id", pkg, "-e", "--silent",
             "--accept-source-agreements", "--accept-package-agreements"])


def install(manifest, os_name):
    pkgs = manifest.packages(os_name)
    if os_name == "linux":
        pm = detect_linux_pm()
        install_linux_packages(pm, [p.get(pm) or p.get("linux") or p["name"] for p in pkgs])
    elif os_name == "macos":
        brew_install([p.get("brew") or p["name"] for p in pkgs if p.get("brew", True)])
    else:
        missing = [p["name"] for p in pkgs if not p.get("winget")]
        if missing:
            info("  no winget id in cain.json for: " + ", ".join(missing) + " (skipped)")
        winget_install([p["winget"] for p in pkgs if p.get("winget")])
