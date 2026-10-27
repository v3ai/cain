/* Loads cain.json and filters its entries for the current OS / desktop. */
#include "cain.h"

#include <stdlib.h>
#include <string.h>

static int list_has(const Json *arr, const char *s)
{
    if (!arr || arr->t != J_ARR) return 0;
    for (int i = 0; i < arr->n; i++)
        if (arr->items[i]->t == J_STR && streq(arr->items[i]->str, s)) return 1;
    return 0;
}

int manifest_applies(const Json *entry, const char *os, const char *desktop)
{
    if (json_has(entry, "os") && !list_has(json_get(entry, "os"), os)) return 0;
    if (json_has(entry, "desktop") &&
        (!streq(os, "linux") || !list_has(json_get(entry, "desktop"), desktop)))
        return 0;
    return 1;
}

const char *setting(const Manifest *m, const char *key, const char *def)
{
    return json_str(m->settings, key, def);
}

static Combo input_combo(const Manifest *m, const char *text, const char *os)
{
    Combo c = combo_must(text);
    if (streq(os, "macos") && streq(setting(m, "mac_alt", "option"), "command"))
        c = mac_swap_alt_cmd(c);
    return c;
}

Manifest *manifest_load(const char *os)
{
    char *path = path_join(g_root, "cain.json"), *err = NULL;
    char *text = read_file(path, NULL);
    if (!text) die("can't read %s", path);
    Manifest *m = xmalloc(sizeof *m);
    memset(m, 0, sizeof *m);
    m->root = json_parse(text, &err);
    if (!m->root) die("%s: %s", path, err);
    if (m->root->t != J_OBJ) die("%s: expected a JSON object", path);
    m->settings = json_get(m->root, "settings");
    if (!m->settings) m->settings = json_new(J_OBJ);
    m->git = json_get(m->root, "git");
    if (!m->git) m->git = json_new(J_OBJ);

    /* remaps, with per-OS overrides and macOS translation applied */
    Json *remaps = json_get(m->root, "remaps");
    m->remaps = xmalloc(sizeof(Remap) * (size_t)(remaps ? remaps->n : 0));
    for (int i = 0; remaps && i < remaps->n; i++) {
        Json *r = remaps->items[i];
        if (!manifest_applies(r, os, "")) continue;
        const char *from = json_str(r, "from", NULL), *to = json_str(r, "to", NULL);
        if (!from || !to) die("cain.json: every remap needs \"from\" and \"to\"");
        Remap rm;
        rm.from = input_combo(m, from, os);
        Json *override = json_get(r, os);  /* e.g. "macos": "cmd+shift+v", or null to skip */
        if (override) {
            if (override->t != J_STR) continue;
            rm.to = combo_must(override->str);
        } else {
            rm.to = combo_must(to);
            if (streq(os, "macos") && json_bool(m->settings, "mac_translate", 1))
                rm.to = mac_translate(rm.to);
        }
        if (combo_eq(rm.from, rm.to)) continue;  /* e.g. Cmd+M -> Cmd+M after translation */
        m->remaps[m->nremaps++] = rm;
    }

    Json *shortcuts = json_get(m->root, "shortcuts");
    m->shortcuts = xmalloc(sizeof(Shortcut) * (size_t)(shortcuts ? shortcuts->n : 0));
    for (int i = 0; shortcuts && i < shortcuts->n; i++) {
        Json *s = shortcuts->items[i], *keys = json_get(s, "keys");
        if (!manifest_applies(s, os, "")) continue;
        Shortcut sc;
        sc.entry = s;
        sc.action = json_str(s, "action", NULL);
        if (!sc.action || !keys || keys->t != J_ARR)
            die("cain.json: every shortcut needs \"action\" and a \"keys\" list");
        sc.nkeys = keys->n;
        sc.keys = xmalloc(sizeof(Combo) * (size_t)keys->n);
        for (int k = 0; k < keys->n; k++) {
            if (keys->items[k]->t != J_STR) die("cain.json: shortcut keys must be strings");
            sc.keys[k] = input_combo(m, keys->items[k]->str, os);
        }
        m->shortcuts[m->nshortcuts++] = sc;
    }
    free(text);
    free(path);
    return m;
}
