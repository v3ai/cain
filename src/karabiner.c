/* macOS key remaps + shortcuts through Karabiner-Elements complex modifications. */
#include "cain.h"

#include <stdlib.h>
#include <string.h>

#define KARABINER_CONFIG "~/.config/karabiner/karabiner.json"
#define MISSION_CONTROL "'/System/Applications/Mission Control.app/Contents/MacOS/Mission Control'"

/* How each window-manager action is done on macOS: a key combo (+ extra modifier) or a shell command. */
typedef struct { const char *action; Combo combo; const char *extra; const char *shell; } MacAction;

static const MacAction WM[] = {
    {"close_window", {M_SUPER, "w"}, NULL, NULL},
    {"minimize", {M_SUPER, "m"}, NULL, NULL},
    {"toggle_maximize", {M_CTRL, "f"}, "fn", NULL},     /* Window > Fill (macOS 15+) */
    {"tile_left", {M_CTRL, "left"}, "fn", NULL},        /* Window > Move & Resize > Left */
    {"tile_right", {M_CTRL, "right"}, "fn", NULL},
    {"switch_windows", {M_SUPER, "tab"}, NULL, NULL},
    {"lock_screen", {M_CTRL | M_SUPER, "q"}, NULL, NULL},
    {"show_desktop", {0, NULL}, NULL, MISSION_CONTROL " 1"},
    {NULL, {0, NULL}, NULL, NULL},
};

static Json *manipulator(Json *from, Json *to)
{
    Json *m = json_new(J_OBJ);
    json_set(m, "type", json_new_str("basic"));
    json_set(m, "from", from);
    json_set(m, "to", to);
    return m;
}

static Json *rule(const char *description, Json *manipulators)
{
    Json *r = json_new(J_OBJ);
    json_set(r, "description", json_new_str(description));
    json_set(r, "manipulators", manipulators);
    return r;
}

/* The list of Karabiner rules cain owns. */
Json *karabiner_generate(const Manifest *m)
{
    static const char *const any[] = {"any", NULL};
    static const char *const caps_shift[] = {"caps_lock", "shift", NULL};
    static const char *const caps[] = {"caps_lock", NULL};
    Json *rules = json_new(J_ARR);

    for (int i = 0; i < m->nremaps; i++) {
        Combo src = m->remaps[i].from, dst = m->remaps[i].to;
        const char *const *optional = !src.mods ? any : !dst.mods ? caps_shift : caps;
        Json *to = json_new(J_ARR), *manips = json_new(J_ARR);
        json_push(to, karabiner_to(dst, NULL));
        json_push(manips, manipulator(karabiner_from(src, optional), to));
        char *a = combo_str(src), *b = combo_str(dst);
        char *desc = xprintf("%s%s -> %s", KARABINER_TAG, a, b);
        json_push(rules, rule(desc, manips));
        free(a);
        free(b);
        free(desc);
    }

    for (int i = 0; i < m->nshortcuts; i++) {
        const Shortcut *sc = &m->shortcuts[i];
        const MacAction *wm = NULL;
        for (int n = 0; WM[n].action; n++)
            if (streq(WM[n].action, sc->action)) wm = &WM[n];
        Json *to = json_new(J_ARR);
        if (wm && !wm->shell) {
            json_push(to, karabiner_to(wm->combo, wm->extra));
        } else {
            char *cmd = wm ? xstrdup(wm->shell) : launch_command(sc, "macos", m);
            if (!cmd) continue;  /* a "run" shortcut with no macOS command */
            Json *sh = json_new(J_OBJ);
            json_set(sh, "shell_command", json_new_str(cmd));
            json_push(to, sh);
            free(cmd);
        }
        Json *manips = json_new(J_ARR);
        Buf keys = {0};
        for (int k = 0; k < sc->nkeys; k++) {
            char *cs = combo_str(sc->keys[k]);
            buf_addf(&keys, "%s%s", k ? ", " : "", cs);
            free(cs);
            json_push(manips, manipulator(karabiner_from(sc->keys[k], caps), to));
        }
        char *desc = xprintf("%s%s (%s)", KARABINER_TAG, sc->action, buf_str(&keys));
        json_push(rules, rule(desc, manips));
        free(desc);
    }
    return rules;
}

void karabiner_apply(const Manifest *m)
{
    if (!is_dir("/Applications/Karabiner-Elements.app")) {
        StrList pkgs = {0};
        sl_push(&pkgs, "--cask karabiner-elements");
        brew_install(&pkgs);
    }
    char *path = expand(KARABINER_CONFIG);
    Json *config = NULL;
    char *text = read_file(path, NULL);
    if (text) {
        char *err;
        config = json_parse(text, &err);
        if (!config || config->t != J_OBJ) {
            warn("%s isn't valid JSON (%s); leaving it alone", path, err ? err : "not an object");
            return;
        }
    } else {
        config = json_new(J_OBJ);
    }

    Json *profiles = json_get(config, "profiles");
    if (!profiles || profiles->t != J_ARR || !profiles->n) {
        profiles = json_new(J_ARR);
        Json *p = json_new(J_OBJ), *yes = json_new(J_BOOL);
        yes->b = 1;
        json_set(p, "name", json_new_str("Default profile"));
        json_set(p, "selected", yes);
        json_push(profiles, p);
        json_set(config, "profiles", profiles);
    }
    Json *profile = profiles->items[0];
    for (int i = 0; i < profiles->n; i++)
        if (json_bool(profiles->items[i], "selected", 0)) { profile = profiles->items[i]; break; }

    Json *cm = json_get(profile, "complex_modifications");
    if (!cm || cm->t != J_OBJ) { cm = json_new(J_OBJ); json_set(profile, "complex_modifications", cm); }
    Json *old = json_get(cm, "rules");

    /* cain's rules first (Karabiner gives earlier rules priority), then everything else kept */
    Json *rules = karabiner_generate(m);
    for (int i = 0; old && old->t == J_ARR && i < old->n; i++)
        if (!starts_with(json_str(old->items[i], "description", ""), KARABINER_TAG))
            json_push(rules, old->items[i]);
    json_set(cm, "rules", rules);

    Buf out = {0};
    json_write(&out, config, 4);
    buf_addc(&out, '\n');
    write_text(path, out.s, 0);
    info("  Karabiner reloads this automatically. The first time, open Karabiner-Elements and\n"
         "  allow its Input Monitoring / driver permissions in System Settings > Privacy & Security.");
}
