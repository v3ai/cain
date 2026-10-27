/* Strings, paths, files and running commands - the portable plumbing. */
#include "cain.h"

#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <time.h>
#include <ctype.h>

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#define mkdir_one(p) _mkdir(p)
#else
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>
#define mkdir_one(p) mkdir(p, 0755)
#endif
#ifdef __APPLE__
#include <mach-o/dyld.h>
#include <stdint.h>
#endif

int g_dry_run = 0;
char *g_root = NULL;

/* ------------------------------------------------------------------ memory / strings */

void *xmalloc(size_t n)
{
    void *p = malloc(n ? n : 1);
    if (!p) die("out of memory");
    return p;
}

void *xrealloc(void *p, size_t n)
{
    p = realloc(p, n ? n : 1);
    if (!p) die("out of memory");
    return p;
}

char *xstrdup(const char *s)
{
    size_t n = strlen(s) + 1;
    return memcpy(xmalloc(n), s, n);
}

char *xprintf(const char *fmt, ...)
{
    Buf b = {0};
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    b.s = xmalloc((size_t)n + 1);
    va_start(ap, fmt);
    vsnprintf(b.s, (size_t)n + 1, fmt, ap);
    va_end(ap);
    return b.s;
}

void buf_addn(Buf *b, const char *s, size_t n)
{
    if (b->len + n + 1 > b->cap) {
        b->cap = (b->len + n + 1) * 2;
        b->s = xrealloc(b->s, b->cap);
    }
    memcpy(b->s + b->len, s, n);
    b->len += n;
    b->s[b->len] = 0;
}

void buf_add(Buf *b, const char *s) { buf_addn(b, s, strlen(s)); }
void buf_addc(Buf *b, char c) { buf_addn(b, &c, 1); }

void buf_addf(Buf *b, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(NULL, 0, fmt, ap);
    va_end(ap);
    char *tmp = xmalloc((size_t)n + 1);
    va_start(ap, fmt);
    vsnprintf(tmp, (size_t)n + 1, fmt, ap);
    va_end(ap);
    buf_addn(b, tmp, (size_t)n);
    free(tmp);
}

const char *buf_str(Buf *b) { return b->s ? b->s : ""; }

void sl_push(StrList *l, const char *s)
{
    if (l->n + 1 >= l->cap) {
        l->cap = l->cap ? l->cap * 2 : 8;
        l->v = xrealloc(l->v, sizeof(char *) * (size_t)l->cap);
    }
    l->v[l->n++] = xstrdup(s);
    l->v[l->n] = NULL;
}

int sl_has(const StrList *l, const char *s)
{
    for (int i = 0; i < l->n; i++)
        if (streq(l->v[i], s)) return 1;
    return 0;
}

int streq(const char *a, const char *b) { return a && b && strcmp(a, b) == 0; }
int starts_with(const char *s, const char *p) { return strncmp(s, p, strlen(p)) == 0; }

int ends_with(const char *s, const char *suffix)
{
    size_t a = strlen(s), b = strlen(suffix);
    return a >= b && strcmp(s + a - b, suffix) == 0;
}

char *str_replace(const char *s, const char *from, const char *to)
{
    Buf b = {0};
    size_t fl = strlen(from);
    const char *p;
    while ((p = strstr(s, from))) {
        buf_addn(&b, s, (size_t)(p - s));
        buf_add(&b, to);
        s = p + fl;
    }
    buf_add(&b, s);
    return xstrdup(buf_str(&b));
}

char *str_lower(const char *s)
{
    char *r = xstrdup(s);
    for (char *p = r; *p; p++) *p = (char)tolower((unsigned char)*p);
    return r;
}

char *str_upper(const char *s)
{
    char *r = xstrdup(s);
    for (char *p = r; *p; p++) *p = (char)toupper((unsigned char)*p);
    return r;
}

/* ------------------------------------------------------------------ messages */

void info(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    fflush(stdout);
}

void warn(const char *fmt, ...)
{
    va_list ap;
    printf("  WARNING: ");
    va_start(ap, fmt);
    vprintf(fmt, ap);
    va_end(ap);
    putchar('\n');
    fflush(stdout);
}

void die(const char *fmt, ...)
{
    va_list ap;
    fflush(stdout);
    fprintf(stderr, "cain: ");
    va_start(ap, fmt);
    vfprintf(stderr, fmt, ap);
    va_end(ap);
    fputc('\n', stderr);
    exit(1);
}

void step(const char *title) { info("\n== %s ==", title); }

/* ------------------------------------------------------------------ paths */

const char *home_dir(void)
{
    const char *h = getenv("HOME");
#ifdef _WIN32
    if (!h || !*h) h = getenv("USERPROFILE");
#endif
    return h && *h ? h : ".";
}

char *expand(const char *path)
{
    char *full = path[0] == '~' && (path[1] == '/' || path[1] == '\\' || path[1] == 0)
                     ? xprintf("%s%s", home_dir(), path + 1) : xstrdup(path);
    char *native = native_path(full);
    free(full);
    return native;
}

char *path_join(const char *a, const char *b)
{
    size_t n = strlen(a);
    char *joined = n && (a[n - 1] == '/' || a[n - 1] == '\\') ? xprintf("%s%s", a, b)
                                                              : xprintf("%s/%s", a, b);
    char *native = native_path(joined);
    free(joined);
    return native;
}

static const char *last_sep(const char *p)
{
    const char *s = strrchr(p, '/');
#ifdef _WIN32
    const char *t = strrchr(p, '\\');
    if (t && (!s || t > s)) s = t;
#endif
    return s;
}

char *path_dir(const char *path)
{
    const char *s = last_sep(path);
    if (!s) return xstrdup(".");
    if (s == path) return xstrdup("/");
    char *r = xstrdup(path);
    r[s - path] = 0;
    return r;
}

const char *path_base(const char *path)
{
    const char *s = last_sep(path);
    return s ? s + 1 : path;
}

const char *path_ext(const char *path)
{
    const char *b = path_base(path), *d = strrchr(b, '.');
    return d && d != b ? d : "";
}

char *native_path(const char *path)
{
#ifdef _WIN32
    return str_replace(path, "/", "\\");
#else
    return xstrdup(path);
#endif
}

int file_exists(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0;
}

int is_dir(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && (st.st_mode & S_IFMT) == S_IFDIR;
}

int mkdirs(const char *dir)
{
    if (!*dir || is_dir(dir)) return 0;
    char *parent = path_dir(dir);
    if (!streq(parent, dir) && !streq(parent, ".")) mkdirs(parent);
    free(parent);
    return mkdir_one(dir) == 0 || errno == EEXIST ? 0 : -1;
}

char *read_file(const char *path, size_t *len)
{
    FILE *f = fopen(path, "rb");
    if (!f) return NULL;
    Buf b = {0};
    char chunk[65536];
    size_t n;
    while ((n = fread(chunk, 1, sizeof chunk, f)) > 0) buf_addn(&b, chunk, n);
    fclose(f);
    if (len) *len = b.len;
    return b.s ? b.s : xstrdup("");
}

int write_file(const char *path, const char *data, size_t len)
{
    char *dir = path_dir(path);
    mkdirs(dir);
    free(dir);
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    size_t w = fwrite(data, 1, len, f);
    return fclose(f) == 0 && w == len ? 0 : -1;
}

int same_file(const char *a, const char *b)
{
    size_t la, lb;
    char *da = read_file(a, &la), *db = read_file(b, &lb);
    int same = da && db && la == lb && memcmp(da, db, la) == 0;
    free(da);
    free(db);
    return same;
}

/* Copy src -> dest, first backing up an existing, different dest into backup_dir. */
int copy_file(const char *src, const char *dest, const char *backup_dir)
{
    if (backup_dir && file_exists(dest) && !same_file(src, dest)) {
        char *target = path_join(backup_dir, path_base(dest));
        if (g_dry_run) {
            info("  [dry-run] backup %s -> %s", dest, target);
        } else {
            size_t n;
            char *old = read_file(dest, &n);
            if (old) write_file(target, old, n);
            free(old);
        }
        free(target);
    }
    if (g_dry_run) {
        info("  [dry-run] copy %s -> %s", src, dest);
        return 0;
    }
    size_t n;
    char *data = read_file(src, &n);
    if (!data) {
        warn("can't read %s", src);
        return -1;
    }
    int r = write_file(dest, data, n);
    if (r) warn("can't write %s: %s", dest, strerror(errno));
    free(data);
    return r;
}

/* Write a text file, creating parent dirs. With sudo, goes through `sudo tee`. */
void write_text(const char *path, const char *content, int sudo)
{
    if (g_dry_run) {
        info("  [dry-run] write %s (%d bytes)", path, (int)strlen(content));
        return;
    }
    if (sudo && !is_root()) {
        char *dir = path_dir(path);
        run(ARGV("mkdir", "-p", dir), RUN_SUDO);
        free(dir);
        run_input(ARGV("sudo", "tee", path), RUN_QUIET, content);
    } else if (write_file(path, content, strlen(content)) != 0) {
        warn("can't write %s: %s", path, strerror(errno));
        return;
    }
    info("  wrote %s", path);
}

/* Insert or replace a '# >>> cain >>>' managed block in a text file (e.g. ~/.bashrc). */
void upsert_block(const char *path, const char *block)
{
    const char *start = "# >>> cain >>>", *end = "# <<< cain <<<";
    char *text = read_file(path, NULL);
    if (!text) text = xstrdup("");
    Buf nb = {0}, out = {0};
    buf_addf(&nb, "%s\n%s", start, block);
    while (nb.len && nb.s[nb.len - 1] == '\n') nb.s[--nb.len] = 0;
    buf_addf(&nb, "\n%s\n", end);

    char *s = strstr(text, start), *e = s ? strstr(s, end) : NULL;
    if (s && e) {
        buf_addn(&out, text, (size_t)(s - text));
        buf_add(&out, nb.s);
        e += strlen(end);
        while (*e == '\n') e++;
        buf_add(&out, e);
    } else {
        buf_add(&out, text);
        if (*text && !ends_with(text, "\n")) buf_addc(&out, '\n');
        if (*text) buf_addc(&out, '\n');
        buf_add(&out, nb.s);
    }
    write_text(path, buf_str(&out), 0);
    free(text);
}

char *self_exe(void)
{
    char buf[4096];
#ifdef _WIN32
    DWORD n = GetModuleFileNameA(NULL, buf, sizeof buf);
    if (n > 0 && n < sizeof buf) return xstrdup(buf);
#elif defined(__APPLE__)
    uint32_t size = sizeof buf;
    char real[4096];
    if (_NSGetExecutablePath(buf, &size) == 0) return xstrdup(realpath(buf, real) ? real : buf);
#else
    ssize_t n = readlink("/proc/self/exe", buf, sizeof buf - 1);
    if (n > 0) {
        buf[n] = 0;
        return xstrdup(buf);
    }
#endif
    return NULL;
}

char *timestamp(void)
{
    char buf[32];
    time_t t = time(NULL);
    strftime(buf, sizeof buf, "%Y%m%d-%H%M%S", localtime(&t));
    return xstrdup(buf);
}

/* ------------------------------------------------------------------ processes */

int is_root(void)
{
#ifdef _WIN32
    return 0;
#else
    return geteuid() == 0;
#endif
}

/* Quote for display / for sh -c, like Python's shlex.quote. */
char *shell_quote(const char *s)
{
    if (!*s) return xstrdup("''");
    const char *p;
    for (p = s; *p; p++)
        if (!isalnum((unsigned char)*p) && !strchr("@%+=:,./-_", *p)) break;
    if (!*p) return xstrdup(s);
    char *inner = str_replace(s, "'", "'\"'\"'");
    char *r = xprintf("'%s'", inner);
    free(inner);
    return r;
}

static char *argv_display(const char *const *argv)
{
    Buf b = {0};
    for (int i = 0; argv[i]; i++) {
        char *q = shell_quote(argv[i]);
        buf_addf(&b, "%s%s", i ? " " : "", q);
        free(q);
    }
    return xstrdup(buf_str(&b));
}

char *which(const char *cmd)
{
    if (strchr(cmd, '/') || strchr(cmd, '\\'))
        return file_exists(cmd) ? xstrdup(cmd) : NULL;
    const char *path = getenv("PATH");
    if (!path) return NULL;
#ifdef _WIN32
    const char sep = ';';
    const char *exts[] = {"", ".exe", ".cmd", ".bat", ".com", NULL};
#else
    const char sep = ':';
    const char *exts[] = {"", NULL};
#endif
    char *copy = xstrdup(path), *dir = copy, *next;
    char *found = NULL;
    for (; dir && !found; dir = next) {
        next = strchr(dir, sep);
        if (next) *next++ = 0;
        if (!*dir) continue;
        for (int i = 0; exts[i] && !found; i++) {
            char *cand = xprintf("%s/%s%s", dir, cmd, exts[i]);
#ifdef _WIN32
            if (file_exists(cand) && !is_dir(cand)) found = cand;
#else
            if (access(cand, X_OK) == 0 && !is_dir(cand)) found = cand;
#endif
            if (!found) free(cand);
        }
    }
    free(copy);
    return found;
}

#ifdef _WIN32
/* Quote one argument following the MS C runtime rules. */
static void win_quote_arg(Buf *b, const char *a)
{
    if (*a && !strpbrk(a, " \t\"")) {
        buf_add(b, a);
        return;
    }
    buf_addc(b, '"');
    for (const char *p = a;; p++) {
        int slashes = 0;
        while (*p == '\\') { p++; slashes++; }
        if (!*p) {
            for (int i = 0; i < slashes * 2; i++) buf_addc(b, '\\');
            break;
        }
        if (*p == '"') {
            for (int i = 0; i < slashes * 2 + 1; i++) buf_addc(b, '\\');
        } else {
            for (int i = 0; i < slashes; i++) buf_addc(b, '\\');
        }
        buf_addc(b, *p);
    }
    buf_addc(b, '"');
}

static int spawn(const char *const *argv, int quiet, const char *input, char **captured)
{
    Buf cmd = {0};
    for (int i = 0; argv[i]; i++) {
        if (i) buf_addc(&cmd, ' ');
        win_quote_arg(&cmd, argv[i]);
    }
    SECURITY_ATTRIBUTES sa = {sizeof sa, NULL, TRUE};
    HANDLE out_r = NULL, out_w = NULL, in_r = NULL, in_w = NULL, nul = NULL;
    STARTUPINFOA si = {0};
    PROCESS_INFORMATION pi;
    si.cb = sizeof si;
    si.dwFlags = STARTF_USESTDHANDLES;
    si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
    si.hStdOutput = GetStdHandle(STD_OUTPUT_HANDLE);
    si.hStdError = GetStdHandle(STD_ERROR_HANDLE);
    if (captured || quiet) {
        nul = CreateFileA("NUL", GENERIC_WRITE, FILE_SHARE_WRITE, &sa, OPEN_EXISTING, 0, NULL);
        si.hStdError = nul;
        si.hStdOutput = nul;
    }
    if (captured) {
        CreatePipe(&out_r, &out_w, &sa, 0);
        SetHandleInformation(out_r, HANDLE_FLAG_INHERIT, 0);
        si.hStdOutput = out_w;
    }
    if (input) {
        CreatePipe(&in_r, &in_w, &sa, 0);
        SetHandleInformation(in_w, HANDLE_FLAG_INHERIT, 0);
        si.hStdInput = in_r;
    }
    char *line = xstrdup(buf_str(&cmd));
    BOOL ok = CreateProcessA(NULL, line, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
    free(line);
    if (out_w) CloseHandle(out_w);
    if (in_r) CloseHandle(in_r);
    if (!ok) {
        if (out_r) CloseHandle(out_r);
        if (in_w) CloseHandle(in_w);
        if (nul) CloseHandle(nul);
        return -1;
    }
    if (in_w) {
        DWORD w;
        WriteFile(in_w, input, (DWORD)strlen(input), &w, NULL);
        CloseHandle(in_w);
    }
    if (captured) {
        Buf b = {0};
        char chunk[4096];
        DWORD n;
        while (ReadFile(out_r, chunk, sizeof chunk, &n, NULL) && n > 0) buf_addn(&b, chunk, n);
        CloseHandle(out_r);
        *captured = xstrdup(buf_str(&b));
    }
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    CloseHandle(pi.hThread);
    if (nul) CloseHandle(nul);
    return (int)code;
}
#else
static int spawn(const char *const *argv, int quiet, const char *input, char **captured)
{
    int out_pipe[2] = {-1, -1}, in_pipe[2] = {-1, -1};
    if (captured && pipe(out_pipe) != 0) return -1;
    if (input && pipe(in_pipe) != 0) return -1;
    fflush(stdout);
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        if (captured || quiet) {
            int devnull = open("/dev/null", O_WRONLY);
            dup2(devnull, 2);
            dup2(devnull, 1);
        }
        if (captured) {
            dup2(out_pipe[1], 1);
            close(out_pipe[0]);
            close(out_pipe[1]);
        }
        if (input) {
            dup2(in_pipe[0], 0);
            close(in_pipe[0]);
            close(in_pipe[1]);
        }
        execvp(argv[0], (char *const *)argv);
        _exit(127);
    }
    if (input) {
        close(in_pipe[0]);
        size_t len = strlen(input), off = 0;
        while (off < len) {
            ssize_t w = write(in_pipe[1], input + off, len - off);
            if (w <= 0) break;
            off += (size_t)w;
        }
        close(in_pipe[1]);
    }
    if (captured) {
        close(out_pipe[1]);
        Buf b = {0};
        char chunk[4096];
        ssize_t n;
        while ((n = read(out_pipe[0], chunk, sizeof chunk)) > 0) buf_addn(&b, chunk, (size_t)n);
        close(out_pipe[0]);
        *captured = xstrdup(buf_str(&b));
    }
    int status;
    if (waitpid(pid, &status, 0) < 0) return -1;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
#endif

static const char *const *with_sudo(const char *const *argv, int flags)
{
    if (!(flags & RUN_SUDO) || streq(OS_NATIVE, "windows") || is_root()) return argv;
    int n = 0;
    while (argv[n]) n++;
    const char **v = xmalloc(sizeof(char *) * (size_t)(n + 2));
    v[0] = "sudo";
    memcpy(v + 1, argv, sizeof(char *) * (size_t)(n + 1));
    return v;
}

int run_input(const char *const *argv, int flags, const char *input)
{
    argv = with_sudo(argv, flags);
    char *shown = argv_display(argv);
    if (g_dry_run) {
        info("  [dry-run] %s", shown);
        free(shown);
        return 0;
    }
    info("  $ %s", shown);
    free(shown);
    char *exe = which(argv[0]);
    if (!exe) {
        warn("command not found: %s", argv[0]);
        return -1;
    }
    free(exe);
    return spawn(argv, flags & RUN_QUIET, input, NULL);
}

int run(const char *const *argv, int flags) { return run_input(argv, flags, NULL); }

int run_shell(const char *cmd)
{
    if (g_dry_run) {
        info("  [dry-run] %s", cmd);
        return 0;
    }
    info("  $ %s", cmd);
    fflush(stdout);
    return system(cmd);
}

char *output(const char *const *argv)
{
    char *exe = which(argv[0]);
    if (!exe) return NULL;
    free(exe);
    char *out = NULL;
    int code = spawn(argv, 1, NULL, &out);
    if (code != 0) {
        free(out);
        return NULL;
    }
    return out;
}

/* Feed `input` to a command and return its stdout (NULL if it fails). */
char *pipe_through(const char *const *argv, const char *input)
{
    char *exe = which(argv[0]);
    if (!exe) return NULL;
    free(exe);
    char *out = NULL;
    if (spawn(argv, 1, input, &out) != 0) {
        free(out);
        return NULL;
    }
    return out;
}

int stdin_tty(void)
{
#ifdef _WIN32
    DWORD mode;  /* _isatty() is also true for NUL, so ask for a real console */
    return GetConsoleMode(GetStdHandle(STD_INPUT_HANDLE), &mode) != 0;
#else
    return isatty(0);
#endif
}

int ask(const char *question, int def)
{
    if (g_dry_run || !stdin_tty()) return def;
    printf("%s%s", question, def ? " [Y/n]: " : " [y/N]: ");
    fflush(stdout);
    char line[64];
    if (!fgets(line, sizeof line, stdin)) return def;
    char *p = line;
    while (*p == ' ' || *p == '\t') p++;
    if (*p == '\n' || !*p) return def;
    return *p == 'y' || *p == 'Y';
}

void open_path(const char *path)
{
#ifdef _WIN32
    ShellExecuteA(NULL, "open", path, NULL, NULL, SW_SHOWNORMAL);
#else
    const char *opener = streq(OS_NATIVE, "macos") ? "open" : "xdg-open";
    fflush(stdout);
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        int devnull = open("/dev/null", O_WRONLY);
        dup2(devnull, 1);
        dup2(devnull, 2);
        execlp(opener, opener, path, (char *)NULL);
        _exit(127);
    }
#endif
}
