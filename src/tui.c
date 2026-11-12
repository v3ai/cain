/* A tiny terminal menu: arrow keys (or j/k) to move, Enter to pick, Space to tick.
 * Falls back to a numbered prompt when the terminal can't do it (no ANSI, piped output). */
#include "cain.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <conio.h>
#include <io.h>
#define stdout_tty() _isatty(_fileno(stdout))
#else
#define stdout_tty() isatty(1)
#include <poll.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <termios.h>
#include <unistd.h>
#endif

enum { K_NONE, K_UP, K_DOWN, K_ENTER, K_SPACE, K_QUIT, K_ALL, K_HOME, K_END };

/* ------------------------------------------------------------------ raw keyboard */

#ifdef _WIN32
static int raw_on(void)
{
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD mode;
    if (!GetConsoleMode(out, &mode)) return 0;
    return SetConsoleMode(out, mode | 0x0004 /* ENABLE_VIRTUAL_TERMINAL_PROCESSING */) != 0;
}
static void raw_off(void) {}

static int read_key(int *ch)
{
    int c = _getch();
    *ch = c;
    if (c == 0 || c == 0xE0) {  /* arrows and friends come as two codes */
        int d = _getch();
        return d == 72 ? K_UP : d == 80 ? K_DOWN : d == 71 ? K_HOME : d == 79 ? K_END : K_NONE;
    }
    if (c == '\r' || c == '\n') return K_ENTER;
    if (c == 27 || c == 3) return K_QUIT;  /* Esc, Ctrl+C */
    return K_NONE;
}
#else
static struct termios saved;
static int raw_active = 0;

static void raw_off(void)
{
    if (!raw_active) return;
    tcsetattr(0, TCSAFLUSH, &saved);
    fputs("\033[?25h", stdout);  /* show the cursor again */
    fflush(stdout);
    raw_active = 0;
}

static void on_signal(int sig)
{
    raw_off();
    signal(sig, SIG_DFL);
    raise(sig);
}

static int raw_on(void)
{
    if (tcgetattr(0, &saved) != 0) return 0;
    struct termios raw = saved;
    raw.c_lflag &= ~(tcflag_t)(ICANON | ECHO);
    raw.c_cc[VMIN] = 1;
    raw.c_cc[VTIME] = 0;
    if (tcsetattr(0, TCSAFLUSH, &raw) != 0) return 0;
    raw_active = 1;
    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    fputs("\033[?25l", stdout);  /* hide the cursor while the menu is up */
    return 1;
}

static int byte_ready(void)
{
    struct pollfd p = {0, POLLIN, 0};
    return poll(&p, 1, 40) > 0;
}

static int read_key(int *ch)
{
    unsigned char c;
    if (read(0, &c, 1) != 1) return K_QUIT;
    *ch = c;
    if (c == '\r' || c == '\n') return K_ENTER;
    if (c == 3 || c == 4) return K_QUIT;  /* Ctrl+C, Ctrl+D */
    if (c != 27) return K_NONE;
    if (!byte_ready()) return K_QUIT;  /* a lone Esc */
    unsigned char seq[3] = {0};
    if (read(0, &seq[0], 1) != 1 || (seq[0] != '[' && seq[0] != 'O')) return K_NONE;
    if (read(0, &seq[1], 1) != 1) return K_NONE;
    switch (seq[1]) {
    case 'A': return K_UP;
    case 'B': return K_DOWN;
    case 'H': return K_HOME;
    case 'F': return K_END;
    default:
        if (seq[1] >= '0' && seq[1] <= '9' && byte_ready() && read(0, &seq[2], 1) == 1) {}  /* eat the ~ of ESC[3~ */
        return K_NONE;
    }
}
#endif

static int keyboard_key(int *ch)
{
    int k = read_key(ch);
    if (k != K_NONE) return k;
    switch (*ch) {
    case 'k': case 'K': case 'w': return K_UP;
    case 'j': case 'J': case 's': return K_DOWN;
    case ' ': case 'x': return K_SPACE;
    case 'q': case 'Q': return K_QUIT;
    case 'a': case 'A': return K_ALL;
    case 'g': return K_HOME;
    case 'G': return K_END;
    }
    return K_NONE;
}

/* ------------------------------------------------------------------ drawing */

static int term_cols(void)
{
#ifdef _WIN32
    CONSOLE_SCREEN_BUFFER_INFO info;
    if (GetConsoleScreenBufferInfo(GetStdHandle(STD_OUTPUT_HANDLE), &info))
        return info.srWindow.Right - info.srWindow.Left + 1;
#else
    struct winsize ws;
    if (ioctl(1, TIOCGWINSZ, &ws) == 0 && ws.ws_col > 0) return ws.ws_col;
#endif
    return 80;
}

static int g_drawn = 0;  /* lines printed by the last draw, so the next one can overwrite them */

static void draw(const char *title, const char *hint, const MenuItem *items, int n, int cur, const int *checked)
{
    if (g_drawn) printf("\033[%dA", g_drawn);
    int width = 0;
    for (int i = 0; i < n; i++) {
        int w = (int)strlen(items[i].label);
        if (w > width) width = w;
    }
    /* every line must fit: a wrapped line would throw off the redraw */
    int cols = term_cols() - 1, room = cols - 3 - (checked ? 4 : 0) - width - 2;
    if (room < 0) room = 0;
    printf("\r\033[2K\033[1m%.*s\033[0m\n", cols, title);
    printf("\r\033[2K\033[2m%.*s\033[0m\n\r\033[2K\n", cols, hint);
    for (int i = 0; i < n; i++) {
        const char *box = !checked ? "" : checked[i] ? "[x] " : "[ ] ", *desc = items[i].desc ? items[i].desc : "";
        if (i == cur)
            printf("\r\033[2K \033[1;36m> %s%-*s\033[0m  %.*s\n", box, width, items[i].label, room, desc);
        else
            printf("\r\033[2K   %s%-*s  \033[2m%.*s\033[0m\n", box, width, items[i].label, room, desc);
    }
    fflush(stdout);
    g_drawn = n + 3;
}

/* Numbered fallback for terminals that can't do the arrow-key menu. */
static int plain_menu(const char *title, const MenuItem *items, int n, int *checked)
{
    printf("%s\n\n", title);
    for (int i = 0; i < n; i++)
        printf("  %d) %s%-12s %s\n", i + 1, !checked ? "" : checked[i] ? "[x] " : "[ ] ", items[i].label,
               items[i].desc ? items[i].desc : "");
    printf(checked ? "\nNumbers to install, separated by spaces (Enter keeps the [x] ones, q quits): "
                   : "\nPick a number (q quits): ");
    fflush(stdout);
    char line[256];
    if (!fgets(line, sizeof line, stdin)) return -1;
    char *p = line;
    while (*p == ' ' || *p == '\t') p++;
    if (*p == 'q' || *p == 'Q') return -1;
    if (!checked) {
        int v = atoi(p);
        return v >= 1 && v <= n ? v - 1 : plain_menu(title, items, n, checked);
    }
    if (*p == '\n' || !*p) return 0;
    for (int i = 0; i < n; i++) checked[i] = 0;
    for (char *t = strtok(p, " ,\t\n"); t; t = strtok(NULL, " ,\t\n")) {
        int v = atoi(t);
        if (v >= 1 && v <= n) checked[v - 1] = 1;
    }
    return 0;
}

int tui_menu(const char *title, const MenuItem *items, int n, int start, int *checked)
{
    if (!stdin_tty()) return -1;
    if (!stdout_tty() || !raw_on()) return plain_menu(title, items, n, checked);
    const char *hint = checked ? "up/down move   space tick   a all/none   enter go   q quit"
                               : "up/down move   enter pick   q quit";
    int cur = start >= 0 && start < n ? start : 0, result = -1;
    g_drawn = 0;
    putchar('\n');
    for (;;) {
        draw(title, hint, items, n, cur, checked);
        int ch = 0, k = keyboard_key(&ch);
        if (k == K_UP) cur = (cur + n - 1) % n;
        else if (k == K_DOWN) cur = (cur + 1) % n;
        else if (k == K_HOME) cur = 0;
        else if (k == K_END) cur = n - 1;
        else if (k == K_SPACE && checked) checked[cur] = !checked[cur];
        else if (k == K_ALL && checked) {
            int all = 1;
            for (int i = 0; i < n; i++) all &= checked[i] != 0;
            for (int i = 0; i < n; i++) checked[i] = !all;
        } else if (k == K_ENTER) { result = cur; break; }
        else if (k == K_QUIT) break;
        else if (ch >= '1' && ch <= '9' && ch - '1' < n) cur = ch - '1';
    }
    raw_off();
    putchar('\n');
    fflush(stdout);
    return result;
}
