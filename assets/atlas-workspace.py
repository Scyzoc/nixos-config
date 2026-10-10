"""atlas-workspace : espaces de travail par projet Atlas (menu Quickshell, SUPER+H).

  atlas-workspace list [--refresh]   projets Atlas + recette + logo (JSON) ; --refresh
                                     relit Atlas (atlas-task meta + logos), sinon le cache
  atlas-workspace save ID '<json>'   enregistre la recette du projet ID
  atlas-workspace launch ID          ouvre les fenêtres du projet sur le workspace
                                     vide le plus proche (écran actif)
  atlas-workspace context            hook SessionStart de Claude Code : si le dossier
                                     courant est celui d'un projet Atlas, consignes MCP

Recettes : ~/.config/atlas/workspaces.json = {"<id>": {"dir": "...", "windows": [...]}}
Fenêtres : {"type": "terminal", "cmd": "pnpm dev"}   kitty dans le dossier (cmd facultative,
                                                       le shell reste ouvert après)
           {"type": "claude", "cmd": "--continue"}    kitty + Claude Code (arguments facultatifs)
           {"type": "browser", "url": "http://..."}   nouvelle fenêtre Brave
           {"type": "atlas"}                          page du projet dans Atlas (appli Brave)
           {"type": "app", "cmd": "code ."}           commande lancée dans le dossier
"""
import json
import os
import shlex
import subprocess
import sys
import time
import unicodedata
import urllib.parse
import urllib.request

HYPRCTL = os.environ.get("HYPRCTL", "hyprctl")
KITTY = os.environ.get("KITTY", "kitty")
BRAVE = os.environ.get("BRAVE", "brave")
ATLAS_TASK = os.environ.get("ATLAS_TASK", "atlas-task")
ATLAS_WEB = "https://atlas.homelab.lan"
PROJECTS_DIR = os.path.expanduser("~/Documents/PROJETS")
CONF = os.path.expanduser("~/.config/atlas/workspaces.json")
CACHE = os.path.join(os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
                     "atlas-task", "meta.json")
LOGOS = os.path.join(os.path.dirname(CACHE), "logos")
HIDDEN = ("termine", "archive", "brouillon")


def norm(s):
    s = unicodedata.normalize("NFD", s or "").encode("ascii", "ignore").decode().lower()
    return "".join(c for c in s if c.isalnum())


def load_conf():
    try:
        with open(CONF) as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def atlas_client():
    """Client MCP d'atlas-task.py (même dossier assets/, chemin donné par le module nix)."""
    import importlib.util
    path = os.environ.get("ATLAS_TASK_PY",
                          os.path.join(os.path.dirname(os.path.abspath(__file__)), "atlas-task.py"))
    spec = importlib.util.spec_from_file_location("atlas_task", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def refresh_logos():
    """Logos des projets (table project : emoji, icône ou image d'/uploads/) → cache local."""
    at = atlas_client()
    with at.Client() as c:
        rows = c.tool("query_database", {
            "sql": "SELECT id, logo_kind, logo_value FROM project"})["rows"]
    os.makedirs(LOGOS, exist_ok=True)
    out = {}
    for r in rows:
        kind, val = r.get("logo_kind"), r.get("logo_value")
        if not kind or not val:
            continue
        if kind == "image":
            name = os.path.basename(val)
            dest = os.path.join(LOGOS, name)
            if not os.path.exists(dest):
                try:
                    with urllib.request.urlopen(at.base_url() + "/uploads/" + urllib.parse.quote(name),
                                                context=at.CTX, timeout=10) as resp:
                        data = resp.read()
                    with open(dest + ".tmp", "wb") as f:
                        f.write(data)
                    os.replace(dest + ".tmp", dest)
                except Exception:
                    continue
            val = dest
        out[str(r["id"])] = {"kind": kind, "value": val}
    with open(LOGOS + ".json.tmp", "w") as f:
        json.dump(out, f, ensure_ascii=False)
    os.replace(LOGOS + ".json.tmp", LOGOS + ".json")


def load_logos():
    try:
        with open(LOGOS + ".json") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def projects(refresh=False):
    if refresh:
        r = subprocess.run([ATLAS_TASK, "meta"], capture_output=True, text=True)
        if r.returncode != 0:
            try:
                raise RuntimeError(json.loads(r.stdout)["error"])
            except (ValueError, KeyError):
                raise RuntimeError("Atlas injoignable")
        try:
            refresh_logos()
        except Exception:
            pass    # logos facultatifs : on garde ceux du cache
    try:
        with open(CACHE) as f:
            return json.load(f).get("projects", [])
    except (OSError, ValueError):
        return []


def guess_dir(name):
    """Dossier de ~/Documents/PROJETS au nom du projet (« DashFinance » → DashFinance/)."""
    n = norm(name)
    try:
        for d in sorted(os.listdir(PROJECTS_DIR)):
            p = os.path.join(PROJECTS_DIR, d)
            if os.path.isdir(p) and norm(d) == n:
                return p
    except OSError:
        pass
    return ""


def recipe(p, conf):
    r = conf.get(str(p["id"]))
    if r:
        return {"dir": os.path.expanduser(r.get("dir", "")), "windows": r.get("windows", []),
                "configured": True}
    return {"dir": guess_dir(p["name"]), "windows": [], "configured": False}


def cmd_list(refresh):
    conf = load_conf()
    out = []
    ps = projects(refresh)
    logos = load_logos()
    for p in ps:
        if p.get("status") in HIDDEN:
            continue
        out.append({**p, **recipe(p, conf), "logo": logos.get(str(p["id"]))})
    print(json.dumps({"projects": out}, ensure_ascii=False))


def cmd_save(pid, raw):
    r = json.loads(raw)
    conf = load_conf()
    conf[str(pid)] = {"dir": r.get("dir", "").strip(),
                      "windows": [w for w in r.get("windows", []) if w.get("type")]}
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    with open(CONF + ".tmp", "w") as f:
        json.dump(conf, f, ensure_ascii=False, indent=2)
    os.replace(CONF + ".tmp", CONF)
    print(json.dumps({"ok": True}))


# --- Lancement ---------------------------------------------------------------------------
def hypr(*args):
    return subprocess.run([HYPRCTL, *args], capture_output=True, text=True).stdout


def hypr_json(what):
    try:
        return json.loads(hypr("-j", what))
    except ValueError:
        return []


def empty_workspace():
    """Workspace vide le plus proche de l'actif, sur l'écran actif (à égalité : le suivant)."""
    mon = next((m for m in hypr_json("monitors") if m.get("focused")), None)
    if not mon:
        return 1
    cur = mon["activeWorkspace"]["id"]
    wss = [w for w in hypr_json("workspaces") if w["id"] > 0]
    if not any(w["id"] == cur and w["windows"] for w in wss):
        return cur
    used = {w["id"] for w in wss if w["windows"]}
    # Plage de l'écran : ses workspaces connus (1-10, 11-20…), sinon tout
    mine = [w["id"] for w in wss if w["monitor"] == mon["name"]]
    lo, hi = (min(mine), max(mine)) if mine else (1, 10)
    for d in range(1, 100):
        for c in (cur + d, cur - d):
            if lo <= c <= hi and c not in used:
                return c
    return max(used) + 1


def window_cmd(w, p, d):
    t = w.get("type")
    title = f"{p['name']} · "
    if t in ("terminal", "claude"):
        cmd = w.get("cmd", "").strip()
        if t == "claude":
            cmd = ("claude " + cmd).strip()
            title += "Claude Code"
        else:
            title += cmd or "terminal"
        # Shell interactif : PATH de ~/.bashrc (claude, pnpm) ; reste ouvert après la commande
        sh = (cmd + "; " if cmd else "") + "exec bash"
        return [KITTY, "--directory", d, "--title", title, "bash", "-ic", sh]
    if t == "browser" and w.get("url"):
        return [BRAVE, "--new-window", w["url"]]
    if t == "atlas":
        return [BRAVE, f"--app={ATLAS_WEB}/projects/{p['id']}"]
    if t == "app" and w.get("cmd"):
        return ["sh", "-c", f"cd {shlex.quote(d)} && exec {w['cmd']}"]
    return None


def cmd_launch(pid):
    p = next((x for x in projects() if x["id"] == pid), None)
    if not p:
        raise RuntimeError("Projet inconnu")
    r = recipe(p, load_conf())
    d = r["dir"] or os.path.expanduser("~")
    windows = r["windows"] or [{"type": "terminal"}]
    ws = empty_workspace()
    hypr("dispatch", "workspace", str(ws))
    for i, w in enumerate(windows):
        argv = window_cmd(w, p, d)
        if not argv:
            continue
        # Une à une : la disposition (dwindle) suit l'ordre de la recette
        if i:
            time.sleep(0.35)
        hypr("dispatch", "exec", f"[workspace {ws} silent] " + shlex.join(argv))
    print(json.dumps({"ok": True, "workspace": ws}))


# --- Hook Claude Code -------------------------------------------------------------------
def cmd_context():
    try:
        cwd = json.load(sys.stdin).get("cwd") or os.getcwd()
    except ValueError:
        cwd = os.getcwd()
    cwd = os.path.realpath(cwd)
    conf = load_conf()
    best, best_len = None, -1
    for p in projects():
        d = recipe(p, conf)["dir"]
        if not d:
            continue
        d = os.path.realpath(d)
        if (cwd == d or cwd.startswith(d + os.sep)) and len(d) > best_len:
            best, best_len = p, len(d)
    if not best:
        return
    ctx = (
        f"Ce dossier est celui du projet Atlas « {best['name']} » (projectId {best['id']}).\n"
        "Le serveur MCP « atlas » donne accès à ses tâches : consulte-les (list_tasks avec "
        f"projectId {best['id']}) quand c'est utile pour savoir où en est le projet ou quoi faire.\n"
        "Consigne permanente : chaque fois qu'on termine quelque chose qui en vaut la peine "
        "(fonctionnalité, correctif de bug, refonte, configuration notable…), crée la tâche "
        f"correspondante dans ce projet avec create_task (projectId {best['id']}, "
        "status « terminee », titre court en français, notes facultatives). Si une tâche "
        "ouverte du projet correspond déjà au travail fait, termine-la (complete_task) plutôt "
        "que d'en créer une nouvelle. Pas de tâche pour les micro-changements "
        "(typo, simple question, exploration). Signale en une ligne la tâche créée ou terminée."
    )
    print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
                                             "additionalContext": ctx}}, ensure_ascii=False))


def main():
    a = sys.argv[1:]
    try:
        if not a or a[0] == "list":
            cmd_list("--refresh" in a)
        elif a[0] == "save" and len(a) == 3:
            cmd_save(int(a[1]), a[2])
        elif a[0] == "launch" and len(a) == 2:
            cmd_launch(int(a[1]))
        elif a[0] == "context":
            cmd_context()
        else:
            print(__doc__, file=sys.stderr)
            sys.exit(2)
    except Exception as e:
        if a and a[0] == "context":
            return    # le hook ne doit jamais gêner Claude Code
        print(json.dumps({"error": str(e)}, ensure_ascii=False))
        sys.exit(1)


if __name__ == "__main__":
    main()
