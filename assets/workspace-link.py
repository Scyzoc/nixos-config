"""workspace-link : workspaces liés par paires (ex : 1 ↔ 6).

Quand un workspace lié devient actif sur un écran, son jumeau est affiché sur
son propre écran (celui défini par les groupes de la disposition, voir
workspace-bind dans modules/display-switch.nix), sans voler le focus ni la
souris. Les liens marchent dans les deux sens ; ignorés s'il n'y a qu'un écran
ou si les deux workspaces vivent sur le même écran.

  workspace-link daemon      démon (service systemd), écoute le socket Hyprland
  workspace-link state       état JSON pour le menu Quickshell (SUPER+P)
  workspace-link add A B     ajoute la paire A ↔ B
  workspace-link del A B     retire la paire
  workspace-link toggle      active / désactive toutes les liaisons

Config : ~/.local/state/workspace-links.json = {"enabled": bool, "pairs": [[A, B], …]}
"""
import json
import os
import socket
import subprocess
import sys
import time

HYPRCTL = os.environ.get("HYPRCTL", "hyprctl")
CONF = os.path.expanduser("~/.local/state/workspace-links.json")
RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
# Verrou de display-apply : pendant un changement de mode, on n'intervient pas
DISPLAY_LOCK = os.path.join(RUNTIME, "display-apply.lock")


def hypr_json(what):
    r = subprocess.run([HYPRCTL, "-j", what], capture_output=True, text=True)
    try:
        return json.loads(r.stdout)
    except ValueError:
        return []


def load():
    try:
        with open(CONF) as f:
            c = json.load(f)
        pairs = [[int(a), int(b)] for a, b in c.get("pairs", [])]
        return {"enabled": bool(c.get("enabled", True)), "pairs": pairs}
    except (OSError, ValueError, TypeError):
        return {"enabled": True, "pairs": []}


def save(c):
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    tmp = CONF + ".tmp"
    with open(tmp, "w") as f:
        json.dump(c, f)
    os.replace(tmp, CONF)


def ws_monitor(ws, workspaces, rules):
    """Écran d'un workspace : celui où il existe, sinon celui de sa règle."""
    for w in workspaces:
        if w["id"] == ws:
            return w["monitor"]
    for r in rules:
        if r.get("workspaceString") == str(ws) and r.get("monitor"):
            return r["monitor"]
    return None


def live_monitors():
    """{écran: workspace actif} des écrans actifs hors miroir + écran focalisé."""
    mons = [m for m in hypr_json("monitors")
            if not m.get("disabled") and m.get("mirrorOf", "none") == "none"]
    active = {m["name"]: m["activeWorkspace"]["id"] for m in mons}
    focused = next((m["name"] for m in mons if m.get("focused")), None)
    return active, focused


# --- Démon ---------------------------------------------------------------------

def follow(ws, focused, active):
    """Affiche les jumeaux de `ws` (écran `focused`) sur leurs écrans."""
    conf = load()
    if not conf["enabled"] or len(active) < 2:
        return False
    partners = {b if a == ws else a for a, b in conf["pairs"] if ws in (a, b)}
    if not partners:
        return False
    workspaces, rules = hypr_json("workspaces"), hypr_json("workspacerules")
    visible = set(active.values())
    cmds = []
    for p in sorted(partners):
        if p in visible:
            continue
        mon = ws_monitor(p, workspaces, rules)
        if mon not in active or mon == focused:
            continue
        cmds += [f"dispatch focusmonitor {mon}",
                 f"dispatch focusworkspaceoncurrentmonitor {p}"]
        visible.add(p)
    if not cmds:
        return False
    # Retour sur l'écran d'origine, souris remise où elle était
    pos = hypr_json("cursorpos")
    cmds.append(f"dispatch focusmonitor {focused}")
    if isinstance(pos, dict) and "x" in pos:
        cmds.append(f"dispatch movecursor {pos['x']} {pos['y']}")
    subprocess.run([HYPRCTL, "--batch", " ; ".join(cmds)], capture_output=True)
    return True


def daemon():
    sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
    path = os.path.join(RUNTIME, "hypr", sig, ".socket2.sock")
    while True:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(path)
        except OSError:
            time.sleep(1)
            continue
        active, _ = live_monitors()
        buf = b""
        while True:
            data = s.recv(4096)
            if not data:
                break
            buf += data
            lines = buf.split(b"\n")
            buf = lines.pop()
            # Rafale d'événements : un seul passage suffit
            if not any(l.startswith(b"workspacev2>>") for l in lines):
                if any(l.startswith((b"monitoradded", b"monitorremoved")) for l in lines):
                    active, _ = live_monitors()
                continue
            now, focused = live_monitors()
            # Seul un vrai changement de workspace sur l'écran focalisé compte : passer
            # d'un écran à l'autre (souris) émet aussi workspacev2 sans rien changer
            changed = focused and active.get(focused) != now.get(focused)
            active = now
            if not changed or os.path.exists(DISPLAY_LOCK):
                continue
            ws = now[focused]
            if ws > 0 and follow(ws, focused, now):
                active, _ = live_monitors()
        s.close()


# --- CLI -------------------------------------------------------------------------

def state():
    conf = load()
    workspaces, rules = hypr_json("workspaces"), hypr_json("workspacerules")
    mons = {m["name"] for m in hypr_json("monitors")}
    ids = {w for p in conf["pairs"] for w in p}
    conf["monitors"] = {str(w): ws_monitor(w, workspaces, rules) for w in ids}
    conf["live"] = sorted(mons)
    print(json.dumps(conf))


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "state"
    if cmd == "daemon":
        daemon()
    elif cmd == "state":
        state()
    elif cmd == "toggle":
        c = load()
        c["enabled"] = not c["enabled"]
        save(c)
    elif cmd in ("add", "del") and len(args) == 3:
        try:
            a, b = int(args[1]), int(args[2])
        except ValueError:
            sys.exit(1)
        if a == b or a < 1 or b < 1:
            sys.exit(1)
        c = load()
        pair = sorted((a, b))
        c["pairs"] = [p for p in c["pairs"] if sorted(p) != pair]
        if cmd == "add":
            c["pairs"].append(pair)
            c["pairs"].sort()
        save(c)
    else:
        print(__doc__, file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
