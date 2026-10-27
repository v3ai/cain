/* cain - Collects And INstalls dotfiles, keybindings and programs.
 * Shared declarations for every module.
 *
 * cain is a short-lived command: data that lives until it exits (the parsed
 * cain.json, generated configs) is never freed. Temporary strings are. */
#ifndef CAIN_H
#define CAIN_H

#include <stddef.h>
#include <stdarg.h>

#ifdef _WIN32
#define OS_NATIVE "windows"
#elif defined(__APPLE__)
#define OS_NATIVE "macos"
#else
#define OS_NATIVE "linux"
#endif

#if defined(__GNUC__)
#define PRINTF_LIKE(a, b) __attribute__((format(printf, a, b)))
#else
#define PRINTF_LIKE(a, b)
#endif

/* ------------------------------------------------------------------ util.c */

extern int g_dry_run;
extern char *g_root;            /* the cain repo (holds cain.json) */

typedef struct { char *s; size_t len, cap; } Buf;
void buf_add(Buf *b, const char *s);
void buf_addn(Buf *b, const char *s, size_t n);
void buf_addc(Buf *b, char c);
void buf_addf(Buf *b, const char *fmt, ...) PRINTF_LIKE(2, 3);
const char *buf_str(Buf *b);    /* never NULL */

typedef struct { char **v; int n, cap; } StrList;
void sl_push(StrList *l, const char *s);    /* copies s */
int sl_has(const StrList *l, const char *s);

void *xmalloc(size_t n);
void *xrealloc(void *p, size_t n);
char *xstrdup(const char *s);
char *xprintf(const char *fmt, ...) PRINTF_LIKE(1, 2);
int streq(const char *a, const char *b);
int starts_with(const char *s, const char *prefix);
int ends_with(const char *s, const char *suffix);
char *str_replace(const char *s, const char *from, const char *to);
char *str_lower(const char *s);
char *str_upper(const char *s);

void info(const char *fmt, ...) PRINTF_LIKE(1, 2);
void warn(const char *fmt, ...) PRINTF_LIKE(1, 2);
void die(const char *fmt, ...) PRINTF_LIKE(1, 2);
void step(const char *title);

const char *home_dir(void);
char *expand(const char *path);             /* "~/x" -> "/home/me/x" */
char *path_join(const char *a, const char *b);
char *path_dir(const char *path);
const char *path_base(const char *path);
const char *path_ext(const char *path);     /* ".jpg" or "" */
char *native_path(const char *path);        /* backslashes on Windows */
int file_exists(const char *path);
int is_dir(const char *path);
int mkdirs(const char *dir);
char *read_file(const char *path, size_t *len);  /* NULL if unreadable */
int write_file(const char *path, const char *data, size_t len);
int same_file(const char *a, const char *b);
int copy_file(const char *src, const char *dest, const char *backup_dir);
void write_text(const char *path, const char *content, int sudo);
void upsert_block(const char *path, const char *block);
char *self_exe(void);
char *timestamp(void);

/* processes */
#define RUN_SUDO   1    /* prefix with sudo on Linux/macOS unless root */
#define RUN_QUIET  2    /* hide the command's output */
int run(const char *const *argv, int flags);               /* exit code, 0 in dry-run */
int run_input(const char *const *argv, int flags, const char *input);
int run_shell(const char *cmd);
char *output(const char *const *argv);                     /* stdout or NULL; runs in dry-run too */
char *pipe_through(const char *const *argv, const char *input);
char *which(const char *cmd);
char *shell_quote(const char *s);
int is_root(void);
int ask(const char *question, int def);
int stdin_tty(void);
void open_path(const char *path);                          /* default app for a file/URL */

#define ARGV(...) ((const char *const[]){__VA_ARGS__, NULL})

/* ------------------------------------------------------------------ json.c */

typedef enum { J_NULL, J_BOOL, J_NUM, J_STR, J_ARR, J_OBJ } JType;
typedef struct Json {
    JType t;
    int b;
    double num;
    char *str;
    struct Json **items;     /* array items / object values */
    char **keys;             /* object keys */
    int n, cap;
} Json;

Json *json_parse(const char *text, char **err);
void json_write(Buf *out, const Json *j, int indent);
Json *json_new(JType t);
Json *json_new_str(const char *s);
Json *json_get(const Json *obj, const char *key);
int json_has(const Json *obj, const char *key);
const char *json_str(const Json *obj, const char *key, const char *def);
int json_bool(const Json *obj, const char *key, int def);
void json_set(Json *obj, const char *key, Json *val);
void json_push(Json *arr, Json *val);

/* ------------------------------------------------------------------ keys.c */

enum {
    M_SUPER = 1 << 0, M_LSUPER = 1 << 1, M_RSUPER = 1 << 2,
    M_CTRL = 1 << 3, M_LCTRL = 1 << 4, M_RCTRL = 1 << 5,
    M_ALT = 1 << 6, M_LALT = 1 << 7, M_RALT = 1 << 8,
    M_SHIFT = 1 << 9,
    M_COUNT = 10
};
#define M_ANY_ALT (M_ALT | M_LALT | M_RALT)
#define M_ANY_CTRL (M_CTRL | M_LCTRL | M_RCTRL)

typedef struct { unsigned mods; const char *key; } Combo;

extern const char *const MOD_NAMES[M_COUNT];
int combo_parse(const char *text, Combo *out);   /* 0 on success */
Combo combo_must(const char *text);              /* exits on a bad combo */
int combo_eq(Combo a, Combo b);
unsigned generic_mods(unsigned mods);
char *combo_str(Combo c);
Combo mac_translate(Combo c);
Combo mac_swap_alt_cmd(Combo c);

const char *keyd_key(const char *key);
char *keyd_output(Combo c);
char *ahk_key(const char *key);
char *ahk_hotkey(Combo c);
char *ahk_send(Combo c);
const char *karabiner_key(const char *key);
Json *karabiner_from(Combo c, const char *const *optional);
Json *karabiner_to(Combo c, const char *extra_mod);
char *gtk_accel(Combo c);
char *kde_accel(Combo c);

/* -------------------------------------------------------------- manifest.c */

typedef struct { Combo from, to; } Remap;
typedef struct { Json *entry; const char *action; Combo *keys; int nkeys; } Shortcut;

typedef struct {
    Json *root, *settings, *git;
    Remap *remaps; int nremaps;
    Shortcut *shortcuts; int nshortcuts;
} Manifest;

Manifest *manifest_load(const char *os);
int manifest_applies(const Json *entry, const char *os, const char *desktop);
const char *setting(const Manifest *m, const char *key, const char *def);

/* --------------------------------------------------------------- actions.c */

int is_wm_action(const char *action);
char *bin_dir(const char *os);
char *installed_exe(const char *os);
char *launch_command(const Shortcut *sc, const char *os, const Manifest *m);
char *friendly(const Shortcut *sc);

/* --------------------------------------------------------------- backends */

#define KEYD_CONFIG "/etc/keyd/default.conf"
void keyd_generate(const Manifest *m, Buf *out);
void keyd_apply(const Manifest *m, const char *pm);

void ahk_generate(const Manifest *m, Buf *out);
void ahk_apply(const Manifest *m);

#define KARABINER_TAG "cain: "
Json *karabiner_generate(const Manifest *m);
void karabiner_apply(const Manifest *m);

const char *linux_desktop(void);
void linux_desktop_apply(const char *desktop, const Manifest *m);

const char *detect_linux_pm(void);
int install_linux_packages(const char *pm, const StrList *names, int quiet);
void brew_install(const StrList *names);
void winget_install(const StrList *ids);
void packages_install(const Manifest *m, const char *os);

void desktop_apply(const char *os, const char *desktop, const Manifest *m);
int collect_cinnamon_settings(void);

/* ----------------------------------------------------------------- tools.c */

int booklister_main(void);
int listlauncher_main(void);

#endif
