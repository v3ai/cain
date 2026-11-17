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

Server (just micro, git and my configs):
```
cd && sudo apt install git -y && git clone https://github.com/v3ai/cain && ~/cain/cain -i server
```

Install links `cain` into `~/.local/bin`, so after that just type `cain`. The repo can
live anywhere.

| part             | desktop | server | what it is |
|------------------|:-------:|:------:|------------|
| `programs`       | yes     |        | micro git xclip input-remapper inkscape virt-manager qemu-system suckless-tools |
| `server-programs`|         | yes    | micro git |
| `dotfiles`       | yes     | yes    | `~/.bashrc` |
| `micro`          | yes     | yes    | micro bindings and settings |
| `input-remapper` | yes     |        | input-remapper config and my keyboard preset; enables the daemon so the preset loads at boot |
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
