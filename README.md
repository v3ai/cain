```
                         db

      ,p6"bo   ,6"Yb.  `7MM  `7MMpMMMb.
     6M'  OO  8)   MM    MM    MM    MM
     8M        ,pm9MM    MM    MM    MM
     YM.    , 8M   MM    MM    MM    MM
      YMbmd'  `Moo9^Yo..JMML..JMML  JMML.
```

## Collects And INstalls

cain is my dotfiles / system files manager and installer. If you install it, your
configs become mine.

I made cain because I was having a hard time keeping track of and updating separate
repositories for every config.

`cain` is a single POSIX shell script: no Python, no compiler, it runs with whatever
`/bin/sh` the machine has.

### Install

Desktop (Linux Mint / Cinnamon):
```
cd && sudo apt install git -y && git clone https://github.com/v3ai/cain && ~/cain/cain -i desktop
```

Server (just micro, git and my configs, including Claude Code's):
```
cd && sudo apt install git -y && git clone https://github.com/v3ai/cain && ~/cain/cain -i server
```

Install links `cain` into `~/.local/bin`, so after that just type `cain`. The repo can
live anywhere.

| part             | desktop | server | what it is |
|------------------|:-------:|:------:|------------|
| `programs`       | yes     |        | micro git xclip kitty make gawk input-remapper inkscape virt-manager qemu-system suckless-tools |
| `server-programs`|         | yes    | micro git |
| `dotfiles`       | yes     | yes    | `~/.bashrc` |
| `micro`          | yes     | yes    | micro bindings and settings |
| `claude`         | yes     | yes    | Claude Code config: `~/.claude/CLAUDE.md` and `~/.claude/settings.json` |
| `input-remapper` | yes     |        | input-remapper config and my keyboard preset; enables the daemon so the preset loads at boot |
| `terminal`       | yes     |        | kitty as the default terminal (with the GNOME Terminal icon), kitty config, fast-start launchers in `~/.local/bin`, and ble.sh so the bash prompt has Alt+Shift+hjkl selection and Ctrl+C copy (`~/.blerc`) |
| `background`     | yes     |        | pictures in `files/backgrounds/`, copied to `~/.local/share/backgrounds/cain/` and set as the wallpaper |
| `cinnamon`       | yes     |        | Cinnamon settings (dconf) and panel applet settings |

### Usage

```
cain                       asks: Collect (C) or Install (I)?
cain -c                    collect this machine's configs into the repo, commit, push
cain -i desktop            install everything for a desktop
cain -i server             install everything for a server
cain -i cinnamon micro     install only some parts
cain -h                    help
```

`cain -c` collects the desktop parts if Cinnamon is installed, otherwise the server
parts; `cain -c server` / `cain -c desktop` picks one.

Install overwrites everything it manages completely: files are replaced, folders end
up exactly like the repo's (extra files are removed), and each dconf folder is wiped
before loading, so old settings don't linger. Whatever it replaces is backed up to
`~/.cain-backup/<date>/` first (including the old dconf settings).

### Adding things

Everything cain manages is listed at the top of the `cain` script, one line each:

```sh
    track micro      files/micro/bindings.json      ~/.config/micro/bindings.json
    setting cinnamon files/cinnamon/nemo.ini        /org/nemo/preferences/
```

`track` copies a file or folder, `setting` saves/loads a dconf folder. The first word is
the part it belongs to.

### Terminal

* kitty: Ctrl+C copies when text is selected (otherwise it's a normal ^C),
  Ctrl+V pastes, Ctrl+Shift+C always sends ^C.
* [ble.sh](https://github.com/akinomyoga/ble.sh) replaces bash's line editor so the prompt
  can select text: Alt+Shift+h/l select left/right, Alt+Shift+k/j select up/down a line,
  Ctrl+C copies the selection to the clipboard. Its colours and as-you-type suggestions are
  turned off in `~/.blerc`. It's built from git into `~/.local/share/blesh` the first time;
  update it later with `ble-update`. `.bashrc` only loads it if it's there, so servers are fine.
* The default terminal is `TERMINAL` in the script (Cinnamon's setting and
  `x-terminal-emulator`, which Alt+T opens).
* kitty shows the GNOME Terminal icon in Alt+Tab and the panel, from
  `~/.local/share/applications/kitty.desktop` and `~/.config/kitty/kitty.app.png`
  (`kitty.app-128.png` is the size X11 wants, so kitty doesn't warn about it).
* Looks like GNOME Terminal: block cursor and a `user@host: dir` window title (kitty's shell
  integration is told to leave both alone), and `ls` colours match because `.bashrc` turns
  bold colours into bright ones in kitty (GNOME's "bold is bright", which kitty doesn't have).
* Fast start (~1s down to ~0.2s):
  * `~/.local/bin/kitty` wraps the real kitty. kitty's Python runs with `-OO`, but Ubuntu
    ships no `*.opt-2.pyc` files and `/usr` isn't writable, so every launch recompiled ~200
    modules. The wrapper sets `PYTHONPYCACHEPREFIX` to `~/.cache/kitty/pycache` so they're
    cached (`kitty.conf` keeps it out of shells running inside kitty).
  * `~/.local/bin/kitty-window` opens the window in the already-running kitty
    (`--single-instance`). Alt+T and the Cinnamon default terminal use it
    (`TERMINAL_COMMAND` in the script). All those windows share one process.
  * ble.sh takes ~0.3s to load, so `.bashrc` prints a copy of the prompt first and ble.sh
    draws the real one over it (only when the prompt fits on one line; a wrapped one can't
    be handed over without flicker). If you change `PS1`, change `_early_ps1` at the top of
    `.bashrc` to match. `~/.blerc` sets the character widths so ble.sh doesn't probe the
    terminal (that made the prompt flicker), and `ble-attach` runs inside synchronized output.
* Tab completion works like stock bash, not ble.sh's menu (`~/.blerc`): Tab completes as far
  as it can and beeps if there's more than one match; a Tab that can't add anything lists the
  matches in columns above a new prompt, with readline's "Display all N possibilities?
  (y or n)" question for 100+ and its `--More--` pager. With `completion-ignore-case` it keeps
  the case you typed, and lines ble.sh leaves behind aren't greyed out.

### Cinnamon settings

* `files/cinnamon/*.ini` hold the dconf folders for Cinnamon, the GTK/window theme,
  gnome-terminal and Nemo, not the whole `dconf dump /`, so other apps' state (VM lists,
  wifi, window sizes) and your location stay out of the repo.
* Your home folder is saved as `@HOME@`, so it works for any user name.
* `files/cinnamon/spices/` holds every panel applet's settings (menu, pinned apps, ...).
  These go in before the dconf settings, so the panels come back with them.
* The wallpaper is set by the `background` part (`WALLPAPER` in the script).
* After loading, cain reads the settings back and lists any that did not stick.
* It works over ssh or from a TTY too; log in to Cinnamon afterwards.
* Log out and back in (or reboot) after installing.

MIT licensed, check the dotfiles for ideas.
ASCII art made with `figlet -f Georgia11.flf cain` (you may have to download that .flf file).
