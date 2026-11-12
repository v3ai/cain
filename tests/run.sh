#!/bin/sh
# Regression tests: `sh tests/run.sh`.
# Checks the generated configs against tests/expected/, error cases, the install
# presets, real installs into a throwaway home folder, and the desktop plans.
#   CAIN_SH=bash sh tests/run.sh    run cain with another shell (default: its #! line)
#   UPDATE=1 sh tests/run.sh        refresh tests/expected/ after an intended change
cd "$(dirname "$0")/.." || exit 1
export HOME=/home/cain-test CAIN_DIR=.
unset XDG_CURRENT_DESKTOP DESKTOP_SESSION CAIN_PM
CAIN="${CAIN_SH:+$CAIN_SH }./cain"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

ok() { echo "ok    $1"; }
# minimal images (Fedora, Arch, Rocky) have no diff or cmp
same() { if command -v cmp >/dev/null 2>&1; then cmp -s "$1" "$2"; else [ "$(cksum < "$1")" = "$(cksum < "$2")" ]; fi; }
bad() { echo "FAIL  $1"; fail=1; }

for os in linux windows macos; do
    if [ -n "${UPDATE:-}" ]; then
        $CAIN generate $os > tests/expected/$os.txt
    elif $CAIN generate $os > "$tmp/$os.txt" && same tests/expected/$os.txt "$tmp/$os.txt"; then
        ok "generate $os"
    else
        bad "generate $os"; diff -u tests/expected/$os.txt "$tmp/$os.txt" 2>/dev/null | head -40
    fi
done

expect_error() {  # expect_error <description> <message> <cain.json> <args...>
    desc=$1 msg=$2 json=$3; shift 3
    mkdir -p "$tmp/err"
    printf '%s' "$json" > "$tmp/err/cain.json"
    if CAIN_DIR=$tmp/err $CAIN "$@" < /dev/null 2>&1 | grep -q -- "$msg"; then ok "$desc"
    else bad "$desc (wanted: $msg)"; fi
}
expect_error "bad key combo"   "alt+nope"             '{"remaps": [{"from": "alt+nope", "to": "left"}]}' generate linux
expect_error "broken JSON"     "line 2"               '{"remaps": [
}' generate linux
expect_error "unknown action"  "unknown shortcut"     '{"shortcuts": [{"action": "fly", "keys": ["alt+f"]}]}' generate windows
expect_error "unknown step"    "unknown install step" '{}' install nope
expect_error "bad JSON stops install" "line 1" '{"git": }' install dotfiles

# install presets run exactly these steps (no menu: stdin isn't a terminal)
expect_steps() {  # expect_steps <args> <steps>
    got=$($CAIN $1 --dry-run < /dev/null 2>&1 | sed -n 's/^== \(.*\) ==$/\1/p' | tr '\n' ' ')
    if [ "$got" = "$2 " ]; then ok "cain $1"; else bad "cain $1 (wanted: $2, got: $got)"; fi
}
expect_steps "install light"         "git files bin shell keys"
expect_steps "install dotfiles"      "git files bin shell"
expect_steps "install keybindings"   "keys"
expect_steps "install dotfiles keys" "git files bin shell keys"
expect_steps "-i -y"                 "packages git files bin shell keys desktop"
# plain `cain`: installs on a machine it's never been set up on, asks once it has
expect_steps "" "packages git files bin shell keys desktop"
mkdir -p "$tmp/asks/.config/cain"; echo "$PWD" > "$tmp/asks/.config/cain/repo"
if HOME=$tmp/asks $CAIN --dry-run < /dev/null 2>&1 | grep -q "Collect (C) or Install (I)"; then ok "cain (already set up) asks"
else bad "cain (already set up) should ask install or collect"; fi

# a real install into a throwaway home: files, cain on PATH, the shell block
h=$tmp/home
mkdir -p "$h/.config/micro"
printf 'my own line\n' > "$h/.bashrc"
printf '{"old": true}\n' > "$h/.config/micro/settings.json"
run_real() { HOME=$h GIT_CONFIG_GLOBAL=$h/.gitconfig $CAIN install dotfiles < /dev/null > "$tmp/real.out" 2>&1; }
if run_real && same files/micro/settings.json "$h/.config/micro/settings.json"; then ok "install copies files"
else bad "install copies files"; cat "$tmp/real.out"; fi
if ls "$h"/.cain-backup/*/settings.json > /dev/null 2>&1; then ok "install backs up what it replaces"
else bad "install backs up what it replaces"; fi
if [ "$(readlink "$h/.local/bin/cain")" = "$PWD/cain" ]; then ok "install links cain onto PATH"
else bad "install links cain onto PATH"; fi
if [ "$(cat "$h/.config/cain/repo")" = "$PWD" ]; then ok "install remembers the repo"
else bad "install remembers the repo"; fi
run_real
if grep -q "SAME:      ~/.nanorc" "$tmp/real.out"; then ok "second install: SAME"; else bad "second install: SAME"; cat "$tmp/real.out"; fi
if [ "$(grep -c '>>> cain >>>' "$h/.bashrc")" = 1 ] && head -n 1 "$h/.bashrc" | grep -q "my own line"; then
    ok "shell block added once, the rest kept"
else
    bad "shell block added once, the rest kept"; cat "$h/.bashrc"
fi
if ! command -v git >/dev/null 2>&1; then
    ok "install sets git name (skipped: no git here)"
elif [ "$(HOME=$h GIT_CONFIG_GLOBAL=$h/.gitconfig git config --global user.name)" = "$(CAIN_KEY=git.name CAIN_JSON=cain.json awk -v mode=get -f lib/cain.awk)" ]; then
    ok "install sets git name"
else
    bad "install sets git name"
fi

# cain.sh loads even when ~/.bashrc already has aliases named like its functions
# (the old cain's `alias i="sudo apt install"` used to break it)
for sh in bash zsh; do
    command -v $sh > /dev/null 2>&1 || continue
    opt=; [ $sh = bash ] && opt="-O expand_aliases"   # as in an interactive shell
    if HOME=$h $sh $opt -c 'alias i="sudo apt install"; alias install=x; alias u=x; alias update=x; alias upgrade=x; alias a=x
                       . files/shell/cain.sh && type i' > "$tmp/alias.out" 2>&1 && grep -q function "$tmp/alias.out"; then
        ok "cain.sh loads over old aliases ($sh)"
    else
        bad "cain.sh loads over old aliases ($sh)"; cat "$tmp/alias.out"
    fi
done

# Karabiner: cain's rules go first, the user's own rules stay, old cain rules go
cat > "$tmp/karabiner.json" <<'EOF'
{"global": {"show_in_menu_bar": false}, "profiles": [
  {"name": "Other", "selected": false},
  {"name": "Mine", "selected": true, "complex_modifications": {"rules": [
    {"description": "cain: old rule", "manipulators": []},
    {"description": "my rule é", "manipulators": []}]}}]}
EOF
karabiner() { CAIN_JSON=cain.json CAIN_KARABINER=$1 LC_ALL=C awk -v mode=karabiner -v os=macos -f lib/cain.awk; }
karabiner "$tmp/karabiner.json" > "$tmp/k.out" 2>&1
if grep -q '"my rule \\u00e9"' "$tmp/k.out" && ! grep -q "old rule" "$tmp/k.out" &&
   grep -q '"show_in_menu_bar": false' "$tmp/k.out" && [ "$(grep -c '"description": "cain: ' "$tmp/k.out")" -gt 30 ]; then
    ok "karabiner merge"
else
    bad "karabiner merge"; head -20 "$tmp/k.out"
fi
printf '{"profiles": [' > "$tmp/broken.json"
if ! karabiner "$tmp/broken.json" > /dev/null 2> "$tmp/k.err" && grep -q "leaving it alone" "$tmp/k.err"; then
    ok "karabiner leaves broken JSON alone"
else
    bad "karabiner leaves broken JSON alone"
fi

# desktop shortcut plans: run them with stand-ins that print each command's exact arguments
plan() {
    CAIN_JSON=cain.json CAIN_DESKTOP=$1 CAIN_EXISTING=$2 CAIN_KDE_TOOL=$3 CAIN_PLASMA6=${4:-0} \
        CAIN_TERM=kitty CAIN_CALC=kcalc LC_ALL=C awk -v mode=desktop -v os=linux -f lib/cain.awk > "$tmp/plan"
    (
        run() { printf '%s|' "$@"; echo; }
        info() { echo "$*"; }
        warn() { echo "WARNING: $*"; }
        write_text() { echo "write $1"; printf '%s' "$2"; }
        . "$tmp/plan"
    )
}
expect_plan() {  # expect_plan <description> <plan output> <wanted line>...
    desc=$1 out=$2; shift 2
    for want in "$@"; do
        printf '%s\n' "$out" | grep -qxF -- "$want" || { bad "$desc (wanted: $want)"; printf '%s\n' "$out" | head -5; return; }
    done
    ok "$desc"
}
G=org.gnome.settings-daemon.plugins.media-keys
expect_plan "gnome plan" "$(plan gnome "['/org/x/mine/', '/org/x/cain3/']")" \
    "gsettings|set|org.gnome.desktop.wm.keybindings|close|['<Alt>comma']|" \
    "gsettings|set|org.gnome.desktop.wm.keybindings|switch-applications|['<Super>Tab']|" \
    "gsettings|set|$G.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain0/|command|'kitty'|" \
    "gsettings|set|$G.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain1/|binding|'<Alt>Return'|" \
    "gsettings|set|$G.custom-keybinding:/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain3/|command|'xdg-open https://www.google.com'|"
expect_plan "gnome keeps your own shortcuts" "$(plan gnome "['/org/x/mine/', '/org/x/cain3/']" | grep custom-keybindings\|\\[ )" \
    "gsettings|set|$G|custom-keybindings|['/org/x/mine/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain0/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain1/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain2/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain3/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain4/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain5/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain6/', '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/cain7/']|"
expect_plan "cinnamon plan" "$(plan cinnamon "['custom0', 'cain5']")" \
    "gsettings|set|org.cinnamon.desktop.keybindings.wm|push-tile-left|['<Alt>y']|" \
    "gsettings|set|org.cinnamon.desktop.keybindings.custom-keybinding:/org/cinnamon/desktop/keybindings/custom-keybindings/cain4/|binding|['<Primary>b', '<Super>b', '<Alt>g']|" \
    "gsettings|set|org.cinnamon.desktop.keybindings|custom-list|['custom0', 'cain0', 'cain1', 'cain2', 'cain3', 'cain4']|"
expect_plan "kde plan" "$(plan kde "" kwriteconfig6 1)" \
    "kwriteconfig6|--file|kglobalshortcutsrc|--group|kwin|--key|Window Close|Alt+\\,,none,Window Close|" \
    "kwriteconfig6|--file|kglobalshortcutsrc|--group|services|--group|cain-terminal.desktop|--key|_launch|Alt+T	Alt+Return|" \
    "write /home/cain-test/.local/share/applications/cain-tool-booklister.desktop" \
    "Exec=/home/cain-test/.local/bin/cain booklister"
expect_plan "kde 5 plan" "$(plan kde "" kwriteconfig5 0)" \
    "kwriteconfig5|--file|kglobalshortcutsrc|--group|cain-calculator.desktop|--key|_launch|Alt+7,none,calculator|"
expect_plan "xfce plan" "$(plan xfce)" \
    "xfconf-query|-c|xfce4-keyboard-shortcuts|-p|/xfwm4/custom/<Alt>comma|-n|-t|string|-s|close_window_key|" \
    "xfconf-query|-c|xfce4-keyboard-shortcuts|-p|/commands/custom/<Alt>1|-n|-t|string|-s|xflock4|"
expect_plan "unknown desktop" "$(plan "")" \
    "WARNING: don't know how to set shortcuts on this desktop ('unknown'). Set these up by hand:" \
    "    alt+t, alt+enter             terminal           kitty"

# `cain vps` (Linux only): terminal packages only, with the right name for each distro
expect_output() {  # expect_output <description> <pm> <wanted|!unwanted>...
    desc=$1 pm=$2; shift 2
    out=$(CAIN_PM=$pm $CAIN vps packages --dry-run < /dev/null 2>&1)
    for want in "$@"; do
        case $want in
            !*) printf '%s\n' "$out" | grep -q -- "${want#!}" && { bad "$desc (didn't want: ${want#!})"; return; } ;;
            *)  printf '%s\n' "$out" | grep -q -- "$want" || { bad "$desc (wanted: $want)"; return; } ;;
        esac
    done
    ok "$desc"
}
if [ "$(uname -s)" = Linux ]; then
    expect_steps "install server" "packages git files bin shell"
    expect_error  "unknown vps step" "unknown vps step" '{}' vps keys
    expect_output "vps apt"    apt    "apt-get install -y python3-venv" "install -y openssh-client" "!inkscape" "!xclip" "!apk"
    expect_output "vps dnf"    dnf    "dnf install -y ffmpeg-free" "install -y openssh-clients" "install -y iproute\$" "!python3-venv"
    expect_output "vps pacman" pacman "pacman -Syu" "noconfirm python-pip" "noconfirm openssh" "!virt-manager"
    expect_output "vps apk"    apk    "apk add grep" "apk add shadow" "apk add py3-pip" "!python3-venv"
    expect_output "vps zypper" zypper "install micro-editor" "!install micro\$"
fi

exit $fail
