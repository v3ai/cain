/* What each shortcut action means on each OS.
 *
 * Window-manager actions (close_window, minimize, ...) are handled natively by each
 * backend. Everything else is a *launch* action that boils down to a command line,
 * resolved here. "tool:booklister" runs `cain booklister`. */
#include "cain.h"

#include <stdlib.h>
#include <string.h>

static const char *const WM_ACTIONS[] = {
    "close_window", "minimize", "toggle_maximize", "tile_left", "tile_right",
    "show_desktop", "switch_windows", "lock_screen", NULL,
};

static const char *const LINUX_TERMINALS[] = {
    "x-terminal-emulator", "gnome-terminal", "konsole", "xfce4-terminal", "mate-terminal",
    "kitty", "alacritty", "wezterm", "foot", "tilix", "xterm", NULL,
};
static const char *const LINUX_CALCULATORS[] = {
    "gnome-calculator", "kcalc", "galculator", "mate-calc", "qalculate-gtk", "xcalc", NULL,
};

int is_wm_action(const char *action)
{
    for (int i = 0; WM_ACTIONS[i]; i++)
        if (streq(WM_ACTIONS[i], action)) return 1;
    return 0;
}

/* Where cain installs itself so shortcuts and shells can find it. */
char *bin_dir(const char *os)
{
    (void)os;
    return expand("~/.local/bin");
}

char *installed_exe(const char *os)
{
    char *dir = bin_dir(os);
    char *exe = path_join(dir, streq(os, "windows") ? "cain.exe" : "cain");
    char *native = streq(os, "windows") ? str_replace(exe, "/", "\\") : xstrdup(exe);
    free(dir);
    free(exe);
    return native;
}

static char *first_found(const char *const *cmds, const char *fallback)
{
    for (int i = 0; cmds[i]; i++) {
        char *p = which(cmds[i]);
        if (p) {
            free(p);
            return xstrdup(cmds[i]);
        }
    }
    return xstrdup(fallback);
}

/* The command line for a launch shortcut, or NULL for a window-manager action. */
char *launch_command(const Shortcut *sc, const char *os, const Manifest *m)
{
    const char *action = sc->action;
    if (is_wm_action(action)) return NULL;

    Json *run = json_get(sc->entry, "run");
    if (run) {
        if (run->t == J_STR) return xstrdup(run->str);
        const char *cmd = json_str(run, os, NULL);
        return cmd ? xstrdup(cmd) : NULL;
    }

    if (starts_with(action, "tool:")) {
        char *exe = installed_exe(os);
        char *cmd = streq(os, "windows") ? xprintf("\"%s\" %s", exe, action + 5)
                                         : xprintf("%s %s", shell_quote(exe), action + 5);
        free(exe);
        return cmd;
    }

    const char *url = setting(m, "homepage", "https://www.google.com");
    char *home = native_path(home_dir());
    char *cmd = NULL;
    if (streq(os, "linux")) {
        if (streq(action, "terminal")) cmd = first_found(LINUX_TERMINALS, "xterm");
        else if (streq(action, "calculator")) cmd = first_found(LINUX_CALCULATORS, "xcalc");
        else if (streq(action, "browser")) cmd = xprintf("xdg-open %s", shell_quote(url));
        else if (streq(action, "file_manager")) cmd = xprintf("xdg-open %s", shell_quote(home));
    } else if (streq(os, "macos")) {
        if (streq(action, "terminal")) cmd = xstrdup("open -a Terminal");
        else if (streq(action, "calculator")) cmd = xstrdup("open -a Calculator");
        else if (streq(action, "browser")) cmd = xprintf("open %s", shell_quote(url));
        else if (streq(action, "file_manager")) cmd = xprintf("open %s", shell_quote(home));
    } else {
        if (streq(action, "terminal")) cmd = xstrdup("wt.exe");
        else if (streq(action, "calculator")) cmd = xstrdup("calc.exe");
        else if (streq(action, "browser")) cmd = xstrdup(url);
        else if (streq(action, "file_manager")) cmd = xprintf("explorer.exe \"%s\"", home);
    }
    free(home);
    if (!cmd) die("cain.json: unknown shortcut action \"%s\" (give it a \"run\" command)", action);
    return cmd;
}

char *friendly(const Shortcut *sc)
{
    const char *name = json_str(sc->entry, "name", NULL);
    if (name) return xstrdup(name);
    const char *colon = strrchr(sc->action, ':');
    return str_replace(colon ? colon + 1 : sc->action, "_", " ");
}
