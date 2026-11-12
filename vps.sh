#!/bin/sh
# Set up a fresh Linux server (VPS) with cain: terminal programs, configs and shell.
# Works on Debian, Ubuntu, Fedora, Rocky/Alma/CentOS/RHEL, Arch, openSUSE, Alpine and Void.
#
#   curl -fsSL https://raw.githubusercontent.com/v3ai/cain/master/vps.sh | sh
#   wget -qO- https://raw.githubusercontent.com/v3ai/cain/master/vps.sh | sh
#
# or, from a clone:  ./vps.sh
#
# It installs git if it's missing, clones cain to ~/cain (or $CAIN_DIR) and runs
# `cain vps`. Any arguments are passed on, e.g. `sh vps.sh --dry-run`.
set -e

REPO=${CAIN_REPO:-https://github.com/v3ai/cain}
BRANCH=${CAIN_BRANCH:-master}

say() { printf '\n== %s ==\n' "$*"; }
die() { printf 'vps.sh: %s\n' "$*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

if [ "$(id -u)" -eq 0 ]; then
    SUDO=
elif have sudo; then
    SUDO=sudo
else
    die "run this as root, or install sudo first"
fi

# ------------------------------------------------------------------ git
if ! have git; then
    say "installing git"
    if have apt-get; then
        $SUDO apt-get update
        $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y git ca-certificates
    elif have dnf; then
        $SUDO dnf install -y git
    elif have yum; then
        $SUDO yum install -y git
    elif have pacman; then
        $SUDO pacman -Syu --needed --noconfirm git
    elif have zypper; then
        $SUDO zypper --non-interactive install git
    elif have apk; then
        $SUDO apk add git
    elif have xbps-install; then
        $SUDO xbps-install -Sy git
    else
        die "no supported package manager (apt dnf yum pacman zypper apk xbps); install git yourself"
    fi
fi

# ------------------------------------------------------------------ get the repo
here=$(cd "$(dirname "$0")" 2>/dev/null && pwd || true)
if [ -n "$here" ] && [ -f "$here/cain.json" ] && [ -f "$here/lib/cain.awk" ]; then
    DIR=$here                                  # running ./vps.sh from a clone
else
    DIR=${CAIN_DIR:-$HOME/cain}
    if [ -d "$DIR/.git" ]; then
        say "updating $DIR"
        git -C "$DIR" pull --ff-only || echo "(couldn't update, using what's there)"
    else
        say "cloning $REPO into $DIR"
        git clone --branch "$BRANCH" "$REPO" "$DIR"
    fi
fi

# ------------------------------------------------------------------ run it
cd "$DIR"
# When piped from curl, stdin is this script: give cain the terminal so it can ask questions.
if (exec </dev/tty) 2>/dev/null; then
    exec sh ./cain vps "$@" </dev/tty
fi
exec sh ./cain vps "$@"
