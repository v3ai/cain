```
                         db

      ,p6"bo   ,6"Yb.  `7MM  `7MMpMMMb.
     6M'  OO  8)   MM    MM    MM    MM
     8M        ,pm9MM    MM    MM    MM
     YM.    , 8M   MM    MM    MM    MM
      YMbmd'  `Moo9^Yo..JMML..JMML  JMML.
```

## Collects And INstalls

cain is my dotfiles / keybindings / programs manager. It works on **any Linux distro,
macOS and Windows** with nothing to install or build: on Linux and macOS it's a POSIX
`sh` script plus `awk`, which every system already has; on Windows it's a PowerShell
script, which comes with Windows. If you install it, your configs and keys become mine.

Everything lives in one file, [`files/cain.json`](files/cain.json):

| section     | what it is                                                        |
|-------------|-------------------------------------------------------------------|
| `packages`  | programs to install (apt/dnf/pacman/zypper/apk/xbps, brew, winget). `"terminal": true` ones also go on servers |
| `files`     | dotfiles copied between `files/` and your home folder              |
| `remaps`    | key remaps, e.g. `alt+h -> left`, `capslock -> esc`                |
| `shortcuts` | desktop shortcuts, e.g. `alt+comma` closes a window, `alt+t` opens a terminal |
| `settings`  | wallpaper, dark mode, Mac key behavior                            |

Write keys once, in a neutral format (`alt`, `lalt`, `ralt`, `ctrl`, `rctrl`, `shift`, `super`
+ a key name: see `init()` in [`files/cain/cain.awk`](files/cain/cain.awk)). cain turns them into whatever
each OS needs:

| OS      | key remaps                                     | shortcuts                                                  |
|---------|------------------------------------------------|------------------------------------------------------------|
| Linux   | [keyd](https://github.com/rvaiya/keyd) (`/etc/keyd/default.conf`). Works on X11 and Wayland | Cinnamon, GNOME, KDE Plasma, XFCE settings |
| Windows | AutoHotkey v2 script in your Startup folder    | same script                                                |
| macOS   | Karabiner-Elements rules                       | same rules                                                 |

### Install

Linux / macOS:
```
cd && git clone https://github.com/v3ai/cain && cd cain && ./cain
```

Windows (PowerShell or Command Prompt):
```
cd ~; git clone https://github.com/v3ai/cain; cd cain; .\files\cain\cain.cmd
```

### VPS / server

On a fresh Linux server (Debian, Ubuntu, Fedora, Rocky/Alma/CentOS/RHEL, Arch, openSUSE,
Alpine, Void), as root or a sudo user:
```
curl -fsSL https://raw.githubusercontent.com/v3ai/cain/master/files/cain/vps.sh | sh
```
(no curl? `wget -qO- https://raw.githubusercontent.com/v3ai/cain/master/files/cain/vps.sh | sh`)

[`vps.sh`](files/cain/vps.sh) installs git if it's missing, clones cain to `~/cain` and runs
`cain vps`. That installs only what's used in the terminal and skips keybindings, desktop
settings and GUI apps:

* every package marked `"terminal": true` in `files/cain.json`: bash, sudo, curl, git, micro, nano,
  python3 + pip + venv, tree, nnn, fzf, nmap, ffmpeg, yt-dlp, ssh, ...
  with the right package name for each distro. On Rocky/Alma/CentOS/RHEL it turns on EPEL first.
  If a distro doesn't package something (e.g. micro or yt-dlp), its `"fallback"` command
  installs it into `~/.local/bin` instead.
* the dotfiles (micro, nano, `cain.sh`), git name/email, `cain` itself on your `PATH`
* the shell block in `~/.bashrc`, plus a line in `~/.profile` / `~/.bash_profile` so SSH logins
  load it. If your login shell isn't bash or zsh (Alpine's `ash`), cain switches it to bash.

Already cloned? `cd ~/cain && ./cain vps`. Re-running is safe.
Just some steps: `cain vps packages shell`.

Install links `cain` into `~/.local/bin` (on Windows, a small `cain.cmd`) and puts that on
your `PATH`. After that, open a new terminal and just type `cain`. The repo can live
anywhere: cain remembers where it is, and a `git pull` in the repo updates it.

### Usage

```
cain                  first run on a machine: install. After that: menu, Install or Collect
cain -c               collect: copy this machine's configs into the repo, commit, push
cain -i               menu: pick what to install (see below)
cain -i -y            install everything, no menu
cain install light    pick a preset without the menu: full light dotfiles keybindings server
cain install keys     only some steps: packages git files bin shell keys desktop
cain keys             re-apply keybindings after editing files/cain.json
cain generate macos   print the keyd / AutoHotkey / Karabiner config for any OS
cain vps              set up a Linux server: terminal programs, configs, shell (no desktop)
cain -i --dry-run     show what would happen without changing anything
cain booklister       pick a book from ~/Desktop/books and open it ($CAIN_BOOKS_DIR to change)
cain listlauncher     edit list.html on the website, then commit and push ($CAIN_SITE_DIR)
```

`cain -i` opens a menu (arrow keys or j/k, Enter to pick, q to quit):

```
What should cain install?

 > Full         programs, dotfiles, keybindings and desktop settings
   Light        dotfiles and keybindings; no programs, no desktop changes
   Dotfiles     just configs, shell aliases and git settings
   Keybindings  just key remaps and shortcuts
   Server       terminal programs and dotfiles, nothing graphical   (Linux)
   Custom       tick each part yourself
```

Custom shows a checklist of the install steps (Space ticks, `a` toggles all). When cain isn't
run from a terminal (a script, CI) it skips the menu and installs everything, like `-y`.

Files that install overwrites are backed up to `~/.cain-backup/<date>/` first.

### Per-OS notes

* **Linux:** keyd needs sudo once to install. If your distro doesn't package it, cain
  builds it from source. If input-remapper is running, cain offers to turn it off so
  keys aren't remapped twice. On Cinnamon, `cain -c` also saves the whole `dconf`
  dump (theme, panels, ...), and install loads it back. booklister uses dmenu, rofi,
  fuzzel, wofi or zenity, whichever is installed.
* **Windows:** the first time, run `files\cain\cain.cmd` (it starts `cain.ps1` with the
  built-in PowerShell, so you don't have to change the execution policy first). After
  install, `cain` works from any terminal. The AutoHotkey script is at
  `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\cain.ahk`. Shell aliases go
  in your PowerShell profile (`files/shell/cain.ps1`). booklister opens a small
  search-as-you-type window.
* **macOS:** the first time, open Karabiner-Elements and allow it in System Settings >
  Privacy & Security. With `"mac_translate": true`, outputs become Mac-style:
  `ctrl+c -> cmd+c`, `ctrl+left -> option+left`, `home -> cmd+left`.
  `"mac_alt": "option"` uses the Option key as your Alt. Set it to `"command"` to use
  the key under your thumb instead.
* Any remap can be overridden per OS: `{"from": "lalt+v", "to": "ctrl+shift+v", "macos": "cmd+v"}`.
  Use `null` to skip it on that OS. Any entry can be limited with `"os": ["linux"]`.
* Packages: `{"name": "ssh", "apt": "openssh-client", "pacman": "openssh"}` sets the name per
  package manager (`apt dnf yum pacman zypper apk xbps brew winget`, or `linux` for all of them).
  `null` skips it there. `"fallback": "<shell command>"` runs if the package manager can't
  install it; `"bin"` is the command to look for if it isn't the same as `name`.
  `CAIN_PM=apk cain vps -n` shows what a distro would get.
* Shortcuts can run anything: `{"action": "editor", "keys": ["alt+e"], "run": {"linux": "kate", "windows": "notepad.exe"}}`.

### Shell

`files/shell/cain.sh` (bash and zsh) and `files/shell/cain.ps1` (PowerShell) hold my
aliases and functions. `install`, `update`, `upgrade` and the rest use whatever package
manager the machine has. cain adds a small `# >>> cain >>>` block to `~/.bashrc` /
`~/.zshrc` / `$PROFILE` that loads them. Edit them with `rc`.

### Hacking

The repo keeps to three things at the top: `cain` (the command), `files/` and this README.

```
files/cain.json        the config: packages, files, remaps, shortcuts, settings
files/cain/cain.awk    reads cain.json (it has a small JSON parser) and turns it into the
                       keyd / AutoHotkey / Karabiner configs, package and file lists, and
                       the desktop shortcut commands. POSIX awk (mawk, gawk, busybox, macOS awk)
files/cain/cain.ps1    the Windows version, PowerShell 5.1+ (cain.cmd starts it)
files/cain/vps.sh      sets up a fresh server
files/cain/tests/      the tests
files/...              the dotfiles themselves
```

`cain` itself is POSIX `sh` (dash, bash, busybox, ksh, zsh all work): menus, install
steps, running commands, dry-run.

```
sh files/cain/tests/run.sh               run the tests
CAIN_SH=bash sh files/cain/tests/run.sh  ...running cain with another shell
UPDATE=1 sh files/cain/tests/run.sh      refresh the expected outputs after an intended change
```

MIT licensed, check the dotfiles for ideas.
ASCII art made with `figlet -f Georgia11.flf cain`.
