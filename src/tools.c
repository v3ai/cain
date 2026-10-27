/* cain's little built-in tools.
 *
 *   cain booklister    pick a book from ~/Desktop/books (or $CAIN_BOOKS_DIR) and open it
 *   cain listlauncher  edit list.html on rhettapplestone.com, then commit and push it
 */
#include "cain.h"

#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#include <windows.h>
#include <direct.h>
#define change_dir _chdir
#else
#include <dirent.h>
#include <unistd.h>
#define change_dir chdir
#endif

typedef struct { char *name, *path; } Book;
typedef struct { Book *v; int n, cap; } Books;

static void add_book(Books *b, const char *name, const char *path)
{
    for (int i = 0; i < b->n; i++)
        if (streq(b->v[i].name, name)) {  /* same file name twice: the last one wins */
            b->v[i].path = xstrdup(path);
            return;
        }
    if (b->n == b->cap) {
        b->cap = b->cap ? b->cap * 2 : 64;
        b->v = xrealloc(b->v, sizeof(Book) * (size_t)b->cap);
    }
    b->v[b->n].name = xstrdup(name);
    b->v[b->n].path = xstrdup(path);
    b->n++;
}

static void scan(Books *books, const char *dir)
{
#ifdef _WIN32
    char *pattern = path_join(dir, "*");
    WIN32_FIND_DATAA fd;
    HANDLE h = FindFirstFileA(pattern, &fd);
    free(pattern);
    if (h == INVALID_HANDLE_VALUE) return;
    do {
        if (streq(fd.cFileName, ".") || streq(fd.cFileName, "..")) continue;
        char *full = path_join(dir, fd.cFileName);
        if (fd.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) scan(books, full);
        else add_book(books, fd.cFileName, full);
        free(full);
    } while (FindNextFileA(h, &fd));
    FindClose(h);
#else
    DIR *d = opendir(dir);
    if (!d) return;
    struct dirent *e;
    while ((e = readdir(d))) {
        if (streq(e->d_name, ".") || streq(e->d_name, "..")) continue;
        char *full = path_join(dir, e->d_name);
        if (is_dir(full)) scan(books, full);
        else add_book(books, e->d_name, full);
        free(full);
    }
    closedir(d);
#endif
}

static int by_name(const void *a, const void *b)
{
    const char *x = ((const Book *)a)->name, *y = ((const Book *)b)->name;
    for (; *x && tolower((unsigned char)*x) == tolower((unsigned char)*y); x++, y++) {}
    return tolower((unsigned char)*x) - tolower((unsigned char)*y);
}

#ifndef _WIN32
static char *names_text(const Books *b)
{
    Buf t = {0};
    for (int i = 0; i < b->n; i++) buf_addf(&t, "%s\n", b->v[i].name);
    return t.s ? t.s : xstrdup("");
}

static char *chomp(char *s)
{
    if (!s) return NULL;
    size_t n = strlen(s);
    while (n && (s[n - 1] == '\n' || s[n - 1] == '\r')) s[--n] = 0;
    return s;
}
#endif

/* ---------------------------------------------------------------- pickers
 * Each returns the chosen name, "" if the user cancelled, or NULL if it isn't available. */

#ifdef _WIN32
static const Books *g_books;
static HWND g_edit, g_list;
static WNDPROC g_edit_proc;
static int g_choice = -1;

static int matches(const char *name, const char *query)
{
    char *n = str_lower(name), *q = str_lower(query);
    int ok = 1;
    for (char *part = strtok(q, " "); part && ok; part = strtok(NULL, " ")) ok = strstr(n, part) != NULL;
    free(n);
    free(q);
    return ok;
}

static void refill(void)
{
    char query[512];
    GetWindowTextA(g_edit, query, sizeof query);
    SendMessageA(g_list, LB_RESETCONTENT, 0, 0);
    for (int i = 0; i < g_books->n; i++)
        if (matches(g_books->v[i].name, query)) {
            LRESULT at = SendMessageA(g_list, LB_ADDSTRING, 0, (LPARAM)g_books->v[i].name);
            SendMessageA(g_list, LB_SETITEMDATA, (WPARAM)at, i);
        }
    SendMessageA(g_list, LB_SETCURSEL, 0, 0);
}

static void choose(HWND win)
{
    LRESULT sel = SendMessageA(g_list, LB_GETCURSEL, 0, 0);
    if (sel != LB_ERR) g_choice = (int)SendMessageA(g_list, LB_GETITEMDATA, (WPARAM)sel, 0);
    DestroyWindow(win);
}

static LRESULT CALLBACK edit_proc(HWND h, UINT msg, WPARAM wp, LPARAM lp)
{
    HWND win = GetParent(h);
    if (msg == WM_KEYDOWN) {
        LRESULT sel = SendMessageA(g_list, LB_GETCURSEL, 0, 0), count = SendMessageA(g_list, LB_GETCOUNT, 0, 0);
        if (wp == VK_DOWN && sel + 1 < count) { SendMessageA(g_list, LB_SETCURSEL, (WPARAM)(sel + 1), 0); return 0; }
        if (wp == VK_UP && sel > 0) { SendMessageA(g_list, LB_SETCURSEL, (WPARAM)(sel - 1), 0); return 0; }
        if (wp == VK_RETURN) { choose(win); return 0; }
        if (wp == VK_ESCAPE) { DestroyWindow(win); return 0; }
    }
    if (msg == WM_CHAR && (wp == '\r' || wp == 27)) return 0;  /* no beep */
    return CallWindowProcA(g_edit_proc, h, msg, wp, lp);
}

static LRESULT CALLBACK win_proc(HWND h, UINT msg, WPARAM wp, LPARAM lp)
{
    switch (msg) {
    case WM_CREATE: {
        HFONT font = (HFONT)GetStockObject(DEFAULT_GUI_FONT);
        g_edit = CreateWindowExA(WS_EX_CLIENTEDGE, "EDIT", "", WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL,
                                 0, 0, 0, 0, h, (HMENU)1, NULL, NULL);
        g_list = CreateWindowExA(WS_EX_CLIENTEDGE, "LISTBOX", "",
                                 WS_CHILD | WS_VISIBLE | WS_VSCROLL | LBS_NOTIFY | LBS_NOINTEGRALHEIGHT,
                                 0, 0, 0, 0, h, (HMENU)2, NULL, NULL);
        SendMessageA(g_edit, WM_SETFONT, (WPARAM)font, TRUE);
        SendMessageA(g_list, WM_SETFONT, (WPARAM)font, TRUE);
        g_edit_proc = (WNDPROC)SetWindowLongPtrA(g_edit, GWLP_WNDPROC, (LONG_PTR)edit_proc);
        refill();
        return 0;
    }
    case WM_SIZE:
        MoveWindow(g_edit, 0, 0, LOWORD(lp), 24, TRUE);
        MoveWindow(g_list, 0, 24, LOWORD(lp), HIWORD(lp) - 24, TRUE);
        return 0;
    case WM_SETFOCUS:
        SetFocus(g_edit);
        return 0;
    case WM_COMMAND:
        if (LOWORD(wp) == 1 && HIWORD(wp) == EN_CHANGE) refill();
        if (LOWORD(wp) == 2 && HIWORD(wp) == LBN_DBLCLK) choose(h);
        return 0;
    case WM_DESTROY:
        PostQuitMessage(0);
        return 0;
    }
    return DefWindowProcA(h, msg, wp, lp);
}

static char *pick_windows(const Books *books)
{
    g_books = books;
    WNDCLASSA wc = {0};
    wc.lpfnWndProc = win_proc;
    wc.hInstance = GetModuleHandleA(NULL);
    wc.hCursor = LoadCursor(NULL, IDC_ARROW);
    wc.hbrBackground = (HBRUSH)(COLOR_WINDOW + 1);
    wc.lpszClassName = "cainBooklister";
    RegisterClassA(&wc);
    HWND win = CreateWindowExA(WS_EX_TOPMOST, wc.lpszClassName, "Books", WS_OVERLAPPEDWINDOW,
                               CW_USEDEFAULT, CW_USEDEFAULT, 560, 520, NULL, NULL, wc.hInstance, NULL);
    ShowWindow(win, SW_SHOW);
    SetForegroundWindow(win);
    MSG msg;
    while (GetMessageA(&msg, NULL, 0, 0) > 0) {
        TranslateMessage(&msg);
        DispatchMessageA(&msg);
    }
    return xstrdup(g_choice >= 0 ? books->v[g_choice].name : "");
}
#else

static char *pick_menu(const Books *books)
{
    const char *const *menus[] = {
        ARGV("dmenu", "-i", "-l", "25"),
        ARGV("rofi", "-dmenu", "-i", "-l", "25"),
        ARGV("fuzzel", "--dmenu"),
        ARGV("wofi", "--dmenu"),
        NULL,
    };
    for (int i = 0; menus[i]; i++) {
        char *exe = which(menus[i][0]);
        if (!exe) continue;
        free(exe);
        char *names = names_text(books), *r = pipe_through(menus[i], names);
        free(names);
        return r ? chomp(r) : xstrdup("");
    }
    char *zenity = which("zenity");
    if (zenity) {
        const char **argv = xmalloc(sizeof(char *) * (size_t)(books->n + 8));
        int n = 0;
        argv[n++] = "zenity"; argv[n++] = "--list"; argv[n++] = "--title=Books";
        argv[n++] = "--column=Book"; argv[n++] = "--hide-header";
        argv[n++] = "--width=560"; argv[n++] = "--height=520";
        for (int i = 0; i < books->n; i++) argv[n++] = books->v[i].name;
        argv[n] = NULL;
        char *r = output(argv);
        free(argv);
        free(zenity);
        return r ? chomp(r) : xstrdup("");
    }
    return NULL;
}

static char *pick_macos(const Books *books)
{
    Buf script = {0};
    buf_add(&script, "choose from list {");
    for (int i = 0; i < books->n; i++) {
        char *a = str_replace(books->v[i].name, "\\", "\\\\"), *b = str_replace(a, "\"", "\\\"");
        buf_addf(&script, "%s\"%s\"", i ? ", " : "", b);
        free(a);
        free(b);
    }
    buf_add(&script, "} with title \"Books\" with prompt \"Open which book?\"");
    char *r = chomp(output(ARGV("osascript", "-e", buf_str(&script))));
    if (r && streq(r, "false")) r[0] = 0;
    return r ? r : xstrdup("");
}

static char *pick_terminal(const Books *books)
{
    if (!stdin_tty()) return xstrdup("");
    char *fzf = which("fzf");
    if (fzf) {
        free(fzf);
        char *names = names_text(books), *r = pipe_through(ARGV("fzf", "-i"), names);
        free(names);
        return r ? chomp(r) : xstrdup("");
    }
    for (int i = 0; i < books->n; i++) printf("%3d  %s\n", i + 1, books->v[i].name);
    printf("book #: ");
    fflush(stdout);
    char line[32];
    int n = fgets(line, sizeof line, stdin) ? atoi(line) : 0;
    return xstrdup(n > 0 && n <= books->n ? books->v[n - 1].name : "");
}
#endif

int booklister_main(void)
{
    const char *env = getenv("CAIN_BOOKS_DIR");
    char *dir = env && *env ? xstrdup(env) : expand("~/Desktop/books");
    if (!is_dir(dir)) die("no books folder at %s (set CAIN_BOOKS_DIR to change it)", dir);
    Books books = {0};
    scan(&books, dir);
    if (!books.n) die("no books in %s", dir);
    qsort(books.v, (size_t)books.n, sizeof(Book), by_name);

    char *choice;
#ifdef _WIN32
    choice = pick_windows(&books);
#else
    if (streq(OS_NATIVE, "macos")) choice = pick_macos(&books);
    else if (!(choice = pick_menu(&books))) choice = pick_terminal(&books);
#endif
    for (int i = 0; *choice && i < books.n; i++)
        if (streq(books.v[i].name, choice)) open_path(books.v[i].path);
    return 0;
}

int listlauncher_main(void)
{
    const char *env = getenv("CAIN_SITE_DIR"), *editor = getenv("EDITOR");
    char *site = env && *env ? xstrdup(env) : expand("~/Desktop/rhettapplestone.com");
    if (change_dir(site) != 0) die("can't open %s (set CAIN_SITE_DIR to change it)", site);
    run(ARGV(editor && *editor ? editor : "micro", "list.html"), 0);
    run(ARGV("git", "add", "."), 0);
    run(ARGV("git", "commit", "-m", "qcom"), 0);
    run(ARGV("git", "push"), 0);
    return 0;
}
