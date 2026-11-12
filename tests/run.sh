#!/bin/sh
# Regression tests: `make test`.
# Checks the generated configs against tests/expected/ and a few error cases.
# After an intended change to cain.json or the generators, refresh with:
#   UPDATE=1 sh tests/run.sh
cd "$(dirname "$0")/.." || exit 1
export HOME=/home/cain-test CAIN_DIR=.
fail=0

for os in linux windows macos; do
    if [ -n "$UPDATE" ]; then
        ./cain generate $os > tests/expected/$os.txt
    elif ./cain generate $os | diff -u tests/expected/$os.txt - > /tmp/cain-test.diff; then
        echo "ok    generate $os"
    else
        echo "FAIL  generate $os"; cat /tmp/cain-test.diff; fail=1
    fi
done

expect_error() {  # expect_error <description> <message> <cain.json> <args...>
    desc=$1 msg=$2 json=$3; shift 3
    dir=$(mktemp -d)
    printf '%s' "$json" > "$dir/cain.json"
    if CAIN_DIR=$dir ./cain "$@" 2>&1 | grep -q "$msg"; then echo "ok    $desc"
    else echo "FAIL  $desc (wanted: $msg)"; fail=1; fi
    rm -rf "$dir"
}
expect_error "bad key combo"   "alt+nope"             '{"remaps": [{"from": "alt+nope", "to": "left"}]}' generate linux
expect_error "broken JSON"     "line 2"               '{"remaps": [
}' generate linux
expect_error "unknown action"  "unknown shortcut"     '{"shortcuts": [{"action": "fly", "keys": ["alt+f"]}]}' generate windows
expect_error "unknown step"    "unknown install step" '{}' install nope


# install presets run exactly these steps (no menu: stdin isn't a terminal)
expect_steps() {  # expect_steps <args> <steps>
    got=$(./cain $1 --dry-run < /dev/null 2>&1 | sed -n 's/^== \(.*\) ==$/\1/p' | tr '\n' ' ')
    if [ "$got" = "$2 " ]; then echo "ok    cain $1"; else echo "FAIL  cain $1 (wanted: $2, got: $got)"; fail=1; fi
}
expect_steps "install light"         "git files bin shell keys"
expect_steps "install dotfiles"      "git files bin shell"
expect_steps "install keybindings"   "keys"
expect_steps "install dotfiles keys" "git files bin shell keys"
[ "$(uname -s)" = Linux ] && expect_steps "install server" "packages git files bin shell"

# `cain vps` (Linux only): terminal packages only, with the right name for each distro
expect_output() {  # expect_output <description> <pm> <wanted|!unwanted>...
    desc=$1 pm=$2; shift 2
    out=$(CAIN_PM=$pm ./cain vps packages --dry-run < /dev/null 2>&1)
    for want in "$@"; do
        case $want in
            !*) printf '%s\n' "$out" | grep -q -- "${want#!}" && { echo "FAIL  $desc (didn't want: ${want#!})"; fail=1; return; } ;;
            *)  printf '%s\n' "$out" | grep -q -- "$want" || { echo "FAIL  $desc (wanted: $want)"; fail=1; return; } ;;
        esac
    done
    echo "ok    $desc"
}
if [ "$(uname -s)" = Linux ]; then
    expect_error  "unknown vps step" "unknown vps step" '{}' vps keys
    expect_output "vps apt"    apt    "apt-get install -y python3-venv" "install -y openssh-client" "!inkscape" "!xclip" "!apk"
    expect_output "vps dnf"    dnf    "dnf install -y ffmpeg-free" "install -y openssh-clients" "install -y iproute\$" "!python3-venv"
    expect_output "vps pacman" pacman "pacman -Syu" "noconfirm python-pip" "noconfirm openssh" "!virt-manager"
    expect_output "vps apk"    apk    "apk add grep" "apk add shadow" "apk add py3-pip" "!python3-venv"
    expect_output "vps zypper" zypper "install micro-editor" "!install micro\$"
fi

exit $fail
