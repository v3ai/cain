#!/usr/bin/env python3
"""Pick a book from ~/Desktop/books (or $CAIN_BOOKS_DIR) and open it.

Uses dmenu/rofi on Linux, a native list dialog on macOS, and a small
search-as-you-type window everywhere else.
"""

import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

BOOKS = Path(os.environ.get("CAIN_BOOKS_DIR", Path.home() / "Desktop" / "books"))


def open_file(path):
    system = platform.system()
    if system == "Windows":
        os.startfile(path)
    elif system == "Darwin":
        subprocess.Popen(["open", path])
    else:
        subprocess.Popen(["xdg-open", path])


def pick_dmenu(names):
    for cmd in (["dmenu", "-i", "-l", "25"], ["rofi", "-dmenu", "-i", "-l", "25"]):
        if shutil.which(cmd[0]):
            r = subprocess.run(cmd, input="\n".join(names), text=True, stdout=subprocess.PIPE)
            return r.stdout.strip()
    return None


def pick_macos(names):
    esc = lambda s: s.replace("\\", "\\\\").replace('"', '\\"')
    items = ", ".join('"%s"' % esc(n) for n in names)
    script = 'choose from list {%s} with title "Books" with prompt "Open which book?"' % items
    r = subprocess.run(["osascript", "-e", script], text=True, stdout=subprocess.PIPE)
    out = r.stdout.strip()
    return "" if out == "false" else out


def pick_tk(names):
    import tkinter as tk
    chosen = {"name": ""}
    root = tk.Tk()
    root.title("Books")
    entry = tk.Entry(root, width=70)
    entry.pack(fill="x")
    box = tk.Listbox(root, width=70, height=25)
    box.pack(fill="both", expand=True)

    def refresh(*_):
        q = entry.get().lower()
        box.delete(0, "end")
        for n in names:
            if all(part in n.lower() for part in q.split()):
                box.insert("end", n)
        if box.size():
            box.selection_set(0)

    def choose(*_):
        sel = box.curselection()
        if sel:
            chosen["name"] = box.get(sel[0])
        root.destroy()

    def move(delta):
        sel = box.curselection()
        i = max(0, min(box.size() - 1, (sel[0] if sel else 0) + delta))
        box.selection_clear(0, "end")
        box.selection_set(i)
        box.see(i)

    entry.bind("<KeyRelease>", lambda e: e.keysym not in ("Up", "Down", "Return") and refresh())
    entry.bind("<Return>", choose)
    entry.bind("<Down>", lambda e: move(1))
    entry.bind("<Up>", lambda e: move(-1))
    box.bind("<Double-Button-1>", choose)
    root.bind("<Escape>", lambda e: root.destroy())
    refresh()
    entry.focus_force()
    root.mainloop()
    return chosen["name"]


def pick_terminal(names):
    for i, n in enumerate(names, 1):
        print("%3d  %s" % (i, n))
    answer = input("book #: ").strip()
    return names[int(answer) - 1] if answer.isdigit() and 0 < int(answer) <= len(names) else ""


def main():
    if not BOOKS.is_dir():
        sys.exit("no books folder at %s (set CAIN_BOOKS_DIR to change it)" % BOOKS)
    files = {p.name: p for p in BOOKS.rglob("*") if p.is_file()}
    names = sorted(files, key=str.lower)

    choice = None
    if platform.system() == "Linux":
        choice = pick_dmenu(names)
    elif platform.system() == "Darwin":
        choice = pick_macos(names)
    if choice is None:
        try:
            choice = pick_tk(names)
        except Exception:  # no tkinter / no display
            choice = pick_terminal(names)

    if choice in files:
        open_file(str(files[choice]))


if __name__ == "__main__":
    main()
