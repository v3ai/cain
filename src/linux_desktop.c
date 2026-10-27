/* Window-manager shortcuts and app launchers for Linux desktops.
 *
 * Key *remaps* are done by keyd for every distro; the shortcuts here (close window,
 * open terminal, ...) belong to the desktop environment, so each one needs its own
 * backend. Supported: Cinnamon, GNOME (and GNOME-based: Ubuntu, Pop, Budgie), KDE
 * Plasma, XFCE. Anything else gets a printed list to set up by hand. */
#include "cain.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *action, *schema, *key; } Setting;

const char *linux_desktop(void)
{
    static const char *const names[][2] = {
        {"cinnamon", "cinnamon"}, {"kde", "kde"}, {"kde", "plasma"}, {"xfce", "xfce"},
        {"mate", "mate"}, {"gnome", "gnome"}, {"gnome", "ubuntu"}, {"gnome", "unity"},
        {"gnome", "pop"}, {"gnome", "budgie"}, {NULL, NULL},
    };
    const char *a = getenv("XDG_CURRENT_DESKTOP"), *b = getenv("DESKTOP_SESSION");
    char *raw = xprintf("%s:%s", a ? a : "", b ? b : ""), *low = str_lower(raw);
    const char *found = "";
    for (int i = 0; names[i][0] && !*found; i++)
        if (strstr(low, names[i][1])) found = names[i][0];
    free(raw);
    free(low);
    return found;
}

/* GVariant string / string list literals */
static char *gv_str(const char *s)
{
    char *esc = str_replace(s, "'", "\\'"), *r = xprintf("'%s'", esc);
    free(esc);
    return r;
}

static char *gv_list(const StrList *items)
{
    Buf b = {0};
    buf_addc(&b, '[');
    for (int i = 0; i < items->n; i++) {
        char *q = gv_str(items->v[i]);
        buf_addf(&b, "%s%s", i ? ", " : "", q);
        free(q);
    }
    buf_addc(&b, ']');
    return b.s;
}

static void gsettings(const char *schema, const char *key, const char *value)
{
    run(ARGV("gsettings", "set", schema, key, value), 0);
}

static StrList accels_of(const Shortcut *sc)
{
    StrList l = {0};
    for (int k = 0; k < sc->nkeys; k++) {
        char *a = gtk_accel(sc->keys[k]);
        sl_push(&l, a);
        free(a);
    }
    return l;
}

/* Existing custom-keybinding entries, minus the ones cain made earlier. */
static StrList custom_list(const char *schema, const char *key)
{
    StrList keep = {0};
    char *raw = output(ARGV("gsettings", "get", schema, key));
    if (!raw) return keep;
    for (char *p = strchr(raw, '\''); p; p = strchr(p, '\'')) {
        char *end = strchr(p + 1, '\'');
        if (!end) break;
        *end = 0;
        char *item = p + 1;
        size_t n = strlen(item);
        char *trimmed = xstrdup(item);
        while (n && trimmed[n - 1] == '/') trimmed[--n] = 0;
        if (!starts_with(path_base(trimmed), "cain")) sl_push(&keep, item);
        free(trimmed);
        p = end + 1;
    }
    free(raw);
    return keep;
}

static const Setting *find(const Setting *table, const char *action)
{
    for (; table->action; table++)
        if (streq(table->action, action)) return table;
    return NULL;
}

/* ---------------------------------------------------------------- GNOME */

static const Setting GNOME_WM[] = {
    {"close_window", "org.gnome.desktop.wm.keybindings", "close"},
    {"minimize", "org.gnome.desktop.wm.keybindings", "minimize"},
    {"toggle_maximize", "org.gnome.desktop.wm.keybindings", "toggle-maximized"},
    {"tile_left", "org.gnome.mutter.keybindings", "toggle-tiled-left"},
    {"tile_right", "org.gnome.mutter.keybindings", "toggle-tiled-right"},
    {"show_desktop", "org.gnome.desktop.wm.keybindings", "show-desktop"},
    {"switch_windows", "org.gnome.desktop.wm.keybindings", "switch-windows"},
    {"lock_screen", "org.gnome.settings-daemon.plugins.media-keys", "screensaver"},
    {NULL, NULL, NULL},
};

static void apply_gnome(const Manifest *m)
{
    const char *media = "org.gnome.settings-daemon.plugins.media-keys";
    const char *base = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/";
    StrList paths = custom_list(media, "custom-keybindings");
    int n = 0;
    for (int i = 0; i < m->nshortcuts; i++) {
        const Shortcut *sc = &m->shortcuts[i];
        StrList accels = accels_of(sc);
        const Setting *s = find(GNOME_WM, sc->action);
        if (s) {
            gsettings(s->schema, s->key, gv_list(&accels));
            if (streq(sc->action, "switch_windows")) {  /* free Alt+Tab from the app switcher */
                StrList super_tab = {0};
                sl_push(&super_tab, "<Super>Tab");
                gsettings("org.gnome.desktop.wm.keybindings", "switch-applications", gv_list(&super_tab));
            }
            continue;
        }
        char *cmd = launch_command(sc, "linux", m), *name = friendly(sc);
        if (!cmd) continue;  /* a "run" shortcut with no Linux command */
        for (int k = 0; k < accels.n; k++) {  /* GNOME custom shortcuts hold a single key each */
            char *path = xprintf("%scain%d/", base, n++);
            char *schema = xprintf("%s.custom-keybinding:%s", media, path);
            char *label = xprintf("cain %s", name);
            gsettings(schema, "name", gv_str(label));
            gsettings(schema, "command", gv_str(cmd));
            gsettings(schema, "binding", gv_str(accels.v[k]));
            sl_push(&paths, path);
            free(path);
            free(schema);
            free(label);
        }
        free(cmd);
        free(name);
    }
    gsettings(media, "custom-keybindings", gv_list(&paths));
}

/* ---------------------------------------------------------------- Cinnamon */

static const Setting CINNAMON_WM[] = {
    {"close_window", "org.cinnamon.desktop.keybindings.wm", "close"},
    {"minimize", "org.cinnamon.desktop.keybindings.wm", "minimize"},
    {"toggle_maximize", "org.cinnamon.desktop.keybindings.wm", "toggle-maximized"},
    {"tile_left", "org.cinnamon.desktop.keybindings.wm", "push-tile-left"},
    {"tile_right", "org.cinnamon.desktop.keybindings.wm", "push-tile-right"},
    {"show_desktop", "org.cinnamon.desktop.keybindings.wm", "show-desktop"},
    {"switch_windows", "org.cinnamon.desktop.keybindings.wm", "switch-windows"},
    {"lock_screen", "org.cinnamon.desktop.keybindings.media-keys", "screensaver"},
    {NULL, NULL, NULL},
};

static void apply_cinnamon(const Manifest *m)
{
    const char *root = "org.cinnamon.desktop.keybindings";
    const char *base = "/org/cinnamon/desktop/keybindings/custom-keybindings/";
    StrList names = custom_list(root, "custom-list");
    int n = 0;
    for (int i = 0; i < m->nshortcuts; i++) {
        const Shortcut *sc = &m->shortcuts[i];
        StrList accels = accels_of(sc);
        const Setting *s = find(CINNAMON_WM, sc->action);
        if (s) {
            gsettings(s->schema, s->key, gv_list(&accels));
            continue;
        }
        if (!launch_command(sc, "linux", m)) continue;
        char *name = xprintf("cain%d", n++);
        char *schema = xprintf("%s.custom-keybinding:%s%s/", root, base, name);
        char *label = friendly(sc), *cmd = launch_command(sc, "linux", m);
        gsettings(schema, "name", gv_str(label));
        gsettings(schema, "command", gv_str(cmd));
        gsettings(schema, "binding", gv_list(&accels));
        sl_push(&names, name);
        free(name);
        free(schema);
        free(label);
        free(cmd);
    }
    gsettings(root, "custom-list", gv_list(&names));
}

/* ---------------------------------------------------------------- XFCE */

static const Setting XFCE_WM[] = {
    {"close_window", NULL, "close_window_key"}, {"minimize", NULL, "hide_window_key"},
    {"toggle_maximize", NULL, "maximize_window_key"}, {"tile_left", NULL, "tile_left_key"},
    {"tile_right", NULL, "tile_right_key"}, {"show_desktop", NULL, "show_desktop_key"},
    {"switch_windows", NULL, "cycle_windows_key"}, {NULL, NULL, NULL},
};

static void xfconf(const char *prop, const char *value)
{
    run(ARGV("xfconf-query", "-c", "xfce4-keyboard-shortcuts", "-p", prop, "-n", "-t", "string", "-s", value), 0);
}

static void apply_xfce(const Manifest *m)
{
    for (int i = 0; i < m->nshortcuts; i++) {
        const Shortcut *sc = &m->shortcuts[i];
        StrList accels = accels_of(sc);
        const Setting *s = find(XFCE_WM, sc->action);
        char *cmd = s || streq(sc->action, "lock_screen") ? NULL : launch_command(sc, "linux", m);
        if (!s && !cmd && !streq(sc->action, "lock_screen")) continue;
        for (int k = 0; k < accels.n; k++) {
            char *prop = xprintf("%s%s", s ? "/xfwm4/custom/" : "/commands/custom/", accels.v[k]);
            xfconf(prop, s ? s->key : cmd ? cmd : "xflock4");
            free(prop);
        }
        free(cmd);
    }
}

/* ---------------------------------------------------------------- KDE Plasma */

static const Setting KDE_WM[] = {
    {"close_window", "kwin", "Window Close"},
    {"minimize", "kwin", "Window Minimize"},
    {"toggle_maximize", "kwin", "Window Maximize"},
    {"tile_left", "kwin", "Window Quick Tile Left"},
    {"tile_right", "kwin", "Window Quick Tile Right"},
    {"show_desktop", "kwin", "Show Desktop"},
    {"switch_windows", "kwin", "Walk Through Windows"},
    {"lock_screen", "ksmserver", "Lock Session"},
    {NULL, NULL, NULL},
};

static void kwrite(const char *tool, const char *g1, const char *g2, const char *key, const char *value)
{
    if (g2) run(ARGV(tool, "--file", "kglobalshortcutsrc", "--group", g1, "--group", g2, "--key", key, value), 0);
    else run(ARGV(tool, "--file", "kglobalshortcutsrc", "--group", g1, "--key", key, value), 0);
}

static void apply_kde(const Manifest *m)
{
    char *tool = which("kwriteconfig6");
    int plasma6 = tool != NULL;
    if (!tool) tool = which("kwriteconfig5");
    if (!tool) {
        warn("kwriteconfig6/5 not found; can't set KDE shortcuts");
        return;
    }
    for (int i = 0; i < m->nshortcuts; i++) {
        const Shortcut *sc = &m->shortcuts[i];
        Buf accels = {0};
        for (int k = 0; k < sc->nkeys; k++) {
            char *a = kde_accel(sc->keys[k]);
            buf_addf(&accels, "%s%s", k ? "\t" : "", a);
            free(a);
        }
        /* the kwin values are KConfig lists "active,default,name": escape commas in keys */
        char *escaped = str_replace(buf_str(&accels), ",", "\\,");
        const Setting *s = find(KDE_WM, sc->action);
        if (s) {
            char *v = xprintf("%s,none,%s", escaped, s->key);
            kwrite(tool, s->schema, NULL, s->key, v);
            free(v);
        } else if (launch_command(sc, "linux", m)) {
            char *act = str_replace(sc->action, ":", "-");
            char *id = xprintf("cain-%s.desktop", act), *rel = xprintf("~/.local/share/applications/%s", id);
            char *path = expand(rel), *name = friendly(sc), *cmd = launch_command(sc, "linux", m);
            char *desktop = xprintf("[Desktop Entry]\nType=Application\nName=cain %s\nExec=%s\nNoDisplay=true\n", name, cmd);
            write_text(path, desktop, 0);
            if (plasma6) {
                kwrite(tool, "services", id, "_launch", buf_str(&accels));
            } else {
                char *v = xprintf("%s,none,%s", escaped, name);
                kwrite(tool, id, NULL, "_launch", v);
                free(v);
            }
            free(act); free(id); free(rel); free(path); free(name); free(cmd); free(desktop);
        }
        free(escaped);
    }
    info("  KDE picks up new global shortcuts after you log out and back in.");
}

/* ---------------------------------------------------------------- */

void linux_desktop_apply(const char *desktop, const Manifest *m)
{
    if (streq(desktop, "gnome")) apply_gnome(m);
    else if (streq(desktop, "cinnamon")) apply_cinnamon(m);
    else if (streq(desktop, "xfce")) apply_xfce(m);
    else if (streq(desktop, "kde")) apply_kde(m);
    else {
        warn("don't know how to set shortcuts on this desktop ('%s'). Set these up by hand:",
             *desktop ? desktop : "unknown");
        for (int i = 0; i < m->nshortcuts; i++) {
            const Shortcut *sc = &m->shortcuts[i];
            Buf keys = {0};
            for (int k = 0; k < sc->nkeys; k++) {
                char *cs = combo_str(sc->keys[k]);
                buf_addf(&keys, "%s%s", k ? ", " : "", cs);
                free(cs);
            }
            char *cmd = launch_command(sc, "linux", m);
            info("    %-28s %-18s %s", buf_str(&keys), sc->action,
                 cmd ? cmd : is_wm_action(sc->action) ? "(window manager action)" : "(no Linux command)");
            free(cmd);
        }
    }
}
