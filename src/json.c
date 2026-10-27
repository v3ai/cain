/* A small JSON parser/writer: enough for cain.json and karabiner.json.
 * Objects keep their key order; output matches Python's json.dumps(indent=N). */
#include "cain.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct { const char *p, *start; char *err; } Parser;

static Json *parse_value(Parser *ps);

Json *json_new(JType t)
{
    Json *j = xmalloc(sizeof *j);
    memset(j, 0, sizeof *j);
    j->t = t;
    return j;
}

Json *json_new_str(const char *s)
{
    Json *j = json_new(J_STR);
    j->str = xstrdup(s);
    return j;
}

static void add_item(Json *j, char *key, Json *val)
{
    if (j->n + 1 > j->cap) {
        j->cap = j->cap ? j->cap * 2 : 4;
        j->items = xrealloc(j->items, sizeof(Json *) * (size_t)j->cap);
        if (j->t == J_OBJ) j->keys = xrealloc(j->keys, sizeof(char *) * (size_t)j->cap);
    }
    if (j->t == J_OBJ) j->keys[j->n] = key;
    j->items[j->n++] = val;
}

void json_push(Json *arr, Json *val) { add_item(arr, NULL, val); }

void json_set(Json *obj, const char *key, Json *val)
{
    for (int i = 0; i < obj->n; i++)
        if (streq(obj->keys[i], key)) {
            obj->items[i] = val;
            return;
        }
    add_item(obj, xstrdup(key), val);
}

Json *json_get(const Json *obj, const char *key)
{
    if (!obj || obj->t != J_OBJ) return NULL;
    for (int i = 0; i < obj->n; i++)
        if (streq(obj->keys[i], key)) return obj->items[i];
    return NULL;
}

int json_has(const Json *obj, const char *key) { return json_get(obj, key) != NULL; }

const char *json_str(const Json *obj, const char *key, const char *def)
{
    Json *v = json_get(obj, key);
    return v && v->t == J_STR ? v->str : def;
}

int json_bool(const Json *obj, const char *key, int def)
{
    Json *v = json_get(obj, key);
    return v && v->t == J_BOOL ? v->b : def;
}

/* ------------------------------------------------------------------ parsing */

static void fail(Parser *ps, const char *msg)
{
    if (ps->err) return;
    int line = 1;
    for (const char *q = ps->start; q < ps->p; q++) line += *q == '\n';
    ps->err = xprintf("line %d: %s", line, msg);
}

static void skip_ws(Parser *ps)
{
    while (*ps->p == ' ' || *ps->p == '\t' || *ps->p == '\n' || *ps->p == '\r') ps->p++;
}

static void put_utf8(Buf *b, unsigned cp)
{
    if (cp < 0x80) {
        buf_addc(b, (char)cp);
    } else if (cp < 0x800) {
        buf_addc(b, (char)(0xC0 | (cp >> 6)));
        buf_addc(b, (char)(0x80 | (cp & 0x3F)));
    } else if (cp < 0x10000) {
        buf_addc(b, (char)(0xE0 | (cp >> 12)));
        buf_addc(b, (char)(0x80 | ((cp >> 6) & 0x3F)));
        buf_addc(b, (char)(0x80 | (cp & 0x3F)));
    } else {
        buf_addc(b, (char)(0xF0 | (cp >> 18)));
        buf_addc(b, (char)(0x80 | ((cp >> 12) & 0x3F)));
        buf_addc(b, (char)(0x80 | ((cp >> 6) & 0x3F)));
        buf_addc(b, (char)(0x80 | (cp & 0x3F)));
    }
}

static int hex4(const char *p, unsigned *out)
{
    unsigned v = 0;
    for (int i = 0; i < 4; i++) {
        char c = p[i];
        v <<= 4;
        if (c >= '0' && c <= '9') v |= (unsigned)(c - '0');
        else if (c >= 'a' && c <= 'f') v |= (unsigned)(c - 'a' + 10);
        else if (c >= 'A' && c <= 'F') v |= (unsigned)(c - 'A' + 10);
        else return -1;
    }
    *out = v;
    return 0;
}

static char *parse_string(Parser *ps)
{
    Buf b = {0};
    ps->p++; /* opening quote */
    for (;;) {
        char c = *ps->p;
        if (!c) { fail(ps, "unterminated string"); return NULL; }
        ps->p++;
        if (c == '"') break;
        if (c != '\\') { buf_addc(&b, c); continue; }
        c = *ps->p++;
        switch (c) {
        case '"': case '\\': case '/': buf_addc(&b, c); break;
        case 'b': buf_addc(&b, '\b'); break;
        case 'f': buf_addc(&b, '\f'); break;
        case 'n': buf_addc(&b, '\n'); break;
        case 'r': buf_addc(&b, '\r'); break;
        case 't': buf_addc(&b, '\t'); break;
        case 'u': {
            unsigned cp, lo;
            if (hex4(ps->p, &cp)) { fail(ps, "bad \\u escape"); return NULL; }
            ps->p += 4;
            if (cp >= 0xD800 && cp < 0xDC00 && ps->p[0] == '\\' && ps->p[1] == 'u' &&
                !hex4(ps->p + 2, &lo) && lo >= 0xDC00 && lo < 0xE000) {
                cp = 0x10000 + ((cp - 0xD800) << 10) + (lo - 0xDC00);
                ps->p += 6;
            }
            put_utf8(&b, cp);
            break;
        }
        default: fail(ps, "bad escape"); return NULL;
        }
    }
    return b.s ? b.s : xstrdup("");
}

static Json *parse_value(Parser *ps)
{
    skip_ws(ps);
    char c = *ps->p;
    if (c == '{' || c == '[') {
        int obj = c == '{';
        Json *j = json_new(obj ? J_OBJ : J_ARR);
        ps->p++;
        skip_ws(ps);
        if (*ps->p == (obj ? '}' : ']')) { ps->p++; return j; }
        for (;;) {
            char *key = NULL;
            skip_ws(ps);
            if (obj) {
                if (*ps->p != '"') { fail(ps, "expected a \"key\""); return NULL; }
                if (!(key = parse_string(ps))) return NULL;
                skip_ws(ps);
                if (*ps->p++ != ':') { fail(ps, "expected ':'"); return NULL; }
            }
            Json *v = parse_value(ps);
            if (!v) return NULL;
            add_item(j, key, v);
            skip_ws(ps);
            if (*ps->p == ',') { ps->p++; continue; }
            if (*ps->p == (obj ? '}' : ']')) { ps->p++; return j; }
            fail(ps, obj ? "expected ',' or '}'" : "expected ',' or ']'");
            return NULL;
        }
    }
    if (c == '"') {
        char *s = parse_string(ps);
        if (!s) return NULL;
        Json *j = json_new(J_STR);
        j->str = s;
        return j;
    }
    if (starts_with(ps->p, "true")) { ps->p += 4; Json *j = json_new(J_BOOL); j->b = 1; return j; }
    if (starts_with(ps->p, "false")) { ps->p += 5; return json_new(J_BOOL); }
    if (starts_with(ps->p, "null")) { ps->p += 4; return json_new(J_NULL); }
    if (c == '-' || (c >= '0' && c <= '9')) {
        char *end;
        Json *j = json_new(J_NUM);
        j->num = strtod(ps->p, &end);
        if (end == ps->p) { fail(ps, "bad number"); return NULL; }
        j->str = xmalloc((size_t)(end - ps->p) + 1);  /* keep the original text: 1.0 stays 1.0 */
        memcpy(j->str, ps->p, (size_t)(end - ps->p));
        j->str[end - ps->p] = 0;
        ps->p = end;
        return j;
    }
    fail(ps, "unexpected character");
    return NULL;
}

Json *json_parse(const char *text, char **err)
{
    Parser ps = {text, text, NULL};
    Json *j = parse_value(&ps);
    if (j) {
        skip_ws(&ps);
        if (*ps.p) { fail(&ps, "trailing characters"); j = NULL; }
    }
    if (err) *err = ps.err;
    return ps.err ? NULL : j;
}

/* ------------------------------------------------------------------ writing */

static unsigned next_cp(const unsigned char **p)
{
    const unsigned char *s = *p;
    unsigned cp = *s;
    int extra = cp >= 0xF0 ? 3 : cp >= 0xE0 ? 2 : cp >= 0xC0 ? 1 : 0;
    if (extra) cp &= 0x3F >> extra;
    s++;
    for (int i = 0; i < extra && (*s & 0xC0) == 0x80; i++) cp = (cp << 6) | (*s++ & 0x3F);
    *p = s;
    return cp;
}

static void write_string(Buf *out, const char *s)
{
    buf_addc(out, '"');
    const unsigned char *p = (const unsigned char *)s;
    while (*p) {
        unsigned c = *p;
        if (c == '"') { buf_add(out, "\\\""); p++; }
        else if (c == '\\') { buf_add(out, "\\\\"); p++; }
        else if (c == '\n') { buf_add(out, "\\n"); p++; }
        else if (c == '\r') { buf_add(out, "\\r"); p++; }
        else if (c == '\t') { buf_add(out, "\\t"); p++; }
        else if (c == '\b') { buf_add(out, "\\b"); p++; }
        else if (c == '\f') { buf_add(out, "\\f"); p++; }
        else if (c < 0x20) { buf_addf(out, "\\u%04x", c); p++; }
        else if (c < 0x80) { buf_addc(out, (char)c); p++; }
        else {
            unsigned cp = next_cp(&p);
            if (cp >= 0x10000) {
                cp -= 0x10000;
                buf_addf(out, "\\u%04x\\u%04x", 0xD800 + (cp >> 10), 0xDC00 + (cp & 0x3FF));
            } else {
                buf_addf(out, "\\u%04x", cp);
            }
        }
    }
    buf_addc(out, '"');
}

static void newline(Buf *out, int indent, int depth)
{
    buf_addc(out, '\n');
    for (int i = 0; i < indent * depth; i++) buf_addc(out, ' ');
}

static void write_value(Buf *out, const Json *j, int indent, int depth)
{
    switch (j->t) {
    case J_NULL: buf_add(out, "null"); break;
    case J_BOOL: buf_add(out, j->b ? "true" : "false"); break;
    case J_NUM:
        if (j->str) buf_add(out, j->str);
        else if (j->num == floor(j->num) && fabs(j->num) < 1e15) buf_addf(out, "%.0f", j->num);
        else buf_addf(out, "%.17g", j->num);
        break;
    case J_STR: write_string(out, j->str); break;
    case J_ARR:
    case J_OBJ: {
        int obj = j->t == J_OBJ;
        if (!j->n) { buf_add(out, obj ? "{}" : "[]"); break; }
        buf_addc(out, obj ? '{' : '[');
        for (int i = 0; i < j->n; i++) {
            if (i) buf_addc(out, ',');
            if (indent) newline(out, indent, depth + 1);
            else if (i) buf_addc(out, ' ');
            if (obj) {
                write_string(out, j->keys[i]);
                buf_add(out, ": ");
            }
            write_value(out, j->items[i], indent, depth + 1);
        }
        if (indent) newline(out, indent, depth);
        buf_addc(out, obj ? '}' : ']');
        break;
    }
    }
}

void json_write(Buf *out, const Json *j, int indent) { write_value(out, j, indent, 0); }
