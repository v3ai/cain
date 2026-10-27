/* Desktop look: wallpaper, dark mode, and (Cinnamon only) the full dconf settings dump. */
#include "cain.h"

#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#endif

static char *cinnamon_dump_path(void) { return path_join(g_root, "files/cinnamon/cinnamon-settings"); }

static char *copy_wallpaper(const Manifest *m)
{
    char *src = path_join(g_root, setting(m, "wallpaper", ""));
    if (!file_exists(src)) {
        warn("wallpaper %s not found", src);
        return NULL;
    }
    char *rel = xprintf("~/.config/cain/wallpaper%s", path_ext(src));
    char *dest = expand(rel);
    copy_file(src, dest, NULL);
    free(rel);
    free(src);
    return dest;
}

static void set_wallpaper(const char *os, const char *desktop, const Manifest *m)
{
    if (!*setting(m, "wallpaper", "")) return;
    char *path = copy_wallpaper(m);
    if (!path) return;
    char *uri = xprintf("'file://%s'", path);
    if (streq(os, "windows")) {
#ifdef _WIN32
        char *native = native_path(path);
        if (!g_dry_run)
            SystemParametersInfoA(SPI_SETDESKWALLPAPER, 0, native, SPIF_UPDATEINIFILE | SPIF_SENDCHANGE);
        free(native);
#endif
    } else if (streq(os, "macos")) {
        char *script = xprintf("tell application \"System Events\" to tell every desktop to set picture to \"%s\"", path);
        run(ARGV("osascript", "-e", script), 0);
        free(script);
    } else if (streq(desktop, "cinnamon")) {
        run(ARGV("gsettings", "set", "org.cinnamon.desktop.background", "picture-uri", uri), 0);
    } else if (streq(desktop, "gnome")) {
        run(ARGV("gsettings", "set", "org.gnome.desktop.background", "picture-uri", uri), 0);
        run(ARGV("gsettings", "set", "org.gnome.desktop.background", "picture-uri-dark", uri), 0);
    } else if (streq(desktop, "mate")) {
        run(ARGV("gsettings", "set", "org.mate.background", "picture-filename", path), 0);
    } else if (streq(desktop, "kde")) {
        run(ARGV("plasma-apply-wallpaperimage", path), 0);
    } else if (streq(desktop, "xfce")) {
        char *props = output(ARGV("xfconf-query", "-c", "xfce4-desktop", "-l"));
        for (char *p = props ? strtok(props, "\n") : NULL; p; p = strtok(NULL, "\n"))
            if (ends_with(p, "/last-image"))
                run(ARGV("xfconf-query", "-c", "xfce4-desktop", "-p", p, "-s", path), 0);
        free(props);
    } else {
        warn("don't know how to set the wallpaper here; it's at %s", path);
    }
    free(uri);
    free(path);
}

static void set_dark_mode(const char *os, const char *desktop, const Manifest *m)
{
    if (!json_bool(m->settings, "dark_mode", 0)) return;
    if (streq(os, "windows")) {
        if (g_dry_run) {
            info("  [dry-run] set AppsUseLightTheme/SystemUsesLightTheme = 0");
            return;
        }
#ifdef _WIN32
        HKEY key;
        DWORD zero = 0;
        if (RegCreateKeyExA(HKEY_CURRENT_USER, "Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
                            0, NULL, 0, KEY_SET_VALUE, NULL, &key, NULL) == ERROR_SUCCESS) {
            RegSetValueExA(key, "AppsUseLightTheme", 0, REG_DWORD, (const BYTE *)&zero, sizeof zero);
            RegSetValueExA(key, "SystemUsesLightTheme", 0, REG_DWORD, (const BYTE *)&zero, sizeof zero);
            RegCloseKey(key);
        }
#endif
    } else if (streq(os, "macos")) {
        run(ARGV("osascript", "-e",
                 "tell application \"System Events\" to tell appearance preferences to set dark mode to true"), 0);
    } else if (streq(desktop, "gnome") || streq(desktop, "cinnamon")) {
        run(ARGV("gsettings", "set", "org.gnome.desktop.interface", "color-scheme", "prefer-dark"), 0);
    } else if (streq(desktop, "kde")) {
        run(ARGV("plasma-apply-colorscheme", "BreezeDark"), 0);
    } else if (streq(desktop, "xfce")) {
        run(ARGV("xfconf-query", "-c", "xsettings", "-p", "/Net/ThemeName", "-s", "Adwaita-dark"), 0);
    }
}

/* The saved dconf dump minus keybindings (cain.json owns those) and machine paths. */
static char *filtered_cinnamon_dump(const char *text)
{
    Buf out = {0};
    int skip = 0;
    const char *line = text;
    while (*line) {
        const char *nl = strchr(line, '\n');
        size_t len = nl ? (size_t)(nl - line) : strlen(line);
        if (line[0] == '[') skip = starts_with(line, "[org/cinnamon/desktop/keybindings");
        if (!skip && !starts_with(line, "picture-uri=")) {
            buf_addn(&out, line, len);
            buf_addc(&out, '\n');
        }
        line += len + (nl ? 1 : 0);
    }
    return out.s ? out.s : xstrdup("");
}

static void load_cinnamon_settings(void)
{
    char *path = cinnamon_dump_path(), *text = read_file(path, NULL), *dconf = which("dconf");
    if (text && dconf) {
        char *filtered = filtered_cinnamon_dump(text);
        run_input(ARGV("dconf", "load", "/"), 0, filtered);
        free(filtered);
    }
    free(text);
    free(dconf);
    free(path);
}

/* dconf dump into the repo. Returns 1 if it changed. */
int collect_cinnamon_settings(void)
{
    char *dump = output(ARGV("dconf", "dump", "/"));
    if (!dump || !*dump) return 0;
    char *path = cinnamon_dump_path(), *old = read_file(path, NULL);
    int changed = !old || strcmp(old, dump) != 0;
    if (changed) write_text(path, dump, 0);
    free(old);
    free(path);
    free(dump);
    return changed;
}

void desktop_apply(const char *os, const char *desktop, const Manifest *m)
{
    if (streq(os, "linux") && streq(desktop, "cinnamon")) load_cinnamon_settings();
    set_wallpaper(os, desktop, m);
    set_dark_mode(os, desktop, m);
}
