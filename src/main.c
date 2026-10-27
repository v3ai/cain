/* cain - Collects And INstalls dotfiles, keybindings and programs on Linux, macOS and Windows. */
#include "cain.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#else
#include <sys/stat.h>
#include <unistd.h>
#endif

static const char *USAGE =
    "usage: cain [command] [args...] [-n]\n"
    "\n"
    "  cain                 ask whether to collect or install\n"
    "  cain -c | collect    copy this machine's configs into the repo, commit and push\n"
    "  cain -i | install    install programs, configs, keybindings and desktop settings\n"
    "  cain install keys    run only some install steps:\n"
    "                       packages git files bin shell keys desktop\n"
    "  cain keys            shorthand for `cain install keys`\n"
    "  cain generate [os]   print the keybinding config cain would write for linux/macos/windows\n"
    "  cain booklister      pick a book from ~/Desktop/books and open it\n"
    "  cain listlauncher    edit list.html on the website, then commit and push\n"
    "  -n, --dry-run        show what would happen without changing anything\n";

static const char *ASCII =
    "\n"
    "                         db\n"
    "\n"
    "      ,p6\"bo   ,6\"Yb.  `7MM  `7MMpMMMb.\n"
    "     6M'  OO  8)   MM    MM    MM    MM\n"
    "     8M        ,pm9MM    MM    MM    MM\n"
    "     YM.    , 8M   MM    MM    MM    MM\n"
    "      YMbmd'  `Moo9^Yo..JMML..JMML  JMML.\n";

static const char *const STEPS[] = {"packages", "git", "files", "bin", "shell", "keys", "desktop", NULL};

/* ------------------------------------------------------------------ finding the repo */

static int has_manifest(const char *dir)
{
    char *p = path_join(dir, "cain.json");
    int ok = file_exists(p);
    free(p);
    return ok;
}

/* $CAIN_DIR, then the folder the cain binary sits in (it's built in the repo),
 * then the path `cain install` remembered, then the current directory. */
static char *find_root(void)
{
    const char *env = getenv("CAIN_DIR");
    if (env && has_manifest(env)) return xstrdup(env);
    char *exe = self_exe();
    if (exe) {
        char *dir = path_dir(exe);
        if (has_manifest(dir)) return dir;
        free(dir);
    }
    char *saved_path = expand("~/.config/cain/repo"), *saved = read_file(saved_path, NULL);
    if (saved) {
        saved[strcspn(saved, "\r\n")] = 0;
        if (has_manifest(saved)) return saved;
    }
    if (has_manifest(".")) return xstrdup(".");
    return NULL;
}

/* ------------------------------------------------------------------ install steps */

static void install_packages(const Manifest *m, const char *os, const char *de)
{
    (void)de;
    packages_install(m, os);
}

static void install_git(const Manifest *m, const char *os, const char *de)
{
    (void)os; (void)de;
    const char *name = json_str(m->git, "name", NULL), *email = json_str(m->git, "email", NULL);
    if (name) run(ARGV("git", "config", "--global", "user.name", name), 0);
    if (email) run(ARGV("git", "config", "--global", "user.email", email), 0);
}

static void install_files(const Manifest *m, const char *os, const char *de)
{
    char *ts = timestamp(), *rel = xprintf("~/.cain-backup/%s", ts), *backup = expand(rel);
    Json *files = json_get(m->root, "files");
    for (int i = 0; files && i < files->n; i++) {
        Json *f = files->items[i];
        if (!manifest_applies(f, os, de)) continue;
        const char *srel = json_str(f, "src", NULL), *drel = json_str(f, "dest", NULL);
        if (!srel || !drel) die("cain.json: every file needs \"src\" and \"dest\"");
        char *src = path_join(g_root, srel), *dest = expand(drel);
        if (same_file(src, dest)) {
            info("  SAME:      %s", drel);
        } else {
            copy_file(src, dest, backup);
            info("  INSTALLED: %s", drel);
        }
        free(src);
        free(dest);
    }
    if (is_dir(backup)) info("  (previous versions backed up in %s)", backup);
    free(ts); free(rel); free(backup);
}

#ifdef _WIN32
static void windows_add_to_path(const char *folder)
{
    if (g_dry_run) {
        info("  [dry-run] add %s to the user PATH", folder);
        return;
    }
    HKEY key;
    if (RegOpenKeyExA(HKEY_CURRENT_USER, "Environment", 0, KEY_ALL_ACCESS, &key) != ERROR_SUCCESS) return;
    char current[32767] = "";
    DWORD size = sizeof current, type = REG_EXPAND_SZ;
    RegQueryValueExA(key, "Path", NULL, &type, (BYTE *)current, &size);
    char *low = str_lower(current), *want = str_lower(folder), *padded = xprintf(";%s;", low);
    char *needle = xprintf(";%s;", want);
    if (!strstr(padded, needle)) {
        size_t n = strlen(current);
        while (n && current[n - 1] == ';') current[--n] = 0;
        char *value = n ? xprintf("%s;%s", current, folder) : xstrdup(folder);
        RegSetValueExA(key, "Path", 0, type == REG_SZ ? REG_SZ : REG_EXPAND_SZ, (const BYTE *)value, (DWORD)strlen(value) + 1);
        SendMessageTimeoutA(HWND_BROADCAST, WM_SETTINGCHANGE, 0, (LPARAM) "Environment", SMTO_ABORTIFHUNG, 2000, NULL);
        info("  added %s to your PATH (new terminals will see it)", folder);
        free(value);
    }
    RegCloseKey(key);
    free(low); free(want); free(padded); free(needle);
}
#endif

/* Put the cain binary on PATH (shortcuts call `cain booklister`) and remember the repo. */
static void install_bin(const Manifest *m, const char *os, const char *de)
{
    (void)m; (void)de;
    char *self = self_exe(), *dest = installed_exe(os), *dir = bin_dir(os);
    if (!self) {
        warn("can't tell where the cain binary is; copy it to %s yourself", dest);
    } else if (same_file(self, dest)) {
        info("  SAME:      %s", dest);
    } else {
        copy_file(self, dest, NULL);
#ifndef _WIN32
        if (!g_dry_run) chmod(dest, 0755);
#endif
        info("  INSTALLED: %s", dest);
    }
    char *repo = expand("~/.config/cain/repo"), *line = xprintf("%s\n", g_root);
    write_text(repo, line, 0);
#ifdef _WIN32
    char *native = native_path(dir);
    windows_add_to_path(native);
    free(native);
#endif
    free(self); free(dest); free(dir); free(repo); free(line);
}

static void install_shell(const Manifest *m, const char *os, const char *de)
{
    (void)m; (void)de;
    if (streq(os, "windows")) {
        const char *block = "if (Test-Path \"$HOME\\.config\\cain\\cain.ps1\") { . \"$HOME\\.config\\cain\\cain.ps1\" }";
        StrList profiles = {0};
        const char *shells[] = {"powershell", "pwsh", NULL};
        for (int i = 0; shells[i]; i++) {
            char *p = output(ARGV(shells[i], "-NoProfile", "-Command", "$PROFILE"));
            if (p) {
                p[strcspn(p, "\r\n")] = 0;
                if (*p && !sl_has(&profiles, p)) sl_push(&profiles, p);
            }
            free(p);
        }
        for (int i = 0; i < profiles.n; i++) upsert_block(profiles.v[i], block);
        /* Windows refuses to run profile scripts until this is relaxed for the user. */
        run(ARGV("powershell", "-NoProfile", "-Command", "Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force"), 0);
        return;
    }
    const char *block =
        "case \":$PATH:\" in *\":$HOME/.local/bin:\"*) ;; *) export PATH=\"$HOME/.local/bin:$PATH\" ;; esac\n"
        "[ -f \"$HOME/.config/cain/cain.sh\" ] && . \"$HOME/.config/cain/cain.sh\"";
    /* macOS defaults to zsh, Linux to bash: always do bash, do zsh if it's in use. */
    char *bashrc = expand("~/.bashrc"), *zshrc = expand("~/.zshrc");
    upsert_block(bashrc, block);
    if (file_exists(zshrc) || streq(os, "macos")) upsert_block(zshrc, block);
    free(bashrc);
    free(zshrc);
}

static void install_keys(const Manifest *m, const char *os, const char *de)
{
    if (streq(os, "linux")) {
        keyd_apply(m, detect_linux_pm());
        linux_desktop_apply(de, m);
    } else if (streq(os, "windows")) {
        ahk_apply(m);
    } else {
        karabiner_apply(m);
    }
}

static void install_desktop(const Manifest *m, const char *os, const char *de)
{
    desktop_apply(os, de, m);
}

typedef void (*StepFn)(const Manifest *, const char *, const char *);
static const StepFn STEP_FNS[] = {
    install_packages, install_git, install_files, install_bin, install_shell, install_keys, install_desktop,
};

static void install(const Manifest *m, const StrList *steps)
{
    const char *os = OS_NATIVE, *de = streq(os, "linux") ? linux_desktop() : "";
    if (*de) info("INSTALLING on %s (%s)", os, de);
    else info("INSTALLING on %s", os);
    int visual = 0;
    for (int i = 0; i < steps->n; i++) {
        for (int k = 0; STEPS[k]; k++)
            if (streq(STEPS[k], steps->v[i])) {
                step(STEPS[k]);
                STEP_FNS[k](m, os, de);
            }
        visual |= streq(steps->v[i], "keys") || streq(steps->v[i], "desktop");
    }
    info("\nDone. Log out and back in (or reboot) so every change takes effect.");
    if (visual && ask("Reboot now?", 0)) {
        if (streq(os, "windows")) run(ARGV("shutdown", "/r", "/t", "0"), 0);
        else run(ARGV("reboot"), streq(os, "macos") ? RUN_SUDO : 0);
    }
}

/* ------------------------------------------------------------------ collect */

static void track(StrList *changed, const char *name, const char *system, const char *repo)
{
    if (!file_exists(system)) {
        info("    MISSING: %s", name);
    } else if (same_file(system, repo)) {
        info("    SAME: %s", name);
    } else {
        copy_file(system, repo, NULL);
        sl_push(changed, name);
        info("    CHANGED: %s", name);
    }
}

static void collect(const Manifest *m)
{
    const char *os = OS_NATIVE, *de = streq(os, "linux") ? linux_desktop() : "";
    StrList changed = {0};
    info("Files Changed:\n");
    Json *files = json_get(m->root, "files");
    for (int i = 0; files && i < files->n; i++) {
        Json *f = files->items[i];
        if (!manifest_applies(f, os, de)) continue;
        const char *srel = json_str(f, "src", ""), *drel = json_str(f, "dest", "");
        char *src = path_join(g_root, srel), *dest = expand(drel);
        track(&changed, drel, dest, src);
        free(src);
        free(dest);
    }
    if (streq(de, "cinnamon")) {
        if (collect_cinnamon_settings()) {
            sl_push(&changed, "cinnamonSettings");
            info("    CHANGED: cinnamonSettings");
        } else {
            info("    SAME: cinnamonSettings");
        }
    }
    if (!changed.n) {
        info("\nALL FILES ARE THE SAME\n");
        return;
    }
    Buf msg = {0};
    buf_add(&msg, "CHANGED:");
    for (int i = 0; i < changed.n; i++) buf_addf(&msg, " %s", changed.v[i]);
    run(ARGV("git", "-C", g_root, "add", "-A"), 0);
    if (run(ARGV("git", "-C", g_root, "commit", "-m", buf_str(&msg)), 0) == 0)
        run(ARGV("git", "-C", g_root, "push"), 0);
}

/* ------------------------------------------------------------------ generate */

static void generate(const Manifest *m, const char *os)
{
    Buf out = {0};
    if (streq(os, "linux")) {
        keyd_generate(m, &out);
        printf("# ---- %s\n%s\n", KEYD_CONFIG, buf_str(&out));
        printf("# ---- desktop shortcuts (applied with gsettings / kwriteconfig / xfconf)\n");
        for (int i = 0; i < m->nshortcuts; i++) {
            Buf keys = {0};
            for (int k = 0; k < m->shortcuts[i].nkeys; k++) {
                char *cs = combo_str(m->shortcuts[i].keys[k]);
                buf_addf(&keys, "%s%s", k ? ", " : "", cs);
                free(cs);
            }
            printf("#   %-30s %s\n", buf_str(&keys), m->shortcuts[i].action);
        }
    } else if (streq(os, "windows")) {
        ahk_generate(m, &out);
        printf("%s\n", buf_str(&out));
    } else {
        json_write(&out, karabiner_generate(m), 2);
        printf("%s\n", buf_str(&out));
    }
}

/* ------------------------------------------------------------------ CLI */

int main(int argc, char **argv)
{
    const char *command = NULL;
    StrList args = {0};
    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if (streq(a, "-n") || streq(a, "--dry-run")) g_dry_run = 1;
        else if (streq(a, "-c") || streq(a, "--collect")) command = "collect";
        else if (streq(a, "-i") || streq(a, "--install")) command = "install";
        else if (streq(a, "-h") || streq(a, "--help") || streq(a, "help")) { fputs(USAGE, stdout); return 0; }
        else if (a[0] == '-') { fprintf(stderr, "cain: unknown option %s\n\n%s", a, USAGE); return 2; }
        else if (!command) command = a;
        else sl_push(&args, a);
    }

    /* the tools don't need the repo */
    if (streq(command, "booklister")) return booklister_main();
    if (streq(command, "listlauncher")) return listlauncher_main();

    g_root = find_root();
    if (!g_root) die("can't find the cain repo (the folder with cain.json). Run cain from inside it, or set CAIN_DIR.");

    if (streq(command, "generate")) {
        const char *os = args.n ? args.v[0] : OS_NATIVE;
        if (!streq(os, "linux") && !streq(os, "macos") && !streq(os, "windows"))
            die("generate: pick linux, macos or windows");
        generate(manifest_load(os), os);
        return 0;
    }

    fputs(ASCII, stdout);
    putchar('\n');
    while (!command) {
        printf("Would you like to Collect (C) or Install (I)?: ");
        fflush(stdout);
        char line[64];
        if (!fgets(line, sizeof line, stdin)) return 1;
        if (line[0] == 'c' || line[0] == 'C') command = "collect";
        else if (line[0] == 'i' || line[0] == 'I') command = "install";
        else printf("\nNon valid input, please try again\n\n");
    }

    Manifest *m = manifest_load(OS_NATIVE);
    if (streq(command, "collect") || streq(command, "c")) {
        collect(m);
    } else if (streq(command, "install") || streq(command, "i") || streq(command, "keys")) {
        StrList steps = {0};
        if (args.n) steps = args;
        else if (streq(command, "keys")) sl_push(&steps, "keys");
        else for (int i = 0; STEPS[i]; i++) sl_push(&steps, STEPS[i]);
        for (int i = 0; i < steps.n; i++) {
            int known = 0;
            for (int k = 0; STEPS[k]; k++) known |= streq(STEPS[k], steps.v[i]);
            if (!known) die("unknown install step \"%s\"; choose from: packages git files bin shell keys desktop", steps.v[i]);
        }
        install(m, &steps);
    } else {
        fprintf(stderr, "cain: unknown command \"%s\"\n\n%s", command, USAGE);
        return 2;
    }
    return 0;
}
