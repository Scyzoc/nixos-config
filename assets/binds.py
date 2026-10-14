"""binds : gestionnaire des raccourcis (binds) Hyprland.

Les binds par défaut sont définis dans la config Nix (~/.config/hypr/hyprland.lua,
générée). Pour les lister sans Hyprland, ce script exécute ce fichier dans un
interpréteur Lua avec un faux `hl` qui enregistre chaque hl.bind (boucles et
variables comprises). Les changements de l'utilisateur vivent dans une couche à
part, ~/.local/state/binds/user.json :

  {"disabled": ["d:super + q", …],           binds par défaut désactivés
   "custom": [{"id", "keys", "kind", "value", "desc", "flags", "replaces"}, …]}

et sont appliqués à chaud (hyprctl eval) puis écrits dans
~/.config/hypr/binds-user.lua, chargé en dernier par hyprland.lua au démarrage.

  binds list                    état complet (JSON) : binds par défaut + perso
  binds add '<json>'            nouveau bind perso
  binds update <id> '<json>'    modifie (un bind par défaut devient un bind perso
                                qui le remplace)
  binds delete <id>             supprime un bind perso (restaure l'original)
  binds toggle <id>             désactive / réactive un bind par défaut
  binds reset                   efface toute la couche utilisateur
  binds apply                   réapplique la couche utilisateur
  binds capture start|stop      submap vide pendant la capture d'une combinaison

Les commandes qui modifient affichent l'état (comme `list`), avec une clé "error"
si l'application à chaud a échoué.
"""
import json
import os
import re
import subprocess
import sys
import uuid

HYPRCTL = os.environ.get("HYPRCTL", "hyprctl")
LUA = os.environ.get("BINDS_LUA", "lua")
HOME = os.path.expanduser("~")
HYPR_LUA = os.path.join(HOME, ".config/hypr/hyprland.lua")
USER_LUA = os.path.join(HOME, ".config/hypr/binds-user.lua")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.join(HOME, ".local/state")), "binds")
USER_JSON = os.path.join(STATE, "user.json")
TOUCHED_JSON = os.path.join(STATE, "touched.json")
SUBMAP = "bindcap"

FLAGS = ["locked", "repeating", "release", "non_consuming"]

# Faux `hl` : enregistre les hl.bind, ignore tout le reste. Une ligne par bind :
#   B <touches> <drapeaux> <description> <type> <commande> <source Lua de l'action> <options Lua>
STUB = r"""
local esc = function(s) return (tostring(s):gsub("\\", "\\\\"):gsub("\t", "\\t"):gsub("\n", "\\n")) end
local DESC = {}
local ser
ser = function(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v)
  elseif t == "number" or t == "boolean" then return tostring(v)
  elseif t == "table" then
    if getmetatable(v) == DESC then
      local a = {}
      for i, x in ipairs(v.args) do a[i] = ser(x) end
      return v.path .. "(" .. table.concat(a, ", ") .. ")"
    end
    local parts, seen = {}, {}
    for i, x in ipairs(v) do parts[#parts + 1] = ser(x); seen[i] = true end
    local keys = {}
    for k in pairs(v) do if not seen[k] then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or "[" .. ser(k) .. "]"
      parts[#parts + 1] = ks .. " = " .. ser(v[k])
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
  end
  return "nil"
end
local node
node = function(path)
  return setmetatable({}, {
    __index = function(_, k) return node(path .. "." .. tostring(k)) end,
    __call = function(_, ...) return setmetatable({ path = path, args = { ... } }, DESC) end,
  })
end
local FLAGNAMES = { locked = 1, repeating = 1, release = 1, non_consuming = 1, mouse = 1 }
local bind = function(keys, d, opts)
  opts = opts or {}
  local flags = {}
  for k in pairs(FLAGNAMES) do if opts[k] == true then flags[#flags + 1] = k end end
  table.sort(flags)
  local kind, cmd = "lua", ""
  if getmetatable(d) == DESC and d.path == "hl.dsp.exec_cmd" and type(d.args[1]) == "string" then
    kind, cmd = "exec", d.args[1]
  end
  io.write(table.concat({ "B", esc(keys), table.concat(flags, ","), esc(opts.description or ""), kind,
    esc(cmd), esc(ser(d)), esc(ser(opts)) }, "\t"), "\n")
end
hl = setmetatable({}, { __index = function(_, k)
  if k == "bind" then return bind end
  if k == "unbind" then return function() end end
  return node("hl." .. tostring(k))
end })
local realdofile = dofile
dofile = function(p) if tostring(p):find("binds%-user") then return end return realdofile(p) end
local ok, err = pcall(realdofile, arg[1])
if not ok then io.stderr:write(tostring(err), "\n") end
"""

MODS = {"SUPER": "SUPER", "WIN": "SUPER", "MOD4": "SUPER", "META": "SUPER", "CTRL": "CTRL",
        "CONTROL": "CTRL", "ALT": "ALT", "MOD1": "ALT", "SHIFT": "SHIFT"}
ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]


def unesc(s):
    return re.sub(r"\\([\\tn])", lambda m: {"\\": "\\", "t": "\t", "n": "\n"}[m.group(1)], s)


def parse_keys(s):
    """'SUPER + SHIFT + K' → (['SUPER', 'SHIFT'], 'K')."""
    parts = [p.strip() for p in re.split(r"[+,]", s) if p.strip()]
    mods = []
    key = ""
    for i, p in enumerate(parts):
        m = MODS.get(p.upper())
        if m and i < len(parts) - 1:
            if m not in mods:
                mods.append(m)
        else:
            key = p
    return sorted(mods, key=ORDER.index), key


def norm(s):
    mods, key = parse_keys(s)
    return " + ".join(mods + [key.lower()])


def pretty(s):
    mods, key = parse_keys(s)
    return " + ".join(mods + [key])


DIRS = {"left": "à gauche", "right": "à droite", "up": "en haut", "down": "en bas"}


def label(kind, cmd, src, desc):
    if desc:
        return desc
    if kind == "exec":
        return cmd
    m = re.search(r'direction = "(\w+)"', src)
    if m:
        d = DIRS.get(m.group(1), m.group(1))
        return ("Focus " if "hl.dsp.focus" in src else "Déplacer la fenêtre ") + d
    m = re.search(r'workspace = "?([^" ,}]+)"?', src)
    if m:
        w = m.group(1)
        if w == "special:magic":
            return "Envoyer au scratchpad"
        if w == "e+1":
            return "Workspace suivant"
        if w == "e-1":
            return "Workspace précédent"
        return ("Aller au workspace " if "hl.dsp.focus" in src else "Envoyer au workspace ") + w
    table = [
        ("hl.dsp.window.close", "Fermer la fenêtre"),
        ("hl.dsp.exit", "Quitter Hyprland"),
        ("hl.dsp.window.float", "Fenêtre flottante (bascule)"),
        ('hl.dsp.layout("togglesplit")', "Inverser la découpe"),
        ('mode = "maximized"', "Maximiser la fenêtre"),
        ('mode = "fullscreen"', "Plein écran"),
        ("hl.dsp.window.drag", "Déplacer la fenêtre (souris)"),
        ("hl.dsp.window.resize", "Redimensionner la fenêtre (souris)"),
    ]
    for pat, text in table:
        if pat in src:
            return text
    return src


def category(keys, kind, src):
    k = keys.lower()
    if "xf86" in k or k.endswith("print"):
        return "media"
    if "mouse" in k or "workspace" in src or "hl.dsp.focus" in src:
        return "workspaces"
    if kind == "exec":
        return "apps"
    return "fenetres"


def load_defaults():
    """Binds de hyprland.lua, via le faux `hl`."""
    try:
        r = subprocess.run([LUA, "-", HYPR_LUA], input=STUB, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.TimeoutExpired):
        return []
    return parse_stub(r.stdout)


def parse_stub(out):
    res, seen = [], {}
    for line in out.splitlines():
        f = line.split("\t")
        if len(f) != 8 or f[0] != "B":
            continue
        keys, flags, desc, kind, cmd, src, opts = (unesc(x) for x in f[1:])
        n = norm(keys)
        seen[n] = seen.get(n, 0) + 1
        res.append({
            "id": "d:" + n + ("#%d" % seen[n] if seen[n] > 1 else ""),
            "keys": keys, "pretty": pretty(keys), "norm": n, "source": "default",
            "kind": kind, "cmd": cmd, "lua": src, "opts": opts,
            "flags": [x for x in flags.split(",") if x and x != "mouse"], "desc": desc,
            "label": label(kind, cmd, src, desc), "cat": category(keys, kind, src),
        })
    res.sort(key=lambda b: (b["cat"], b["norm"]))
    return res


def load_user():
    try:
        with open(USER_JSON) as f:
            u = json.load(f)
        return {"disabled": list(u.get("disabled", [])), "custom": list(u.get("custom", []))}
    except (OSError, ValueError):
        return {"disabled": [], "custom": []}


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def custom_lua(c):
    """(action Lua, options Lua) d'un bind perso."""
    if c["kind"] == "exec":
        action = "hl.dsp.exec_cmd(%s)" % json.dumps(c["value"], ensure_ascii=False)
    else:
        action = c["value"].strip()
    opts = ["%s = true" % f for f in c.get("flags", []) if f in FLAGS]
    if c.get("desc"):
        opts.append("description = %s" % json.dumps(c["desc"], ensure_ascii=False))
    return action, "{ %s }" % ", ".join(opts) if opts else "{}"


def lua_check(expr):
    """Vrai si l'expression Lua (action Hyprland) est syntaxiquement valide."""
    r = subprocess.run([LUA, "-e", 'assert(load("return " .. arg[1]))', "--", expr],
                       capture_output=True, text=True)
    return r.returncode == 0


def state():
    defaults = load_defaults()
    user = load_user()
    by_id = {c["replaces"]: c["id"] for c in user["custom"] if c.get("replaces")}
    binds = []
    for d in defaults:
        d["enabled"] = d["id"] not in user["disabled"]
        d["overridden"] = by_id.get(d["id"], "")
        if not d["overridden"]:
            binds.append(d)
    ids = {d["id"]: d for d in defaults}
    for c in user["custom"]:
        action, opts = custom_lua(c)
        orig = ids.get(c.get("replaces", ""))
        binds.append({
            "id": c["id"], "keys": c["keys"], "pretty": pretty(c["keys"]), "norm": norm(c["keys"]),
            "source": "custom", "kind": c["kind"], "cmd": c["value"] if c["kind"] == "exec" else "",
            "lua": action, "opts": opts, "flags": c.get("flags", []), "desc": c.get("desc", ""),
            "label": c.get("desc") or (c["value"] if c["kind"] == "exec" else label("lua", "", action, "")),
            "value": c["value"], "cat": "perso", "enabled": True,
            "replaces": c.get("replaces", ""), "replacesPretty": pretty(orig["keys"]) if orig else "",
        })
    count = {}
    for b in binds:
        if b["enabled"]:
            count[b["norm"]] = count.get(b["norm"], 0) + 1
    for b in binds:
        b["conflict"] = b["enabled"] and count.get(b["norm"], 0) > 1
    return {"binds": binds, "defaults": defaults, "user": user}


def build_lua(st, touched):
    """Script Lua qui amène Hyprland à l'état voulu.
    `touched` : touches déjà modifiées auparavant (à rétablir si besoin)."""
    user, defaults = st["user"], st["defaults"]
    custom = user["custom"]
    keys = set(touched)
    keys |= {d["keys"] for d in defaults if d["id"] in user["disabled"]}
    keys |= {d["keys"] for d in defaults if d["id"] in {c.get("replaces") for c in custom}}
    keys |= {c["keys"] for c in custom}
    norms = {norm(k) for k in keys}
    lines = ["-- Généré par `binds` (assets/binds.py), ne pas éditer à la main"]
    for k in sorted(keys):
        lines.append("hl.unbind(%s)" % json.dumps(k))
    replaced = {c.get("replaces") for c in custom}
    for d in defaults:
        if d["norm"] in norms and d["id"] not in user["disabled"] and d["id"] not in replaced:
            lines.append("hl.bind(%s, %s, %s)" % (json.dumps(d["keys"]), d["lua"], d["opts"]))
    for c in custom:
        action, opts = custom_lua(c)
        lines.append("hl.bind(%s, %s, %s)" % (json.dumps(c["keys"], ensure_ascii=False), action, opts))
    return "\n".join(lines) + "\n", sorted(keys)


def hypr_eval(code):
    r = subprocess.run([HYPRCTL, "eval", code], capture_output=True, text=True)
    out = (r.stdout + r.stderr).strip()
    return None if out in ("", "ok") else out


def apply(st):
    """Écrit binds-user.lua et applique à chaud. Retourne un message d'erreur ou ''."""
    try:
        with open(TOUCHED_JSON) as f:
            touched = json.load(f)
    except (OSError, ValueError):
        touched = []
    live, all_keys = build_lua(st, touched)
    # Au démarrage, hyprland.lua vient de définir les défauts : seules les
    # désactivations et les binds perso comptent
    boot, _ = build_lua(st, [])
    os.makedirs(os.path.dirname(USER_LUA), exist_ok=True)
    with open(USER_LUA, "w") as f:
        f.write(boot)
    live_file = os.path.join(STATE, "apply.lua")
    os.makedirs(STATE, exist_ok=True)
    with open(live_file, "w") as f:
        f.write(live)
    err = hypr_eval("dofile(%s)" % json.dumps(live_file))
    if err:
        return err
    save_json(TOUCHED_JSON, all_keys)
    return ""


def finish(st_mut=None, err=""):
    st = state()
    e = apply(st) if st_mut is None else err
    out = {"binds": st["binds"], "disabled": st["user"]["disabled"]}
    if e:
        out["error"] = e
    print(json.dumps(out, ensure_ascii=False))


def clean(data, ident=None):
    """Valide un bind perso reçu de l'interface. Retourne (bind, erreur)."""
    keys = str(data.get("keys", "")).strip()
    kind = data.get("kind", "exec")
    value = str(data.get("value", "")).strip()
    mods, key = parse_keys(keys)
    if not key:
        return None, "Touche manquante"
    if kind not in ("exec", "lua") or not value:
        return None, "Action manquante"
    if kind == "lua" and not lua_check(value):
        return None, "Expression Lua invalide"
    return {
        "id": ident or "c:" + uuid.uuid4().hex[:8], "keys": " + ".join(mods + [key]),
        "kind": kind, "value": value, "desc": str(data.get("desc", "")).strip(),
        "flags": [f for f in data.get("flags", []) if f in FLAGS],
        "replaces": data.get("replaces", ""),
    }, ""


def main():
    a = sys.argv[1:]
    cmd = a[0] if a else "list"
    if cmd == "list":
        st = state()
        print(json.dumps({"binds": st["binds"], "disabled": st["user"]["disabled"]}, ensure_ascii=False))
        return
    if cmd == "capture":
        if a[1:2] == ["start"]:
            hypr_eval('hl.define_submap("%s", function() hl.bind("SUPER + CTRL + ALT + F12", '
                      'hl.dsp.submap("reset")) end)' % SUBMAP)
            subprocess.run([HYPRCTL, "dispatch", 'hl.dsp.submap("%s")' % SUBMAP], capture_output=True)
            # Garde-fou : si l'interface plante en pleine capture, les binds reviennent seuls
            subprocess.Popen(["sh", "-c", "sleep 25; %s dispatch 'hl.dsp.submap(\"reset\")'" % HYPRCTL],
                             start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            subprocess.run([HYPRCTL, "dispatch", 'hl.dsp.submap("reset")'], capture_output=True)
        return
    st = state()
    user = st["user"]
    if cmd == "apply":
        finish()
        return
    if cmd == "reset":
        user["disabled"], user["custom"] = [], []
    elif cmd == "toggle":
        i = a[1]
        if i in user["disabled"]:
            user["disabled"].remove(i)
        else:
            user["disabled"].append(i)
    elif cmd == "delete":
        i = a[1]
        c = next((c for c in user["custom"] if c["id"] == i), None)
        if c:
            user["custom"].remove(c)
            if c.get("replaces") in user["disabled"]:
                user["disabled"].remove(c["replaces"])
    elif cmd in ("add", "update"):
        data = json.loads(a[-1])
        ident = a[1] if cmd == "update" else None
        orig = next((d for d in st["defaults"] if d["id"] == ident), None)
        if orig:                                  # modifier un défaut = le remplacer
            data["replaces"] = orig["id"]
            ident = None
        c, err = clean(data, ident)
        if err:
            finish(True, err)
            return
        if orig and orig["id"] not in user["disabled"]:
            user["disabled"].append(orig["id"])
        user["custom"] = [x for x in user["custom"] if x["id"] != c["id"]] + [c]
    else:
        sys.exit("commande inconnue : " + cmd)
    save_json(USER_JSON, user)
    finish()


if __name__ == "__main__":
    main()
