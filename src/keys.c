/* Platform-neutral key combos and the tables that translate them for each backend.
 *
 * Combos are written like "alt+h", "lalt+quote", "ctrl+shift+tab", "super+d".
 *
 * Modifiers: alt, lalt, ralt, ctrl, lctrl, rctrl, shift, super, lsuper, rsuper
 *            (alt/ctrl/super = either side; super = Windows key / Cmd / Meta)
 * Keys:      a-z, 0-9, f1-f12, comma, period, slash, semicolon, quote,
 *            bracketleft, bracketright, backslash, minus, equal, grave,
 *            tab, enter, esc, backspace, delete, space, capslock,
 *            left, right, up, down, home, end, pageup, pagedown
 */
#include "cain.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Bit order is the order modifiers are printed in. */
const char *const MOD_NAMES[M_COUNT] = {
    "super", "lsuper", "rsuper", "ctrl", "lctrl", "rctrl", "alt", "lalt", "ralt", "shift",
};

static const char *const NAMED_KEYS[] = {
    "comma", "period", "slash", "semicolon", "quote", "bracketleft", "bracketright",
    "backslash", "minus", "equal", "grave", "tab", "enter", "esc", "backspace", "delete",
    "space", "capslock", "left", "right", "up", "down", "home", "end", "pageup", "pagedown",
    "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q",
    "r", "s", "t", "u", "v", "w", "x", "y", "z",
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
    "f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12", NULL,
};

typedef struct { const char *from, *to; } Pair;

static const char *lookup(const Pair *table, const char *key, const char *fallback)
{
    for (; table->from; table++)
        if (streq(table->from, key)) return table->to;
    return fallback;
}

static const Pair ALIASES[] = {
    {"escape", "esc"}, {"return", "enter"}, {"dot", "period"}, {"apostrophe", "quote"},
    {"leftbrace", "bracketleft"}, {"rightbrace", "bracketright"}, {"control", "ctrl"},
    {"win", "super"}, {"cmd", "super"}, {"meta", "super"}, {"option", "alt"},
    {"caps", "capslock"}, {"bksp", "backspace"}, {"del", "delete"}, {NULL, NULL},
};

static int is_fkey(const char *key) { return key[0] == 'f' && key[1] >= '1' && key[1] <= '9'; }

static unsigned mod_bit(const char *name)
{
    for (int i = 0; i < M_COUNT; i++)
        if (streq(MOD_NAMES[i], name)) return 1u << i;
    return 0;
}

int combo_parse(const char *text, Combo *out)
{
    char *s = str_lower(text), *tok, *next;
    Buf clean = {0};
    for (char *p = s; *p; p++)
        if (*p != ' ') buf_addc(&clean, *p);
    free(s);
    out->mods = 0;
    out->key = NULL;
    for (tok = clean.s; tok; tok = next) {
        next = strchr(tok, '+');
        if (next) *next++ = 0;
        const char *name = lookup(ALIASES, tok, tok);
        if (next) {
            unsigned bit = mod_bit(name);
            if (!bit) { free(clean.s); return -1; }
            out->mods |= bit;
        } else {
            for (int i = 0; NAMED_KEYS[i]; i++)
                if (streq(NAMED_KEYS[i], name)) out->key = NAMED_KEYS[i];
            if (!out->key) { free(clean.s); return -1; }
        }
    }
    free(clean.s);
    return out->key ? 0 : -1;
}

Combo combo_must(const char *text)
{
    Combo c;
    if (combo_parse(text, &c) != 0) die("cain.json: can't understand the key combo \"%s\"", text);
    return c;
}

int combo_eq(Combo a, Combo b) { return a.mods == b.mods && streq(a.key, b.key); }

/* Modifiers with the left/right distinction dropped. */
unsigned generic_mods(unsigned m)
{
    unsigned g = m & (M_SUPER | M_CTRL | M_ALT | M_SHIFT);
    if (m & (M_LSUPER | M_RSUPER)) g |= M_SUPER;
    if (m & (M_LCTRL | M_RCTRL)) g |= M_CTRL;
    if (m & (M_LALT | M_RALT)) g |= M_ALT;
    return g;
}

char *combo_str(Combo c)
{
    Buf b = {0};
    for (int i = 0; i < M_COUNT; i++)
        if (c.mods & (1u << i)) buf_addf(&b, "%s+", MOD_NAMES[i]);
    buf_add(&b, c.key);
    return b.s;
}

/* For *input* combos on a Mac keyboard: the key under your thumb is Command, so
 * treat Command as the PC's Alt (and Option as the PC's Super). */
Combo mac_swap_alt_cmd(Combo c)
{
    static const unsigned pairs[][2] = {
        {M_ALT, M_SUPER}, {M_LALT, M_LSUPER}, {M_RALT, M_RSUPER},
        {M_SUPER, M_ALT}, {M_LSUPER, M_LALT}, {M_RSUPER, M_RALT},
    };
    unsigned m = c.mods & ~(unsigned)(M_ANY_ALT | M_SUPER | M_LSUPER | M_RSUPER);
    for (int i = 0; i < 6; i++)
        if (c.mods & pairs[i][0]) m |= pairs[i][1];
    c.mods = m;
    return c;
}

/* Rewrite a Linux/Windows-style *output* combo into the macOS equivalent:
 * ctrl+c -> cmd+c, ctrl+left -> option+left, home -> cmd+left, end -> cmd+right.
 * ctrl+tab / ctrl+shift+tab stay as they are (they switch tabs on macOS too). */
Combo mac_translate(Combo c)
{
    unsigned ctrl = c.mods & M_ANY_CTRL;
    if (!c.mods && streq(c.key, "home")) return (Combo){M_SUPER, "left"};
    if (!c.mods && streq(c.key, "end")) return (Combo){M_SUPER, "right"};
    if (ctrl && (streq(c.key, "left") || streq(c.key, "right")))
        return (Combo){(c.mods & ~ctrl) | M_ALT, c.key};
    if (ctrl && !streq(c.key, "tab")) return (Combo){(c.mods & ~ctrl) | M_SUPER, c.key};
    return c;
}

/* ---------------------------------------------------------------- keyd (Linux) */

static const Pair KEYD_KEYS[] = {
    {"period", "dot"}, {"quote", "apostrophe"}, {"bracketleft", "leftbrace"},
    {"bracketright", "rightbrace"}, {NULL, NULL},
};

const char *keyd_key(const char *key) { return lookup(KEYD_KEYS, key, key); }

char *keyd_output(Combo c)
{
    Buf b = {0};
    unsigned g = generic_mods(c.mods);
    if (g & M_SUPER) buf_add(&b, "M-");
    if (g & M_CTRL) buf_add(&b, "C-");
    if (g & M_ALT) buf_add(&b, "A-");
    if (g & M_SHIFT) buf_add(&b, "S-");
    buf_add(&b, keyd_key(c.key));
    return b.s;
}

/* ---------------------------------------------------------- AutoHotkey (Windows) */

static const Pair AHK_KEYS[] = {
    {"comma", "vkBC"}, {"period", "vkBE"}, {"slash", "vkBF"}, {"semicolon", "vkBA"},
    {"quote", "vkDE"}, {"bracketleft", "vkDB"}, {"bracketright", "vkDD"},
    {"backslash", "vkDC"}, {"minus", "vkBD"}, {"equal", "vkBB"}, {"grave", "vkC0"},
    {"tab", "Tab"}, {"enter", "Enter"}, {"esc", "Esc"}, {"backspace", "Backspace"},
    {"delete", "Delete"}, {"space", "Space"}, {"capslock", "CapsLock"}, {"left", "Left"},
    {"right", "Right"}, {"up", "Up"}, {"down", "Down"}, {"home", "Home"}, {"end", "End"},
    {"pageup", "PgUp"}, {"pagedown", "PgDn"}, {NULL, NULL},
};

static const char *const AHK_HOTKEY_MODS[M_COUNT] = {
    "#", "<#", ">#", "^", "<^", ">^", "!", "<!", ">!", "+",
};

char *ahk_key(const char *key)
{
    const char *k = lookup(AHK_KEYS, key, NULL);
    if (k) return xstrdup(k);
    return is_fkey(key) ? str_upper(key) : xstrdup(key);
}

char *ahk_hotkey(Combo c)
{
    Buf b = {0};
    for (int i = 0; i < M_COUNT; i++)
        if (c.mods & (1u << i)) buf_add(&b, AHK_HOTKEY_MODS[i]);
    char *k = ahk_key(c.key);
    buf_add(&b, k);
    free(k);
    return b.s;
}

char *ahk_send(Combo c)
{
    Buf b = {0};
    unsigned g = generic_mods(c.mods);
    if (g & M_SUPER) buf_add(&b, "#");
    if (g & M_CTRL) buf_add(&b, "^");
    if (g & M_ALT) buf_add(&b, "!");
    if (g & M_SHIFT) buf_add(&b, "+");
    char *k = ahk_key(c.key);
    if (strlen(k) > 1) buf_addf(&b, "{%s}", k);
    else buf_add(&b, k);
    free(k);
    return b.s;
}

/* ------------------------------------------------------ Karabiner-Elements (macOS) */

static const Pair KARABINER_KEYS[] = {
    {"bracketleft", "open_bracket"}, {"bracketright", "close_bracket"}, {"minus", "hyphen"},
    {"equal", "equal_sign"}, {"grave", "grave_accent_and_tilde"}, {"enter", "return_or_enter"},
    {"esc", "escape"}, {"backspace", "delete_or_backspace"}, {"delete", "delete_forward"},
    {"space", "spacebar"}, {"capslock", "caps_lock"}, {"left", "left_arrow"},
    {"right", "right_arrow"}, {"up", "up_arrow"}, {"down", "down_arrow"},
    {"pageup", "page_up"}, {"pagedown", "page_down"}, {NULL, NULL},
};

static const char *const KARABINER_FROM_MODS[M_COUNT] = {
    "command", "left_command", "right_command", "control", "left_control", "right_control",
    "option", "left_option", "right_option", "shift",
};

const char *karabiner_key(const char *key) { return lookup(KARABINER_KEYS, key, key); }

Json *karabiner_from(Combo c, const char *const *optional)
{
    Json *from = json_new(J_OBJ), *mods = json_new(J_OBJ), *opt = json_new(J_ARR);
    json_set(from, "key_code", json_new_str(karabiner_key(c.key)));
    for (; *optional; optional++) json_push(opt, json_new_str(*optional));
    json_set(mods, "optional", opt);
    if (c.mods) {
        Json *mand = json_new(J_ARR);
        for (int i = 0; i < M_COUNT; i++)
            if (c.mods & (1u << i)) json_push(mand, json_new_str(KARABINER_FROM_MODS[i]));
        json_set(mods, "mandatory", mand);
    }
    json_set(from, "modifiers", mods);
    return from;
}

Json *karabiner_to(Combo c, const char *extra_mod)
{
    Json *to = json_new(J_OBJ), *mods = json_new(J_ARR);
    unsigned g = generic_mods(c.mods);
    json_set(to, "key_code", json_new_str(karabiner_key(c.key)));
    if (g & M_SUPER) json_push(mods, json_new_str("left_command"));
    if (g & M_CTRL) json_push(mods, json_new_str("left_control"));
    if (g & M_ALT) json_push(mods, json_new_str("left_option"));
    if (g & M_SHIFT) json_push(mods, json_new_str("left_shift"));
    if (extra_mod) json_push(mods, json_new_str(extra_mod));
    if (mods->n) json_set(to, "modifiers", mods);
    return to;
}

/* -------------------------------------------- GTK accelerators (GNOME, Cinnamon, XFCE) */

static const Pair GTK_KEYS[] = {
    {"quote", "apostrophe"}, {"tab", "Tab"}, {"enter", "Return"}, {"esc", "Escape"},
    {"backspace", "BackSpace"}, {"delete", "Delete"}, {"capslock", "Caps_Lock"},
    {"left", "Left"}, {"right", "Right"}, {"up", "Up"}, {"down", "Down"}, {"home", "Home"},
    {"end", "End"}, {"pageup", "Page_Up"}, {"pagedown", "Page_Down"}, {NULL, NULL},
};

char *gtk_accel(Combo c)
{
    Buf b = {0};
    unsigned g = generic_mods(c.mods);
    if (g & M_SUPER) buf_add(&b, "<Super>");
    if (g & M_CTRL) buf_add(&b, "<Primary>");
    if (g & M_ALT) buf_add(&b, "<Alt>");
    if (g & M_SHIFT) buf_add(&b, "<Shift>");
    if (is_fkey(c.key)) {
        char *k = str_upper(c.key);
        buf_add(&b, k);
        free(k);
    } else {
        buf_add(&b, lookup(GTK_KEYS, c.key, c.key));
    }
    return b.s;
}

/* ----------------------------------------------------------------- KDE Plasma */

static const Pair KDE_KEYS[] = {
    {"comma", ","}, {"period", "."}, {"slash", "/"}, {"semicolon", ";"}, {"quote", "'"},
    {"bracketleft", "["}, {"bracketright", "]"}, {"backslash", "\\"}, {"minus", "-"},
    {"equal", "="}, {"grave", "`"}, {"tab", "Tab"}, {"enter", "Return"}, {"esc", "Esc"},
    {"backspace", "Backspace"}, {"delete", "Del"}, {"space", "Space"},
    {"capslock", "CapsLock"}, {"left", "Left"}, {"right", "Right"}, {"up", "Up"},
    {"down", "Down"}, {"home", "Home"}, {"end", "End"}, {"pageup", "PgUp"},
    {"pagedown", "PgDown"}, {NULL, NULL},
};

char *kde_accel(Combo c)
{
    Buf b = {0};
    unsigned g = generic_mods(c.mods);
    if (g & M_SUPER) buf_add(&b, "Meta+");
    if (g & M_CTRL) buf_add(&b, "Ctrl+");
    if (g & M_ALT) buf_add(&b, "Alt+");
    if (g & M_SHIFT) buf_add(&b, "Shift+");
    const char *k = lookup(KDE_KEYS, c.key, NULL);
    if (k) {
        buf_add(&b, k);
    } else {
        char *u = str_upper(c.key);
        buf_add(&b, u);
        free(u);
    }
    return b.s;
}
