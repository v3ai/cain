/* Installs programs with whatever package manager the machine has. */
#include "cain.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *pm, *binary; const char *install[6]; } LinuxPM;

static const LinuxPM LINUX_PMS[] = {
    {"apt", "apt-get", {"env", "DEBIAN_FRONTEND=noninteractive", "apt-get", "install", "-y", NULL}},
    {"dnf", "dnf", {"dnf", "install", "-y", NULL}},
    {"yum", "yum", {"yum", "install", "-y", NULL}},
    {"pacman", "pacman", {"pacman", "-S", "--needed", "--noconfirm", NULL}},
    {"zypper", "zypper", {"zypper", "--non-interactive", "install", NULL}},
    {"apk", "apk", {"apk", "add", NULL}},
    {"xbps", "xbps-install", {"xbps-install", "-Sy", NULL}},
    {NULL, NULL, {NULL}},
};

/* $CAIN_PM forces one (e.g. CAIN_PM=apk for testing). */
const char *detect_linux_pm(void)
{
    const char *forced = getenv("CAIN_PM");
    if (forced && *forced) {
        for (int i = 0; LINUX_PMS[i].pm; i++)
            if (streq(LINUX_PMS[i].pm, forced)) return LINUX_PMS[i].pm;
        die("CAIN_PM=%s: pick one of apt dnf yum pacman zypper apk xbps", forced);
    }
    for (int i = 0; LINUX_PMS[i].pm; i++) {
        char *p = which(LINUX_PMS[i].binary);
        if (p) {
            free(p);
            return LINUX_PMS[i].pm;
        }
    }
    return NULL;
}

/* A field of /etc/os-release, lowercased ("" if missing). */
static char *os_release(const char *key)
{
    char *text = read_file("/etc/os-release", NULL);
    char *want = xprintf("%s=", key), *r = NULL;
    for (char *line = text; line && *line && !r;) {
        char *nl = strchr(line, '\n');
        if (nl) *nl = 0;
        if (starts_with(line, want)) {
            char *v = line + strlen(want);
            if (*v == '"' || *v == '\'') v++;
            v[strcspn(v, "\"'")] = 0;
            r = str_lower(v);
        }
        line = nl ? nl + 1 : NULL;
    }
    free(text);
    free(want);
    return r ? r : xstrdup("");
}

/* Rocky / Alma / CentOS / RHEL keep most terminal tools (nnn, fzf, yt-dlp...) in EPEL. */
static void enable_epel(const char *pm)
{
    char *id = os_release("ID"), *like = os_release("ID_LIKE"), *ver = os_release("VERSION_ID");
    int el = !streq(id, "fedora") && (strstr(id, "rhel") || strstr(id, "centos") || strstr(like, "rhel") || strstr(like, "centos"));
    char *rpm = which("rpm"), *have = rpm ? output(ARGV("rpm", "-q", "epel-release")) : NULL;
    if (el && rpm && !have) {
        info("  enabling EPEL (extra packages for %s)", id);
        if (run(ARGV(pm, "install", "-y", "epel-release"), RUN_SUDO) != 0) {
            ver[strcspn(ver, ".")] = 0;  /* "9.4" -> "9" */
            char *url = xprintf("https://dl.fedoraproject.org/pub/epel/epel-release-latest-%s.noarch.rpm", ver);
            run(ARGV(pm, "install", "-y", url), RUN_SUDO);
            free(url);
        }
    }
    char *crb = which("crb");  /* shipped by epel-release on EL9+: turns on the CodeReady Builder repo */
    if (el && (crb || g_dry_run)) run(ARGV("crb", "enable"), RUN_SUDO | RUN_QUIET);
    free(crb); free(rpm); free(have); free(id); free(like); free(ver);
}

static void refresh(const char *pm)
{
    static int done = 0;
    if (done) return;
    done = 1;
    if (streq(pm, "apt")) run(ARGV("apt-get", "update"), RUN_SUDO);
    else if (streq(pm, "pacman")) run(ARGV("pacman", "-Syu", "--noconfirm"), RUN_SUDO);  /* Arch doesn't support partial upgrades */
    else if (streq(pm, "apk")) run(ARGV("apk", "update"), RUN_SUDO);
    else if (streq(pm, "zypper")) run(ARGV("zypper", "--non-interactive", "refresh"), RUN_SUDO);
    else if (streq(pm, "dnf") || streq(pm, "yum")) enable_epel(pm);
}

/* Install one package; 0 on success. */
static int install_linux_package(const LinuxPM *p, const char *name, int quiet)
{
    const char *argv[10];
    int n = 0;
    while (p->install[n]) { argv[n] = p->install[n]; n++; }
    argv[n++] = name;
    argv[n] = NULL;
    return run(argv, RUN_SUDO | (quiet ? RUN_QUIET : 0));
}

int install_linux_packages(const char *pm, const StrList *names, int quiet)
{
    if (!pm) {
        Buf b = {0};
        for (int i = 0; i < names->n; i++) buf_addf(&b, " %s", names->v[i]);
        warn("no supported package manager found; install by hand:%s", buf_str(&b));
        return 0;
    }
    const LinuxPM *p = LINUX_PMS;
    while (!streq(p->pm, pm)) p++;
    refresh(pm);
    int all_ok = 1;
    for (int i = 0; i < names->n; i++) {  /* one at a time so one missing package doesn't sink the rest */
        if (install_linux_package(p, names->v[i], quiet) != 0) {
            all_ok = 0;
            if (!quiet) warn("couldn't install %s with %s", names->v[i], pm);
        }
    }
    return all_ok;
}

void brew_install(const StrList *names)
{
    char *brew = which("brew");
    if (!brew && file_exists("/opt/homebrew/bin/brew")) brew = xstrdup("/opt/homebrew/bin/brew");
    if (!brew && file_exists("/usr/local/bin/brew")) brew = xstrdup("/usr/local/bin/brew");
    if (!brew) {
        if (!ask("Homebrew isn't installed. Install it now?", 1)) {
            warn("skipping Homebrew packages");
            return;
        }
        run_shell("/bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"");
        brew = xstrdup(file_exists("/opt/homebrew/bin/brew") ? "/opt/homebrew/bin/brew" : "brew");
    }
    for (int i = 0; i < names->n; i++) {
        /* entries may carry flags, e.g. "--cask inkscape" */
        const char *argv[8] = {brew, "install"};
        int n = 2;
        char *copy = xstrdup(names->v[i]);
        for (char *t = strtok(copy, " "); t && n < 7; t = strtok(NULL, " ")) argv[n++] = t;
        argv[n] = NULL;
        if (run(argv, 0) != 0) warn("couldn't install %s", names->v[i]);
        free(copy);
    }
}

void winget_install(const StrList *ids)
{
    char *winget = which("winget");
    if (!winget && !g_dry_run) {
        Buf b = {0};
        for (int i = 0; i < ids->n; i++) buf_addf(&b, " %s", ids->v[i]);
        warn("winget not found (it ships with Windows 10 21H2+/11 as 'App Installer'). "
             "Install by hand:%s", buf_str(&b));
        return;
    }
    free(winget);
    for (int i = 0; i < ids->n; i++)
        run(ARGV("winget", "install", "--id", ids->v[i], "-e", "--silent",
                 "--accept-source-agreements", "--accept-package-agreements"), 0);
}

/* The Linux package name for an entry: its "<pm>" key, else "linux", else "name".
 * NULL when the entry says null for this package manager (skip it). */
static const char *linux_name(const Json *p, const char *pm)
{
    const char *keys[] = {pm, "linux", NULL};
    for (int k = 0; keys[k]; k++) {
        Json *v = keys[k] ? json_get(p, keys[k]) : NULL;
        if (v && v->t == J_NULL) return NULL;
        if (v && v->t == J_STR) return v->str;
    }
    return json_str(p, "name", NULL);
}

/* Linux: install each package; if that fails (or the distro doesn't have it) and the
 * entry has a "fallback" shell command, run that instead, e.g. a curl install into ~/.local/bin. */
static void linux_packages_install(const Manifest *m, int terminal_only)
{
    const char *pm = detect_linux_pm();
    Json *pkgs = json_get(m->root, "packages");
    const LinuxPM *p = LINUX_PMS;
    while (pm && !streq(p->pm, pm)) p++;
    if (pm) refresh(pm);
    StrList failed = {0};
    for (int i = 0; pkgs && i < pkgs->n; i++) {
        Json *e = pkgs->items[i];
        if (!manifest_applies(e, "linux", "")) continue;
        if (terminal_only && !json_bool(e, "terminal", 0)) continue;
        const char *name = json_str(e, "name", NULL);
        if (!name) die("cain.json: every package needs a \"name\"");
        const char *pkg = pm ? linux_name(e, pm) : NULL, *fallback = json_str(e, "fallback", NULL);
        const char *bin = json_str(e, "bin", name);
        if (pkg && install_linux_package(p, pkg, 0) == 0) continue;
        if (!pkg && !fallback) continue;  /* null for this distro and nothing else to try */
        char *have = which(bin);
        if (!have && fallback) {
            if (pkg) info("  %s isn't packaged here, installing it another way", name);
            /* look in ~/.local/bin too: it may not be on PATH until the next login */
            char *local = xprintf("~/.local/bin/%s", bin), *path = expand(local);
            if (run_shell(fallback) != 0 || (!g_dry_run && !file_exists(path) && !(have = which(bin))))
                sl_push(&failed, name);
            free(local);
            free(path);
        } else if (!have) {
            sl_push(&failed, name);
        }
        free(have);
    }
    if (!pm) warn("no supported package manager found (apt dnf yum pacman zypper apk xbps)");
    if (failed.n) {
        Buf b = {0};
        for (int i = 0; i < failed.n; i++) buf_addf(&b, " %s", failed.v[i]);
        warn("couldn't install:%s", buf_str(&b));
    }
}

void packages_install(const Manifest *m, const char *os, int terminal_only)
{
    if (streq(os, "linux")) {
        linux_packages_install(m, terminal_only);
        return;
    }
    Json *pkgs = json_get(m->root, "packages");
    StrList names = {0}, missing = {0};
    for (int i = 0; pkgs && i < pkgs->n; i++) {
        Json *p = pkgs->items[i];
        if (!manifest_applies(p, os, "")) continue;
        if (terminal_only && !json_bool(p, "terminal", 0)) continue;
        const char *name = json_str(p, "name", NULL);
        if (!name) die("cain.json: every package needs a \"name\"");
        if (streq(os, "macos")) {
            Json *b = json_get(p, "brew");
            if (b && b->t == J_NULL) continue;
            sl_push(&names, json_str(p, "brew", name));
        } else {
            const char *id = json_str(p, "winget", NULL);
            if (id) sl_push(&names, id);
            else sl_push(&missing, name);
        }
    }
    if (streq(os, "macos")) {
        brew_install(&names);
    } else {
        if (missing.n) {
            Buf b = {0};
            for (int i = 0; i < missing.n; i++) buf_addf(&b, "%s%s", i ? ", " : "", missing.v[i]);
            info("  no winget id in cain.json for: %s (skipped)", buf_str(&b));
        }
        winget_install(&names);
    }
}
