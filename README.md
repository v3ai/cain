```
                         db

      ,p6"bo   ,6"Yb.  `7MM  `7MMpMMMb.
     6M'  OO  8)   MM    MM    MM    MM
     8M        ,pm9MM    MM    MM    MM
     YM.    , 8M   MM    MM    MM    MM
      YMbmd'  `Moo9^Yo..JMML..JMML  JMML.
```

## Collects And INstalls

cain is my dotfiles / keybindings / programs manager. It works on **any Linux
distro, macOS and Windows**. If you install it, your configs and keys become mine.

Everything lives in one file, [`cain.json`](cain.json):

| section     | what it is                                                        |
|-------------|-------------------------------------------------------------------|
| `packages`  | programs to install (apt/dnf/pacman/zypper/apk/xbps, brew, winget) |
| `files`     | dotfiles copied between `files/` and your home folder              |
| `scripts`   | little tools (booklister, listlauncher) put on your `PATH`         |
| `remaps`    | key remaps, e.g. `alt+h -> left`, `capslock -> esc`                |
| `shortcuts` | desktop shortcuts, e.g. `alt+comma` closes a window, `alt+t` opens a terminal |
| `settings`  | wallpaper, dark mode, Mac key behavior                            |

Write keys once, in a neutral format (`alt`, `lalt`, `ralt`, `ctrl`, `rctrl`, `shift`, `super`
+ a key name: see the top of [`cainlib/keys.py`](cainlib/keys.py)). cain turns them into
whatever each OS needs:

| OS      | key remaps                                     | shortcuts                                                  |
|---------|------------------------------------------------|------------------------------------------------------------|
| Linux   | [keyd](https://github.com/rvaiya/keyd) (`/etc/keyd/default.conf`). Works on X11 and Wayland | Cinnamon, GNOME, KDE Plasma, XFCE settings |
| Windows | AutoHotkey v2 script in your Startup folder    | same script                                                |
| macOS   | Karabiner-Elements rules                       | same rules                                                 |

### Requirements

Python 3.7+ and git.
* Linux: already installed on almost every distro.
* macOS: `xcode-select --install`.
* Windows: `winget install Python.Python.3.12 Git.Git`.

### Install

Linux / macOS:
```
cd && git clone https://github.com/v3ai/cain && cd cain && ./cain -i
```

Windows (PowerShell):
```
cd ~; git clone https://github.com/v3ai/cain; cd cain; .\cain.cmd -i
```

After that, open a new terminal and just type `cain`. The cain folder can live anywhere.

### Usage

```
cain                  asks: Collect (C) or Install (I)?
cain -c               collect: copy this machine's configs into the repo, commit, push
cain -i               install everything
cain install keys     only some steps: packages git files scripts shell keys desktop
cain keys             re-apply keybindings after editing cain.json
cain generate macos   print the keyd / AutoHotkey / Karabiner config for any OS
cain -i --dry-run     show what would happen without changing anything
```

Files that install overwrites are backed up to `~/.cain-backup/<date>/` first.

### Per-OS notes

* **Linux:** keyd needs sudo once to install. If your distro doesn't package it, cain
  builds it from source. If input-remapper is running, cain offers to turn it off so
  keys aren't remapped twice. On Cinnamon, `cain -c` also saves the whole `dconf`
  dump (theme, panels, ...), and install loads it back.
* **Windows:** the AutoHotkey script is at
  `%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup\cain.ahk`. Shell aliases go
  in your PowerShell profile (`files/shell/cain.ps1`).
* **macOS:** the first time, open Karabiner-Elements and allow it in System Settings >
  Privacy & Security. With `"mac_translate": true`, outputs become Mac-style:
  `ctrl+c -> cmd+c`, `ctrl+left -> option+left`, `home -> cmd+left`.
  `"mac_alt": "option"` uses the Option key as your Alt. Set it to `"command"` to use
  the key under your thumb instead.
* Any remap can be overridden per OS: `{"from": "lalt+v", "to": "ctrl+shift+v", "macos": "cmd+v"}`.
  Use `null` to skip it on that OS. Any entry can be limited with `"os": ["linux"]`.

### Shell

`files/shell/cain.sh` (bash and zsh) and `files/shell/cain.ps1` (PowerShell) hold my
aliases and functions. `install`, `update`, `upgrade` and the rest use whatever package
manager the machine has. cain adds a small `# >>> cain >>>` block to `~/.bashrc` /
`~/.zshrc` / `$PROFILE` that loads them. Edit them with `rc`.

MIT licensed, check the dotfiles for ideas.
ASCII art made with `figlet -f Georgia11.flf cain`.
