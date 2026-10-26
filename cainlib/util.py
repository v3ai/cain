"""Shared helpers: OS detection, command running, dry-run aware file writes."""

import os
import platform
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

DRY_RUN = False

ROOT = Path(__file__).resolve().parent.parent  # the cain repo, wherever it lives


def current_os():
    """Return 'linux', 'macos' or 'windows'."""
    s = platform.system()
    if s == "Darwin":
        return "macos"
    if s == "Windows":
        return "windows"
    return "linux"


def linux_desktop():
    """Best guess at the running Linux desktop: cinnamon, gnome, kde, xfce, mate or ''."""
    raw = (os.environ.get("XDG_CURRENT_DESKTOP", "") + ":" +
           os.environ.get("DESKTOP_SESSION", "")).lower()
    for name, needles in [("cinnamon", ["cinnamon"]),
                          ("kde", ["kde", "plasma"]),
                          ("xfce", ["xfce"]),
                          ("mate", ["mate"]),
                          ("gnome", ["gnome", "ubuntu", "unity", "pop", "budgie"])]:
        if any(n in raw for n in needles):
            return name
    return ""


def expand(path):
    return Path(os.path.expandvars(os.path.expanduser(path)))


def which(cmd):
    return shutil.which(cmd)


def info(msg):
    print(msg)


def warn(msg):
    print("  WARNING: " + msg)


def step(title):
    print("\n== " + title + " ==")


def run(cmd, sudo=False, check=False, capture=False, input=None, shell=False):
    """Run a command (list or string). Honors DRY_RUN. Returns CompletedProcess or None."""
    if sudo and current_os() != "windows" and os.geteuid() != 0:
        cmd = ["sudo"] + list(cmd) if not shell else "sudo " + cmd
    shown = cmd if isinstance(cmd, str) else " ".join(_quote(c) for c in cmd)
    if DRY_RUN:
        print("  [dry-run] " + shown)
        return None
    print("  $ " + shown)
    try:
        return subprocess.run(cmd, check=check, shell=shell, text=True, input=input,
                              stdout=subprocess.PIPE if capture else None,
                              stderr=subprocess.PIPE if capture else None)
    except FileNotFoundError as e:
        warn("command not found: %s" % e.filename)
        return None


def output(cmd):
    """Run a read-only command and return its stdout ('' on failure). Runs even in dry-run."""
    try:
        r = subprocess.run(cmd, text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        return r.stdout if r.returncode == 0 else ""
    except (FileNotFoundError, OSError):
        return ""


def ok(result):
    return result is None or result.returncode == 0  # None means dry-run


def _quote(s):
    import shlex
    return shlex.quote(str(s))


def write_text(path, content, sudo=False):
    """Write a file, creating parent dirs. With sudo, goes through `sudo tee`."""
    path = Path(path)
    if DRY_RUN:
        print("  [dry-run] write %s (%d bytes)" % (path, len(content)))
        return
    if sudo and current_os() != "windows" and os.geteuid() != 0:
        run(["mkdir", "-p", str(path.parent)], sudo=True)
        subprocess.run(["sudo", "tee", str(path)], input=content, text=True,
                       stdout=subprocess.DEVNULL, check=True)
        print("  wrote " + str(path))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n" if not str(path).endswith(".ahk") else None)
    print("  wrote " + str(path))


def copy_file(src, dest, backup_dir=None):
    """Copy src -> dest, backing up an existing, different dest first."""
    src, dest = Path(src), Path(dest)
    if dest.exists() and backup_dir is not None and not same_file(src, dest):
        target = Path(backup_dir) / dest.name
        if DRY_RUN:
            print("  [dry-run] backup %s -> %s" % (dest, target))
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(dest, target)
    if DRY_RUN:
        print("  [dry-run] copy %s -> %s" % (src, dest))
        return
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)


def same_file(a, b):
    import filecmp
    a, b = Path(a), Path(b)
    return a.exists() and b.exists() and filecmp.cmp(a, b, shallow=False)


def upsert_block(path, block, comment="#"):
    """Insert or replace a '>>> cain >>>' managed block in a text file (e.g. ~/.bashrc)."""
    start, end = comment + " >>> cain >>>", comment + " <<< cain <<<"
    path = Path(path)
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    new_block = start + "\n" + block.rstrip("\n") + "\n" + end + "\n"
    if start in text and end in text:
        before, rest = text.split(start, 1)
        after = rest.split(end, 1)[1].lstrip("\n")
        text = before + new_block + after
    else:
        text = text + ("\n" if text and not text.endswith("\n") else "") + "\n" + new_block
    write_text(path, text)


def ask(question, default=True):
    if DRY_RUN or not sys.stdin.isatty():
        return default
    suffix = " [Y/n]: " if default else " [y/N]: "
    answer = input(question + suffix).strip().lower()
    return default if not answer else answer.startswith("y")


def tmpdir():
    return Path(tempfile.mkdtemp(prefix="cain-"))
