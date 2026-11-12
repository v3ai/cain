# cain.awk - the part of cain that thinks: it reads cain.json and turns it into
# keyd / AutoHotkey / Karabiner configs, package and file lists, and plans for
# desktop shortcuts. The `cain` shell script does everything that touches the system.
#
# Plain POSIX awk (mawk, gawk, busybox, macOS awk). Run with LC_ALL=C.
#   awk -v mode=<mode> -v os=<linux|macos|windows> -f files/cain/cain.awk
# Inputs come from the environment: CAIN_JSON (path to files/cain.json), HOME, and per mode
# the CAIN_* variables named below. Everything happens in BEGIN.
#
# Modes:
#   check      just load cain.json (exits non-zero with a message if it's broken)
#   generate   print the keybinding config for `os` (what `cain generate` shows)
#   keyd       /etc/keyd/default.conf
#   karabiner  ~/.config/karabiner/karabiner.json with cain's rules merged into
#              CAIN_KARABINER (the existing file, if any)
#   desktop    shell commands that set desktop shortcuts for CAIN_DESKTOP
#              (uses CAIN_TERM, CAIN_CALC, CAIN_EXISTING, CAIN_KDE_TOOL, CAIN_PLASMA6)
#   packages   one line per package: name, skip(0/1), package, fallback, bin (split by \037)
#              for CAIN_PM (or brew on macOS); CAIN_TERMINAL=1 keeps only "terminal" ones
#   files      one line per file: src, dest (split by \037), for CAIN_DESKTOP
#   get        print the value at CAIN_KEY, e.g. git.name or settings.dark_mode

# ---------------------------------------------------------------- messages

function die(msg) {
    printf "cain: %s\n", msg | "cat 1>&2"
    close("cat 1>&2")
    exit 1
}

function warn(msg) { print "  WARNING: " msg }

# ---------------------------------------------------------------- strings

# Replace every `from` with `to` (no regex, no backslash surprises).
function repl(s, from, to,    out, i) {
    out = ""
    while ((i = index(s, from)) > 0) {
        out = out substr(s, 1, i - 1) to
        s = substr(s, i + length(from))
    }
    return out s
}

function spaces(n,    s) { s = ""; while (n-- > 0) s = s " "; return s }

function starts(s, p) { return substr(s, 1, length(p)) == p }

# Quote for sh, the same way cain shows commands.
function shq(s) {
    if (s == "") return "''"
    if (s ~ /^[A-Za-z0-9@%+=:,.\/_-]+$/) return s
    return "'" repl(s, "'", "'\"'\"'") "'"
}

# ---------------------------------------------------------------- JSON
# Nodes are numbers. JT[n] type: o(bject) a(rray) s(tring) n(umber) b(ool) z(null).
# JV[n] value; JC[n] child count; JK[n,i] key (objects), JI[n,i] child.

function jnew(t, v) { JN++; JT[JN] = t; JV[JN] = v; JC[JN] = 0; return JN }
function jstrnode(v) { return jnew("s", v) }
function jpush(a, c) { JC[a]++; JK[a, JC[a]] = ""; JI[a, JC[a]] = c }
function jset(o, k, c,    i) {
    for (i = 1; i <= JC[o]; i++) if (JK[o, i] == k) { JI[o, i] = c; return }
    JC[o]++; JK[o, JC[o]] = k; JI[o, JC[o]] = c
}
function jget(o, k,    i) {
    if (!o || JT[o] != "o") return 0
    for (i = 1; i <= JC[o]; i++) if (JK[o, i] == k) return JI[o, i]
    return 0
}
function jstr(o, k, def,    c) { c = jget(o, k); return c && JT[c] == "s" ? JV[c] : def }
function jbool(o, k, def,    c) { c = jget(o, k); return c && JT[c] == "b" ? JV[c] == "true" : def }
function jhas_str(a, s,    i, c) {
    if (!a || JT[a] != "a") return 0
    for (i = 1; i <= JC[a]; i++) { c = JI[a, i]; if (JT[c] == "s" && JV[c] == s) return 1 }
    return 0
}

function readfile(path,    line, text, r) {
    text = ""
    while ((r = (getline line < path)) > 0) text = text line "\n"
    if (r < 0) return "\001"   # unreadable
    close(path)
    return text
}

function jparse(text,    v) {
    PS = text; PP = 1; PL = length(text); PERR = ""
    v = pval()
    if (PERR == "") { ws(); if (PP <= PL) pfail("trailing characters") }
    return PERR == "" ? v : 0
}

function pfail(msg,    pre) {
    if (PERR != "") return
    pre = substr(PS, 1, PP - 1)
    PERR = "line " (1 + gsub(/\n/, "", pre)) ": " msg
}

function ws(    c) {
    while (PP <= PL) {
        c = substr(PS, PP, 1)
        if (c == " " || c == "\t" || c == "\n" || c == "\r") PP++
        else return
    }
}

function pval(    c, id, obj, endc, key, v, num) {
    ws()
    c = substr(PS, PP, 1)
    if (c == "{" || c == "[") {
        obj = c == "{"
        endc = obj ? "}" : "]"
        id = jnew(obj ? "o" : "a", "")
        PP++
        ws()
        if (substr(PS, PP, 1) == endc) { PP++; return id }
        for (;;) {
            ws()
            key = ""
            if (obj) {
                if (substr(PS, PP, 1) != "\"") { pfail("expected a \"key\""); return 0 }
                key = pstr()
                if (PERR != "") return 0
                ws()
                if (substr(PS, PP++, 1) != ":") { pfail("expected ':'"); return 0 }
            }
            v = pval()
            if (PERR != "") return 0
            JC[id]++; JK[id, JC[id]] = key; JI[id, JC[id]] = v
            ws()
            c = substr(PS, PP, 1)
            if (c == ",") { PP++; continue }
            if (c == endc) { PP++; return id }
            pfail(obj ? "expected ',' or '}'" : "expected ',' or ']'")
            return 0
        }
    }
    if (c == "\"") { v = pstr(); return PERR == "" ? jstrnode(v) : 0 }
    if (substr(PS, PP, 4) == "true") { PP += 4; return jnew("b", "true") }
    if (substr(PS, PP, 5) == "false") { PP += 5; return jnew("b", "false") }
    if (substr(PS, PP, 4) == "null") { PP += 4; return jnew("z", "") }
    if (c == "-" || (c >= "0" && c <= "9")) {
        if (match(substr(PS, PP, 64), /^-?[0-9]+(\.[0-9]+)?([eE][-+]?[0-9]+)?/)) {
            num = substr(PS, PP, RLENGTH)
            PP += RLENGTH
            return jnew("n", num)
        }
        pfail("bad number")
        return 0
    }
    pfail("unexpected character")
    return 0
}

function hex4(s,    i, c, v, d) {
    v = 0
    for (i = 1; i <= 4; i++) {
        c = tolower(substr(s, i, 1))
        d = index("0123456789abcdef", c)
        if (!d || c == "") return -1
        v = v * 16 + d - 1
    }
    return v
}

function utf8(cp) {
    if (cp < 128) return sprintf("%c", cp)
    if (cp < 2048) return sprintf("%c%c", 192 + int(cp / 64), 128 + cp % 64)
    if (cp < 65536) return sprintf("%c%c%c", 224 + int(cp / 4096), 128 + int(cp / 64) % 64, 128 + cp % 64)
    return sprintf("%c%c%c%c", 240 + int(cp / 262144), 128 + int(cp / 4096) % 64, 128 + int(cp / 64) % 64, 128 + cp % 64)
}

function pstr(    out, c, cp, lo) {
    PP++   # opening quote
    out = ""
    for (;;) {
        if (PP > PL) { pfail("unterminated string"); return "" }
        c = substr(PS, PP++, 1)
        if (c == "\"") return out
        if (c != "\\") { out = out c; continue }
        c = substr(PS, PP++, 1)
        if (c == "\"" || c == "\\" || c == "/") out = out c
        else if (c == "b") out = out "\b"
        else if (c == "f") out = out "\f"
        else if (c == "n") out = out "\n"
        else if (c == "r") out = out "\r"
        else if (c == "t") out = out "\t"
        else if (c == "u") {
            cp = hex4(substr(PS, PP, 4))
            if (cp < 0) { pfail("bad \\u escape"); return "" }
            PP += 4
            if (cp >= 55296 && cp < 56320 && substr(PS, PP, 2) == "\\u") {
                lo = hex4(substr(PS, PP + 2, 4))
                if (lo >= 56320 && lo < 57344) { cp = 65536 + (cp - 55296) * 1024 + lo - 56320; PP += 6 }
            }
            out = out utf8(cp)
        } else { pfail("bad escape"); return "" }
    }
}

# JSON string literal; like cain's C writer, non-ASCII becomes \uXXXX.
function jesc(s,    out, i, n, c, o, cp, extra, k, hi) {
    if (s !~ /["\\]/ && s !~ /[^ -~]/) return "\"" s "\""
    out = "\""
    n = length(s)
    for (i = 1; i <= n; i++) {
        c = substr(s, i, 1)
        o = ORD[c]
        if (c == "\"") out = out "\\\""
        else if (c == "\\") out = out "\\\\"
        else if (c == "\n") out = out "\\n"
        else if (c == "\r") out = out "\\r"
        else if (c == "\t") out = out "\\t"
        else if (c == "\b") out = out "\\b"
        else if (c == "\f") out = out "\\f"
        else if (o < 32) out = out sprintf("\\u%04x", o)
        else if (o < 128) out = out c
        else {
            extra = o >= 240 ? 3 : o >= 224 ? 2 : o >= 192 ? 1 : 0
            cp = extra == 3 ? o % 8 : extra == 2 ? o % 16 : extra == 1 ? o % 32 : o
            for (k = 0; k < extra && i < n && ORD[substr(s, i + 1, 1)] >= 128 && ORD[substr(s, i + 1, 1)] < 192; k++) {
                i++
                cp = cp * 64 + ORD[substr(s, i, 1)] % 64
            }
            if (cp >= 65536) {
                cp -= 65536
                hi = 55296 + int(cp / 1024)
                out = out sprintf("\\u%04x\\u%04x", hi, 56320 + cp % 1024)
            } else out = out sprintf("\\u%04x", cp)
        }
    }
    return out "\""
}

function jwrite(id, ind, d,    t, s, i, n, obj) {
    t = JT[id]
    if (t == "z") return "null"
    if (t == "b" || t == "n") return JV[id]
    if (t == "s") return jesc(JV[id])
    n = JC[id]
    obj = t == "o"
    if (!n) return obj ? "{}" : "[]"
    s = obj ? "{" : "["
    for (i = 1; i <= n; i++) {
        if (i > 1) s = s ","
        if (ind) s = s "\n" spaces(ind * (d + 1))
        else if (i > 1) s = s " "
        if (obj) s = s jesc(JK[id, i]) ": "
        s = s jwrite(JI[id, i], ind, d + 1)
    }
    if (ind) s = s "\n" spaces(ind * d)
    return s (obj ? "}" : "]")
}

# ---------------------------------------------------------------- key combos
# Modifiers are a 10-character string of 0/1 flags, in this order (also the print order):
#   1 super  2 lsuper  3 rsuper  4 ctrl  5 lctrl  6 rctrl  7 alt  8 lalt  9 ralt  10 shift
# A combo is "<flags> <key>".

function mhas(m, i) { return substr(m, i, 1) == "1" }
function mon(m, i) { return substr(m, 1, i - 1) "1" substr(m, i + 1) }
function moff(m, i) { return substr(m, 1, i - 1) "0" substr(m, i + 1) }
function cmods(c) { return substr(c, 1, 10) }
function ckey(c) { return substr(c, 12) }
function combo(m, k) { return m " " k }
function any_super(m) { return mhas(m, 1) || mhas(m, 2) || mhas(m, 3) }
function any_ctrl(m) { return mhas(m, 4) || mhas(m, 5) || mhas(m, 6) }
function any_alt(m) { return mhas(m, 7) || mhas(m, 8) || mhas(m, 9) }

function generic(m,    g) {
    g = M0
    if (any_super(m)) g = mon(g, 1)
    if (any_ctrl(m)) g = mon(g, 4)
    if (any_alt(m)) g = mon(g, 7)
    if (mhas(m, 10)) g = mon(g, 10)
    return g
}

function is_fkey(k) { return k ~ /^f[1-9]/ }

# "" if it can't be parsed.
function combo_parse(text,    s, n, parts, i, m, name, key) {
    s = repl(tolower(text), " ", "")
    n = split(s, parts, "+")
    if (n == 0) return ""
    m = M0
    for (i = 1; i < n; i++) {
        name = (parts[i] in ALIAS) ? ALIAS[parts[i]] : parts[i]
        if (!(name in MODBIT)) return ""
        m = mon(m, MODBIT[name])
    }
    key = (parts[n] in ALIAS) ? ALIAS[parts[n]] : parts[n]
    if (!(key in NAMED)) return ""
    return combo(m, key)
}

function combo_must(text,    c) {
    c = combo_parse(text)
    if (c == "") die("cain.json: can't understand the key combo \"" text "\"")
    return c
}

function combo_str(c,    s, i, m) {
    s = ""
    m = cmods(c)
    for (i = 1; i <= 10; i++) if (mhas(m, i)) s = s MODNAME[i] "+"
    return s ckey(c)
}

# Input combos on a Mac keyboard: Command is under your thumb, so it plays the PC's Alt.
function mac_swap_alt_cmd(c,    m, r, i) {
    m = cmods(c)
    r = m
    for (i = 1; i <= 3; i++) { r = moff(r, i); r = moff(r, i + 6) }
    for (i = 1; i <= 3; i++) {
        if (mhas(m, i + 6)) r = mon(r, i)
        if (mhas(m, i)) r = mon(r, i + 6)
    }
    return combo(r, ckey(c))
}

# PC-style output -> macOS: ctrl+c -> cmd+c, ctrl+left -> option+left, home -> cmd+left.
function mac_translate(c,    m, k, r) {
    m = cmods(c); k = ckey(c)
    if (m == M0 && k == "home") return combo(mon(M0, 1), "left")
    if (m == M0 && k == "end") return combo(mon(M0, 1), "right")
    if (!any_ctrl(m)) return c
    r = moff(moff(moff(m, 4), 5), 6)
    if (k == "left" || k == "right") return combo(mon(r, 7), k)
    if (k != "tab") return combo(mon(r, 1), k)
    return c
}

function lookup(tbl, k) { return (k in tbl) ? tbl[k] : k }

function keyd_output(c,    g, s) {
    g = generic(cmods(c)); s = ""
    if (mhas(g, 1)) s = s "M-"
    if (mhas(g, 4)) s = s "C-"
    if (mhas(g, 7)) s = s "A-"
    if (mhas(g, 10)) s = s "S-"
    return s lookup(KEYD, ckey(c))
}

function ahk_key(k) {
    if (k in AHK) return AHK[k]
    return is_fkey(k) ? toupper(k) : k
}

function ahk_hotkey(c,    s, i, m) {
    s = ""; m = cmods(c)
    for (i = 1; i <= 10; i++) if (mhas(m, i)) s = s AHKMOD[i]
    return s ahk_key(ckey(c))
}

function ahk_send(c,    g, s, k) {
    g = generic(cmods(c)); s = ""
    if (mhas(g, 1)) s = s "#"
    if (mhas(g, 4)) s = s "^"
    if (mhas(g, 7)) s = s "!"
    if (mhas(g, 10)) s = s "+"
    k = ahk_key(ckey(c))
    return length(k) > 1 ? s "{" k "}" : s k
}

function gtk_accel(c,    g, s, k) {
    g = generic(cmods(c)); s = ""; k = ckey(c)
    if (mhas(g, 1)) s = s "<Super>"
    if (mhas(g, 4)) s = s "<Primary>"
    if (mhas(g, 7)) s = s "<Alt>"
    if (mhas(g, 10)) s = s "<Shift>"
    return s (is_fkey(k) ? toupper(k) : lookup(GTK, k))
}

function kde_accel(c,    g, s, k) {
    g = generic(cmods(c)); s = ""; k = ckey(c)
    if (mhas(g, 1)) s = s "Meta+"
    if (mhas(g, 4)) s = s "Ctrl+"
    if (mhas(g, 7)) s = s "Alt+"
    if (mhas(g, 10)) s = s "Shift+"
    return s ((k in KDE) ? KDE[k] : toupper(k))
}

function karabiner_from(c, optional,    from, mods, opt, n, parts, i, mand, m) {
    from = jnew("o", ""); mods = jnew("o", ""); opt = jnew("a", "")
    jset(from, "key_code", jstrnode(lookup(KARA, ckey(c))))
    n = split(optional, parts, " ")
    for (i = 1; i <= n; i++) jpush(opt, jstrnode(parts[i]))
    jset(mods, "optional", opt)
    m = cmods(c)
    if (m != M0) {
        mand = jnew("a", "")
        for (i = 1; i <= 10; i++) if (mhas(m, i)) jpush(mand, jstrnode(KARAMOD[i]))
        jset(mods, "mandatory", mand)
    }
    jset(from, "modifiers", mods)
    return from
}

function karabiner_to(c, extra,    to, mods, g) {
    to = jnew("o", ""); mods = jnew("a", "")
    g = generic(cmods(c))
    jset(to, "key_code", jstrnode(lookup(KARA, ckey(c))))
    if (mhas(g, 1)) jpush(mods, jstrnode("left_command"))
    if (mhas(g, 4)) jpush(mods, jstrnode("left_control"))
    if (mhas(g, 7)) jpush(mods, jstrnode("left_option"))
    if (mhas(g, 10)) jpush(mods, jstrnode("left_shift"))
    if (extra != "") jpush(mods, jstrnode(extra))
    if (JC[mods]) jset(to, "modifiers", mods)
    return to
}

# ---------------------------------------------------------------- cain.json

function applies(e, target, desktop) {
    if (jget(e, "os") && !jhas_str(jget(e, "os"), target)) return 0
    if (jget(e, "desktop") && (target != "linux" || !jhas_str(jget(e, "desktop"), desktop))) return 0
    return 1
}

function input_combo(text,    c) {
    c = combo_must(text)
    if (OS == "macos" && jstr(SETTINGS, "mac_alt", "option") == "command") c = mac_swap_alt_cmd(c)
    return c
}

function load(path,    text, remaps, shortcuts, i, k, r, s, from, to, ov, keys, f, t) {
    text = readfile(path)
    if (text == "\001") die("can't read " path)
    ROOT = jparse(text)
    if (!ROOT) die(path ": " PERR)
    if (JT[ROOT] != "o") die(path ": expected a JSON object")
    SETTINGS = jget(ROOT, "settings")
    GIT = jget(ROOT, "git")

    NR_ = 0
    remaps = jget(ROOT, "remaps")
    for (i = 1; remaps && i <= JC[remaps]; i++) {
        r = JI[remaps, i]
        if (!applies(r, OS, "")) continue
        from = jstr(r, "from", ""); to = jstr(r, "to", "")
        if (from == "" || to == "") die("cain.json: every remap needs \"from\" and \"to\"")
        f = input_combo(from)
        ov = jget(r, OS)   # e.g. "macos": "cmd+shift+v", or null to skip
        if (ov) {
            if (JT[ov] != "s") continue
            t = combo_must(JV[ov])
        } else {
            t = combo_must(to)
            if (OS == "macos" && jbool(SETTINGS, "mac_translate", 1)) t = mac_translate(t)
        }
        if (f == t) continue
        NR_++; RFROM[NR_] = f; RTO[NR_] = t
    }

    NS = 0
    shortcuts = jget(ROOT, "shortcuts")
    for (i = 1; shortcuts && i <= JC[shortcuts]; i++) {
        s = JI[shortcuts, i]
        if (!applies(s, OS, "")) continue
        keys = jget(s, "keys")
        if (jstr(s, "action", "") == "" || !keys || JT[keys] != "a")
            die("cain.json: every shortcut needs \"action\" and a \"keys\" list")
        NS++; SENTRY[NS] = s; SACTION[NS] = jstr(s, "action", ""); SNKEYS[NS] = JC[keys]
        for (k = 1; k <= JC[keys]; k++) {
            if (JT[JI[keys, k]] != "s") die("cain.json: shortcut keys must be strings")
            SKEY[NS, k] = input_combo(JV[JI[keys, k]])
        }
    }
}

function keys_text(i,    s, k) {
    s = ""
    for (k = 1; k <= SNKEYS[i]; k++) s = s (k > 1 ? ", " : "") combo_str(SKEY[i, k])
    return s
}

# ---------------------------------------------------------------- shortcut actions

function is_wm(a) { return a in WMACTION }

# The command a launch shortcut runs, or "" (window-manager action, or no command for this OS).
function launch_command(i, target,    a, run, url, home, cmd, exe) {
    a = SACTION[i]
    if (is_wm(a)) return ""
    run = jget(SENTRY[i], "run")
    if (run) {
        if (JT[run] == "s") return JV[run]
        return jstr(run, target, "")
    }
    if (starts(a, "tool:")) {
        if (target == "windows") {
            exe = repl(HOME "/.local/bin/cain.cmd", "/", "\\")
            return "\"" exe "\" " substr(a, 6)
        }
        return shq(HOME "/.local/bin/cain") " " substr(a, 6)
    }
    url = jstr(SETTINGS, "homepage", "https://www.google.com")
    home = HOME
    cmd = ""
    if (target == "linux") {
        if (a == "terminal") cmd = ENVIRON["CAIN_TERM"] != "" ? ENVIRON["CAIN_TERM"] : "xterm"
        else if (a == "calculator") cmd = ENVIRON["CAIN_CALC"] != "" ? ENVIRON["CAIN_CALC"] : "xcalc"
        else if (a == "browser") cmd = "xdg-open " shq(url)
        else if (a == "file_manager") cmd = "xdg-open " shq(home)
    } else if (target == "macos") {
        if (a == "terminal") cmd = "open -a Terminal"
        else if (a == "calculator") cmd = "open -a Calculator"
        else if (a == "browser") cmd = "open " shq(url)
        else if (a == "file_manager") cmd = "open " shq(home)
    } else {
        if (a == "terminal") cmd = "wt.exe"
        else if (a == "calculator") cmd = "calc.exe"
        else if (a == "browser") cmd = url
        else if (a == "file_manager") cmd = "explorer.exe \"" home "\""
    }
    if (cmd == "") die("cain.json: unknown shortcut action \"" a "\" (give it a \"run\" command)")
    return cmd
}

function friendly(i,    name, a, p) {
    name = jstr(SENTRY[i], "name", "")
    if (name != "") return name
    a = SACTION[i]
    while ((p = index(a, ":")) > 0) a = substr(a, p + 1)
    return repl(a, "_", " ")
}

# ---------------------------------------------------------------- keyd (Linux)

function layer(name,    i) {
    for (i = 1; i <= LN; i++) if (LNAME[i] == name) return i
    LN++; LNAME[LN] = name; LBODY[LN] = ""
    return LN
}

function layers_for(bit) {
    if (bit == 8) { LF[1] = "alt"; return 1 }
    if (bit == 9) { LF[1] = "ralt"; return 1 }
    if (bit == 7) { LF[1] = "alt"; LF[2] = "ralt"; return HAS_RALT ? 2 : 1 }
    if (bit == 5) { LF[1] = "control"; return 1 }
    if (bit == 6) { LF[1] = "rctrl"; return 1 }
    if (bit == 4) { LF[1] = "control"; LF[2] = "rctrl"; return HAS_RCTRL ? 2 : 1 }
    if (bit == 10) { LF[1] = "shift"; return 1 }
    LF[1] = "meta"; return 1
}

# Add `line` to every combination of layers the modifiers from bit `i` on map to.
function add_combos(m, i, prefix, line,    n, k, opts, l) {
    while (i <= 10 && !mhas(m, i)) i++
    if (i > 10) { l = layer(prefix); LBODY[l] = LBODY[l] line "\n"; return }
    n = layers_for(i)
    for (k = 1; k <= n; k++) opts[k] = LF[k]
    for (k = 1; k <= n; k++) add_combos(m, i + 1, prefix == "" ? opts[k] : prefix "+" opts[k], line)
}

function keyd_generate(    used, i, k, m, mainl, line, out, name, header) {
    used = M0
    for (i = 1; i <= NR_; i++) {
        m = cmods(RFROM[i])
        for (k = 1; k <= 10; k++) if (mhas(m, k)) used = mon(used, k)
    }
    HAS_RALT = any_alt(used)
    HAS_RCTRL = mhas(used, 5) || mhas(used, 6)
    LN = 0
    mainl = layer("main")
    if (HAS_RALT) LBODY[mainl] = LBODY[mainl] "rightalt = layer(ralt)\n"
    if (HAS_RCTRL) LBODY[mainl] = LBODY[mainl] "rightcontrol = layer(rctrl)\n"
    for (i = 1; i <= NR_; i++) {
        line = lookup(KEYD, ckey(RFROM[i])) " = " keyd_output(RTO[i])
        if (cmods(RFROM[i]) == M0) LBODY[mainl] = LBODY[mainl] line "\n"
        else add_combos(cmods(RFROM[i]), 1, "", line)
    }
    out = "# Generated by cain from cain.json - edit that file and re-run `cain keys`.\n\n[ids]\n*\n\n"
    for (i = 1; i <= LN; i++) {
        if (LBODY[i] == "") continue
        name = LNAME[i]
        header = name == "ralt" ? "ralt:A" : name == "rctrl" ? "rctrl:C" : name
        out = out "[" header "]\n" LBODY[i] "\n"
    }
    if (substr(out, length(out) - 1) == "\n\n") out = substr(out, 1, length(out) - 1)
    return out
}

# ---------------------------------------------------------------- AutoHotkey (Windows)

function ahk_str(s) { return "\"" repl(repl(s, "`", "``"), "\"", "`\"") "\"" }

function ahk_add(hk, body) {
    if (hk in AHK_SEEN) { warn("duplicate Windows hotkey " hk " skipped"); return }
    AHK_SEEN[hk] = 1
    AHK_OUT = AHK_OUT hk "::" body "\n"
}

function ahk_generate(    i, k, src, dst, sm, dm, send, body, c, cs, hk, native, wm, key, cmd, q) {
    AHK_OUT = "; Generated by cain from cain.json - edit that file and re-run `cain keys`.\n" \
              "#Requires AutoHotkey v2.0\n#SingleInstance Force\nSendMode \"Input\"\n" \
              "A_MenuMaskKey := \"vkE8\"  ; stops a lone Alt tap from opening menus\n\n; ---- key remaps\n"
    for (i = 1; i <= NR_; i++) {
        src = RFROM[i]; dst = RTO[i]; sm = cmods(src); dm = cmods(dst)
        send = ahk_send(dst)
        body = "Send \"" send "\""
        if (sm == M0) {
            ahk_add(ahk_key(ckey(src)), dm != M0 ? body : ahk_key(ckey(dst)))   # plain remap, e.g. CapsLock::Esc
        } else {
            ahk_add(ahk_hotkey(src), body)
            if (dm == M0 && (ckey(dst) in SELECTABLE) && !mhas(sm, 10))   # keep Shift for selecting
                ahk_add(ahk_hotkey(combo(mon(sm, 10), ckey(src))), "Send \"" ahk_send(combo(mon(M0, 10), ckey(dst))) "\"")
        }
    }
    AHK_OUT = AHK_OUT "\n; ---- shortcuts\n"
    for (i = 1; i <= NS; i++) {
        for (k = 1; k <= SNKEYS[i]; k++) {
            c = SKEY[i, k]; cs = combo_str(c); hk = ahk_hotkey(c)
            native = (SACTION[i] == "switch_windows" && cs == "alt+tab") || (SACTION[i] == "show_desktop" && cs == "super+d")
            wm = (SACTION[i] in AHKWM) ? AHKWM[SACTION[i]] : ""
            if (native) {
                # Windows already does this one
            } else if (SACTION[i] == "switch_windows") {
                # AltTab only works on "LAlt & key" style hotkeys
                key = ahk_key(ckey(c))
                if (any_alt(cmods(c)) && cmods(c) == alt_only(cmods(c))) {
                    if (!(mhas(cmods(c), 9) && !mhas(cmods(c), 7) && !mhas(cmods(c), 8))) ahk_add("LAlt & " key, "AltTab")
                    if (!(mhas(cmods(c), 8) && !mhas(cmods(c), 7) && !mhas(cmods(c), 9))) ahk_add("RAlt & " key, "AltTab")
                } else ahk_add(hk, "Send \"!{Tab}\"")
            } else if (wm != "") {
                ahk_add(hk, wm)
            } else {
                cmd = launch_command(i, "windows")
                if (cmd != "") {
                    q = ahk_str(cmd)
                    # cain's own tools are console programs: hide their window
                    ahk_add(hk, starts(SACTION[i], "tool:") ? "RunCmd(" q ", \"Hide\")" : "RunCmd(" q ")")
                }
            }
        }
    }
    return AHK_OUT "\nToggleMax() {\n    try {\n        if WinGetMinMax(\"A\") = 1\n            WinRestore \"A\"\n" \
        "        else\n            WinMaximize \"A\"\n    }\n}\n\nRunCmd(cmd, opts := \"\") {\n    try Run cmd, , opts\n" \
        "    catch as e\n        MsgBox \"cain could not run:`n\" cmd \"`n`n\" e.Message\n}\n"
}

# The alt bits of m and nothing else (to test "only alt modifiers are held").
function alt_only(m,    r) {
    r = M0
    if (mhas(m, 7)) r = mon(r, 7)
    if (mhas(m, 8)) r = mon(r, 8)
    if (mhas(m, 9)) r = mon(r, 9)
    return r
}

# ---------------------------------------------------------------- Karabiner (macOS)

function manipulator(from, to,    m) {
    m = jnew("o", "")
    jset(m, "type", jstrnode("basic"))
    jset(m, "from", from)
    jset(m, "to", to)
    return m
}

function rule(desc, manips,    r) {
    r = jnew("o", "")
    jset(r, "description", jstrnode(desc))
    jset(r, "manipulators", manips)
    return r
}

function karabiner_generate(    rules, i, k, src, dst, opt, to, manips, sh, cmd, a) {
    rules = jnew("a", "")
    for (i = 1; i <= NR_; i++) {
        src = RFROM[i]; dst = RTO[i]
        opt = cmods(src) == M0 ? "any" : cmods(dst) == M0 ? "caps_lock shift" : "caps_lock"
        to = jnew("a", ""); manips = jnew("a", "")
        jpush(to, karabiner_to(dst, ""))
        jpush(manips, manipulator(karabiner_from(src, opt), to))
        jpush(rules, rule("cain: " combo_str(src) " -> " combo_str(dst), manips))
    }
    for (i = 1; i <= NS; i++) {
        a = SACTION[i]
        to = jnew("a", "")
        if ((a in MACWM) && MACWM[a] != "shell") {
            jpush(to, karabiner_to(MACWM[a], MACEXTRA[a]))
        } else {
            cmd = (a in MACWM) ? MACSHELL[a] : launch_command(i, "macos")
            if (cmd == "") continue   # a "run" shortcut with no macOS command
            sh = jnew("o", "")
            jset(sh, "shell_command", jstrnode(cmd))
            jpush(to, sh)
        }
        manips = jnew("a", "")
        for (k = 1; k <= SNKEYS[i]; k++) jpush(manips, manipulator(karabiner_from(SKEY[i, k], "caps_lock"), to))
        jpush(rules, rule("cain: " a " (" keys_text(i) ")", manips))
    }
    return rules
}

# Merge cain's rules into the user's karabiner.json, keeping everything else.
function karabiner_merge(path,    text, config, profiles, p, profile, i, cm, old, rules, d) {
    text = readfile(path)
    if (text == "\001" || text ~ /^[ \t\r\n]*$/) config = jnew("o", "")
    else {
        config = jparse(text)
        if (!config || JT[config] != "o") {
            printf "%s isn't valid JSON (%s); leaving it alone\n", path, config ? "not an object" : PERR | "cat 1>&2"
            exit 3
        }
    }
    profiles = jget(config, "profiles")
    if (!profiles || JT[profiles] != "a" || !JC[profiles]) {
        profiles = jnew("a", "")
        p = jnew("o", "")
        jset(p, "name", jstrnode("Default profile"))
        jset(p, "selected", jnew("b", "true"))
        jpush(profiles, p)
        jset(config, "profiles", profiles)
    }
    profile = JI[profiles, 1]
    for (i = 1; i <= JC[profiles]; i++) if (jbool(JI[profiles, i], "selected", 0)) { profile = JI[profiles, i]; break }
    cm = jget(profile, "complex_modifications")
    if (!cm || JT[cm] != "o") { cm = jnew("o", ""); jset(profile, "complex_modifications", cm) }
    old = jget(cm, "rules")
    rules = karabiner_generate()   # cain's rules first: Karabiner gives earlier rules priority
    for (i = 1; old && JT[old] == "a" && i <= JC[old]; i++) {
        d = jstr(JI[old, i], "description", "")
        if (!starts(d, "cain: ")) jpush(rules, JI[old, i])
    }
    jset(cm, "rules", rules)
    printf "%s\n", jwrite(config, 4, 0)
}

# ---------------------------------------------------------------- Linux desktops
# These modes print shell commands (run, write_text, info, warn) for `cain` to eval.

function gv_str(s) { return "'" repl(s, "'", "\\'") "'" }

function gv_list(list, n,    s, i) {
    s = "["
    for (i = 1; i <= n; i++) s = s (i > 1 ? ", " : "") gv_str(list[i])
    return s "]"
}

function emit(cmd) { PLAN = PLAN cmd "\n" }
function gsettings(schema, key, value) { emit("run gsettings set " shq(schema) " " shq(key) " " shq(value)) }

function accels_of(i,    k) { for (k = 1; k <= SNKEYS[i]; k++) ACC[k] = gtk_accel(SKEY[i, k]); return SNKEYS[i] }

# Entries from `gsettings get` output, minus the ones cain made before.
function custom_list(raw,    n, item, p, t) {
    n = 0
    while ((p = index(raw, "'")) > 0) {
        raw = substr(raw, p + 1)
        p = index(raw, "'")
        if (!p) break
        item = substr(raw, 1, p - 1)
        raw = substr(raw, p + 1)
        t = item
        sub(/\/+$/, "", t)
        sub(/.*\//, "", t)
        if (!starts(t, "cain")) CUSTOM[++n] = item
    }
    return n
}

function plan_gnome(    media, base, n, i, k, na, cmd, name, path, schema, one, made, parts) {
    media = "org.gnome.settings-daemon.plugins.media-keys"
    base = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/"
    n = custom_list(ENVIRON["CAIN_EXISTING"])
    made = 0
    for (i = 1; i <= NS; i++) {
        na = accels_of(i)
        if (SACTION[i] in GNOME) {
            split(GNOME[SACTION[i]], parts, " ")
            gsettings(parts[1], parts[2], gv_list(ACC, na))
            if (SACTION[i] == "switch_windows") {   # free Alt+Tab from the app switcher
                one[1] = "<Super>Tab"
                gsettings("org.gnome.desktop.wm.keybindings", "switch-applications", gv_list(one, 1))
            }
            continue
        }
        cmd = launch_command(i, "linux")
        name = friendly(i)
        if (cmd == "") continue
        for (k = 1; k <= na; k++) {   # GNOME custom shortcuts hold one key each
            path = base "cain" made++ "/"
            schema = media ".custom-keybinding:" path
            gsettings(schema, "name", gv_str("cain " name))
            gsettings(schema, "command", gv_str(cmd))
            gsettings(schema, "binding", gv_str(ACC[k]))
            CUSTOM[++n] = path
        }
    }
    gsettings(media, "custom-keybindings", gv_list(CUSTOM, n))
}

function plan_cinnamon(    root, base, n, i, na, cmd, name, schema, made, parts) {
    root = "org.cinnamon.desktop.keybindings"
    base = "/org/cinnamon/desktop/keybindings/custom-keybindings/"
    n = custom_list(ENVIRON["CAIN_EXISTING"])
    made = 0
    for (i = 1; i <= NS; i++) {
        na = accels_of(i)
        if (SACTION[i] in CINNAMON) {
            split(CINNAMON[SACTION[i]], parts, " ")
            gsettings(parts[1], parts[2], gv_list(ACC, na))
            continue
        }
        cmd = launch_command(i, "linux")
        if (cmd == "") continue
        name = "cain" made++
        schema = root ".custom-keybinding:" base name "/"
        gsettings(schema, "name", gv_str(friendly(i)))
        gsettings(schema, "command", gv_str(cmd))
        gsettings(schema, "binding", gv_list(ACC, na))
        CUSTOM[++n] = name
    }
    gsettings(root, "custom-list", gv_list(CUSTOM, n))
}

function plan_xfce(    i, k, na, wm, cmd, prop, value) {
    for (i = 1; i <= NS; i++) {
        na = accels_of(i)
        wm = (SACTION[i] in XFCE) ? XFCE[SACTION[i]] : ""
        cmd = wm != "" || SACTION[i] == "lock_screen" ? "" : launch_command(i, "linux")
        if (wm == "" && cmd == "" && SACTION[i] != "lock_screen") continue
        for (k = 1; k <= na; k++) {
            prop = (wm != "" ? "/xfwm4/custom/" : "/commands/custom/") ACC[k]
            value = wm != "" ? wm : cmd != "" ? cmd : "xflock4"
            emit("run xfconf-query -c xfce4-keyboard-shortcuts -p " shq(prop) " -n -t string -s " shq(value))
        }
    }
}

function kwrite(tool, g1, g2, key, value) {
    emit("run " shq(tool) " --file kglobalshortcutsrc --group " shq(g1) (g2 != "" ? " --group " shq(g2) : "") \
         " --key " shq(key) " " shq(value))
}

function plan_kde(    tool, plasma6, i, k, accels, escaped, parts, id, path, name, cmd, desktop) {
    tool = ENVIRON["CAIN_KDE_TOOL"]
    plasma6 = ENVIRON["CAIN_PLASMA6"] == "1"
    if (tool == "") { emit("warn " shq("kwriteconfig6/5 not found; can't set KDE shortcuts")); return }
    for (i = 1; i <= NS; i++) {
        accels = ""
        for (k = 1; k <= SNKEYS[i]; k++) accels = accels (k > 1 ? "\t" : "") kde_accel(SKEY[i, k])
        escaped = repl(accels, ",", "\\,")   # kwin values are "active,default,name" lists
        if (SACTION[i] in KDEWM) {
            split(KDEWM[SACTION[i]], parts, "|")
            kwrite(tool, parts[1], "", parts[2], escaped ",none," parts[2])
            continue
        }
        cmd = launch_command(i, "linux")
        if (cmd == "") continue
        id = "cain-" repl(SACTION[i], ":", "-") ".desktop"
        path = HOME "/.local/share/applications/" id
        name = friendly(i)
        desktop = "[Desktop Entry]\nType=Application\nName=cain " name "\nExec=" cmd "\nNoDisplay=true\n"
        emit("write_text " shq(path) " " shq(desktop))
        if (plasma6) kwrite(tool, "services", id, "_launch", accels)
        else kwrite(tool, id, "", "_launch", escaped ",none," name)
    }
    emit("info " shq("  KDE picks up new global shortcuts after you log out and back in."))
}

function plan_unknown(de,    i, cmd) {
    emit("warn " shq("don't know how to set shortcuts on this desktop ('" (de != "" ? de : "unknown") "'). Set these up by hand:"))
    for (i = 1; i <= NS; i++) {
        cmd = launch_command(i, "linux")
        if (cmd == "") cmd = is_wm(SACTION[i]) ? "(window manager action)" : "(no Linux command)"
        emit("info " shq(sprintf("    %-28s %-18s %s", keys_text(i), SACTION[i], cmd)))
    }
}

# ---------------------------------------------------------------- lists for the shell

# The Linux package name: its "<pm>" key, else "linux", else "name". SKIP set when null.
function linux_name(p, pm,    v, keys, k) {
    keys[1] = pm; keys[2] = "linux"
    for (k = 1; k <= 2; k++) {
        v = jget(p, keys[k])
        if (v && JT[v] == "z") { SKIP = 1; return "" }
        if (v && JT[v] == "s") { SKIP = 0; return JV[v] }
    }
    SKIP = 0
    return jstr(p, "name", "")
}

function list_packages(    pkgs, i, p, name, pkg, b) {
    pkgs = jget(ROOT, "packages")
    for (i = 1; pkgs && i <= JC[pkgs]; i++) {
        p = JI[pkgs, i]
        if (!applies(p, OS, "")) continue
        if (ENVIRON["CAIN_TERMINAL"] == "1" && !jbool(p, "terminal", 0)) continue
        name = jstr(p, "name", "")
        if (name == "") die("cain.json: every package needs a \"name\"")
        if (OS == "macos") {
            b = jget(p, "brew")
            if (b && JT[b] == "z") continue
            print name SEP "0" SEP jstr(p, "brew", name) SEP SEP name
        } else {
            pkg = linux_name(p, ENVIRON["CAIN_PM"])
            print name SEP SKIP SEP pkg SEP jstr(p, "fallback", "") SEP jstr(p, "bin", name)
        }
    }
}

function list_files(    files, i, f, src, dest) {
    files = jget(ROOT, "files")
    for (i = 1; files && i <= JC[files]; i++) {
        f = JI[files, i]
        if (!applies(f, OS, ENVIRON["CAIN_DESKTOP"])) continue
        src = jstr(f, "src", ""); dest = jstr(f, "dest", "")
        if (src == "" || dest == "") die("cain.json: every file needs \"src\" and \"dest\"")
        print src SEP dest
    }
}

function get(path,    n, parts, i, node) {
    n = split(path, parts, ".")
    node = ROOT
    for (i = 1; i <= n; i++) { node = jget(node, parts[i]); if (!node) return }
    if (JT[node] == "s" || JT[node] == "b" || JT[node] == "n") print JV[node]
}

# ---------------------------------------------------------------- tables

function table(arr, text,    n, items, i, kv) {
    n = split(text, items, " ")
    for (i = 1; i <= n; i++) { split(items[i], kv, "="); arr[kv[1]] = kv[2] }
}

function init(    i, n, list) {
    M0 = "0000000000"
    SEP = sprintf("%c", 31)   # between fields of the lists the shell reads (tabs would merge)
    split("super lsuper rsuper ctrl lctrl rctrl alt lalt ralt shift", MODNAME, " ")
    for (i = 1; i <= 10; i++) MODBIT[MODNAME[i]] = i
    split("# <# ># ^ <^ >^ ! <! >! +", AHKMOD, " ")
    split("command left_command right_command control left_control right_control option left_option right_option shift", KARAMOD, " ")
    n = split("comma period slash semicolon quote bracketleft bracketright backslash minus equal grave tab enter " \
              "esc backspace delete space capslock left right up down home end pageup pagedown " \
              "a b c d e f g h i j k l m n o p q r s t u v w x y z 0 1 2 3 4 5 6 7 8 9 " \
              "f1 f2 f3 f4 f5 f6 f7 f8 f9 f10 f11 f12", list, " ")
    for (i = 1; i <= n; i++) NAMED[list[i]] = 1
    table(ALIAS, "escape=esc return=enter dot=period apostrophe=quote leftbrace=bracketleft " \
                 "rightbrace=bracketright control=ctrl win=super cmd=super meta=super option=alt " \
                 "caps=capslock bksp=backspace del=delete")
    table(KEYD, "period=dot quote=apostrophe bracketleft=leftbrace bracketright=rightbrace")
    table(AHK, "comma=vkBC period=vkBE slash=vkBF semicolon=vkBA quote=vkDE bracketleft=vkDB " \
               "bracketright=vkDD backslash=vkDC minus=vkBD equal=vkBB grave=vkC0 tab=Tab enter=Enter " \
               "esc=Esc backspace=Backspace delete=Delete space=Space capslock=CapsLock left=Left " \
               "right=Right up=Up down=Down home=Home end=End pageup=PgUp pagedown=PgDn")
    table(KARA, "bracketleft=open_bracket bracketright=close_bracket minus=hyphen equal=equal_sign " \
                "grave=grave_accent_and_tilde enter=return_or_enter esc=escape backspace=delete_or_backspace " \
                "delete=delete_forward space=spacebar capslock=caps_lock left=left_arrow right=right_arrow " \
                "up=up_arrow down=down_arrow pageup=page_up pagedown=page_down")
    table(GTK, "quote=apostrophe tab=Tab enter=Return esc=Escape backspace=BackSpace delete=Delete " \
               "capslock=Caps_Lock left=Left right=Right up=Up down=Down home=Home end=End " \
               "pageup=Page_Up pagedown=Page_Down")
    KDE["comma"] = ","; KDE["period"] = "."; KDE["slash"] = "/"; KDE["semicolon"] = ";"
    KDE["quote"] = "'"; KDE["bracketleft"] = "["; KDE["bracketright"] = "]"; KDE["backslash"] = "\\"
    KDE["minus"] = "-"; KDE["equal"] = "="; KDE["grave"] = "`"
    table(KDE, "tab=Tab enter=Return esc=Esc backspace=Backspace delete=Del space=Space " \
               "capslock=CapsLock left=Left right=Right up=Up down=Down home=Home end=End " \
               "pageup=PgUp pagedown=PgDown")
    n = split("close_window minimize toggle_maximize tile_left tile_right show_desktop switch_windows lock_screen", list, " ")
    for (i = 1; i <= n; i++) WMACTION[list[i]] = 1
    n = split("left right up down home end pageup pagedown tab", list, " ")
    for (i = 1; i <= n; i++) SELECTABLE[list[i]] = 1

    AHKWM["close_window"] = "WinClose \"A\""
    AHKWM["minimize"] = "WinMinimize \"A\""
    AHKWM["toggle_maximize"] = "ToggleMax()"
    AHKWM["tile_left"] = "Send \"#{Left}\""
    AHKWM["tile_right"] = "Send \"#{Right}\""
    AHKWM["show_desktop"] = "Send \"#d\""
    AHKWM["lock_screen"] = "DllCall(\"LockWorkStation\")"

    # macOS: a key combo (+ extra modifier), or "shell" for a command
    MACWM["close_window"] = combo(mon(M0, 1), "w")
    MACWM["minimize"] = combo(mon(M0, 1), "m")
    MACWM["toggle_maximize"] = combo(mon(M0, 4), "f"); MACEXTRA["toggle_maximize"] = "fn"   # Window > Fill
    MACWM["tile_left"] = combo(mon(M0, 4), "left"); MACEXTRA["tile_left"] = "fn"
    MACWM["tile_right"] = combo(mon(M0, 4), "right"); MACEXTRA["tile_right"] = "fn"
    MACWM["switch_windows"] = combo(mon(M0, 1), "tab")
    MACWM["lock_screen"] = combo(mon(mon(M0, 1), 4), "q")
    MACWM["show_desktop"] = "shell"
    MACSHELL["show_desktop"] = "'/System/Applications/Mission Control.app/Contents/MacOS/Mission Control' 1"

    GNOME["close_window"] = "org.gnome.desktop.wm.keybindings close"
    GNOME["minimize"] = "org.gnome.desktop.wm.keybindings minimize"
    GNOME["toggle_maximize"] = "org.gnome.desktop.wm.keybindings toggle-maximized"
    GNOME["tile_left"] = "org.gnome.mutter.keybindings toggle-tiled-left"
    GNOME["tile_right"] = "org.gnome.mutter.keybindings toggle-tiled-right"
    GNOME["show_desktop"] = "org.gnome.desktop.wm.keybindings show-desktop"
    GNOME["switch_windows"] = "org.gnome.desktop.wm.keybindings switch-windows"
    GNOME["lock_screen"] = "org.gnome.settings-daemon.plugins.media-keys screensaver"

    CINNAMON["close_window"] = "org.cinnamon.desktop.keybindings.wm close"
    CINNAMON["minimize"] = "org.cinnamon.desktop.keybindings.wm minimize"
    CINNAMON["toggle_maximize"] = "org.cinnamon.desktop.keybindings.wm toggle-maximized"
    CINNAMON["tile_left"] = "org.cinnamon.desktop.keybindings.wm push-tile-left"
    CINNAMON["tile_right"] = "org.cinnamon.desktop.keybindings.wm push-tile-right"
    CINNAMON["show_desktop"] = "org.cinnamon.desktop.keybindings.wm show-desktop"
    CINNAMON["switch_windows"] = "org.cinnamon.desktop.keybindings.wm switch-windows"
    CINNAMON["lock_screen"] = "org.cinnamon.desktop.keybindings.media-keys screensaver"

    table(XFCE, "close_window=close_window_key minimize=hide_window_key toggle_maximize=maximize_window_key " \
                "tile_left=tile_left_key tile_right=tile_right_key show_desktop=show_desktop_key " \
                "switch_windows=cycle_windows_key")

    KDEWM["close_window"] = "kwin|Window Close"
    KDEWM["minimize"] = "kwin|Window Minimize"
    KDEWM["toggle_maximize"] = "kwin|Window Maximize"
    KDEWM["tile_left"] = "kwin|Window Quick Tile Left"
    KDEWM["tile_right"] = "kwin|Window Quick Tile Right"
    KDEWM["show_desktop"] = "kwin|Show Desktop"
    KDEWM["switch_windows"] = "kwin|Walk Through Windows"
    KDEWM["lock_screen"] = "ksmserver|Lock Session"

    for (i = 1; i < 256; i++) ORD[sprintf("%c", i)] = i
}

# ---------------------------------------------------------------- main

BEGIN { main() }

function main(    i, de) {
    init()
    OS = os
    HOME = ENVIRON["HOME"]
    load(ENVIRON["CAIN_JSON"])

    if (mode == "check") exit 0
    if (mode == "keyd") { printf "%s", keyd_generate(); exit 0 }
    if (mode == "ahk") { printf "%s", ahk_generate(); exit 0 }
    if (mode == "karabiner") { karabiner_merge(ENVIRON["CAIN_KARABINER"]); exit 0 }
    if (mode == "packages") { list_packages(); exit 0 }
    if (mode == "files") { list_files(); exit 0 }
    if (mode == "get") { get(ENVIRON["CAIN_KEY"]); exit 0 }
    if (mode == "generate") {
        if (OS == "linux") {
            printf "# ---- /etc/keyd/default.conf\n%s\n", keyd_generate()
            print "# ---- desktop shortcuts (applied with gsettings / kwriteconfig / xfconf)"
            for (i = 1; i <= NS; i++) printf "#   %-30s %s\n", keys_text(i), SACTION[i]
        } else if (OS == "windows") {
            printf "%s\n", ahk_generate()
        } else {
            printf "%s\n", jwrite(karabiner_generate(), 2, 0)
        }
        exit 0
    }
    if (mode == "desktop") {
        PLAN = ""
        de = ENVIRON["CAIN_DESKTOP"]
        if (de == "gnome") plan_gnome()
        else if (de == "cinnamon") plan_cinnamon()
        else if (de == "xfce") plan_xfce()
        else if (de == "kde") plan_kde()
        else plan_unknown(de)
        printf "%s", PLAN
        exit 0
    }
    die("cain.awk: unknown mode " mode)
}
