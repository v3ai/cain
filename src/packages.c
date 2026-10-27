/* Installs programs with whatever package manager the machine has. */
#include "cain.h"

#include <stdlib.h>
#include <string.h>

typedef struct { const char *pm, *binary; const char *install[5]; } LinuxPM;

static const LinuxPM LINUX_PMS[] = {
    {"apt", "apt-get", {"apt-get", "install", "-y", NULL}},
    {"dnf", "dnf", {"dnf", "install", "-y", NULL}},
    {"yum", "yum", {"yum", "install", "-y", NULL}},
    {"pacman", "pacman", {"pacman", "-S", "--needed", "--noconfirm", NULL}},
    {"zypper", "zypper", {"zypper", "--non-interactive", "install", NULL}},
    {"apk", "apk", {"apk", "add", NULL}},
    {"xbps", "xbps-install", {"xbps-install", "-Sy", NULL}},
    {NULL, NULL, {NULL}},
};

const char *detect_linux_pm(void)
{
    for (int i = 0; LINUX_PMS[i].pm; i++) {
        char *p = which(LINUX_PMS[i].binary);
        if (p) {
            free(p);
            return LINUX_PMS[i].pm;
        }
    }
    return NULL;
}

static void refresh(const char *pm)
{
    static int done = 0;
    if (done) return;
    done = 1;
    if (streq(pm, "apt")) run(ARGV("apt-get", "update"), RUN_SUDO);
    else if (streq(pm, "pacman")) run(ARGV("pacman", "-Sy"), RUN_SUDO);
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
        const char *argv[8];
        int n = 0;
        while (p->install[n]) { argv[n] = p->install[n]; n++; }
        argv[n++] = names->v[i];
        argv[n] = NULL;
        if (run(argv, RUN_SUDO | (quiet ? RUN_QUIET : 0)) != 0) {
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

void packages_install(const Manifest *m, const char *os)
{
    Json *pkgs = json_get(m->root, "packages");
    StrList names = {0}, missing = {0};
    const char *pm = streq(os, "linux") ? detect_linux_pm() : NULL;
    for (int i = 0; pkgs && i < pkgs->n; i++) {
        Json *p = pkgs->items[i];
        if (!manifest_applies(p, os, "")) continue;
        const char *name = json_str(p, "name", NULL);
        if (!name) die("cain.json: every package needs a \"name\"");
        if (streq(os, "linux")) {
            sl_push(&names, json_str(p, pm ? pm : "", json_str(p, "linux", name)));
        } else if (streq(os, "macos")) {
            Json *b = json_get(p, "brew");
            if (b && b->t == J_NULL) continue;
            sl_push(&names, json_str(p, "brew", name));
        } else {
            const char *id = json_str(p, "winget", NULL);
            if (id) sl_push(&names, id);
            else sl_push(&missing, name);
        }
    }
    if (streq(os, "linux")) {
        install_linux_packages(pm, &names, 0);
    } else if (streq(os, "macos")) {
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
