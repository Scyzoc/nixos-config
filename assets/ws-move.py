"""ws-move <src> <dst> : déplace les fenêtres d'un workspace vers un autre en
conservant la disposition dwindle (sens des découpes et proportions).
ws-move --compact [écran] : idem pour compacter les workspaces d'un écran (par
défaut l'écran actif ; ex : 13 seul → 11), utilisé par ws-compact
(Super+Ctrl+Tab, suggestion de la barre Quickshell).

L'arbre dwindle est déduit de la géométrie (partition en guillotine), puis
reconstruit sur la cible avec `layoutmsg preselect` + `splitratio exact`.
"""
import json
import os
import subprocess
import sys

HYPRCTL = os.environ.get("HYPRCTL", "hyprctl")
TOL = 4  # px de tolérance pour les arrondis


def hypr_json(what):
    return json.loads(subprocess.run([HYPRCTL, "-j", what], check=True,
                                     capture_output=True, text=True).stdout)


def batch(cmds):
    if cmds:
        subprocess.run([HYPRCTL, "--batch", " ; ".join(cmds)], check=True,
                       capture_output=True)


def rect(c):
    x, y = c["at"]
    w, h = c["size"]
    return (x, y, x + w, y + h)


def bbox(ws):
    rs = [rect(c) for c in ws]
    return (min(r[0] for r in rs), min(r[1] for r in rs),
            max(r[2] for r in rs), max(r[3] for r in rs))


def split(ws):
    """Arbre : fenêtre (feuille) ou (sens, ratio, A, B), A à gauche / en haut."""
    if len(ws) == 1:
        return ws[0]
    box = bbox(ws)
    for axis, d in ((0, "r"), (1, "d")):  # 0 : découpe verticale, 1 : horizontale
        for cut in sorted({rect(c)[axis + 2] for c in ws}):
            a = [c for c in ws if rect(c)[axis + 2] <= cut + TOL]
            b = [c for c in ws if rect(c)[axis] >= cut - TOL]
            if a and b and len(a) + len(b) == len(ws):
                mid = (cut + min(rect(c)[axis] for c in b)) / 2
                lo, hi = box[axis], box[axis + 2]
                ratio = min(1.9, max(0.1, 2 * (mid - lo) / (hi - lo)))
                return (d, ratio, split(a), split(b))
    return None  # pas une guillotine (groupes…) : repli sur un simple déplacement


def first(node):
    return node if isinstance(node, dict) else first(node[2])


def default_ratio():
    out = subprocess.run([HYPRCTL, "-j", "getoption", "dwindle:default_split_ratio"],
                         check=True, capture_output=True, text=True).stdout
    return json.loads(out).get("float", 1.0)


def build(node, dst, cmds, base):
    """Insère le sous-arbre ; la 1re feuille de `node` est déjà sur dst."""
    if isinstance(node, dict):
        return
    d, ratio, a, b = node
    anchor, new = first(a)["address"], first(b)["address"]
    cmds += [f"dispatch focuswindow address:{anchor}",
             f"dispatch layoutmsg preselect {d}",
             f"dispatch movetoworkspacesilent {dst},address:{new}",
             f"dispatch focuswindow address:{anchor}",
             # Hyprland 0.56 : splitratio n'accepte qu'un delta (pas « exact »)
             f"dispatch layoutmsg splitratio {ratio - base:.4f}"]
    build(a, dst, cmds, base)
    build(b, dst, cmds, base)


def plan(src, dst, wins, base):
    """Commandes qui déplacent les fenêtres `wins` de src vers dst."""
    tiled = [c for c in wins if not c["floating"]]
    floating = [c for c in wins if c["floating"]]
    tree = split(tiled) if tiled else None
    cmds = []
    if tree is None:
        cmds += [f"dispatch movetoworkspacesilent {dst},address:{c['address']}" for c in tiled]
    else:
        cmds.append(f"dispatch movetoworkspacesilent {dst},address:{first(tree)['address']}")
        build(tree, dst, cmds, base)
    cmds += [f"dispatch movetoworkspacesilent {dst},address:{c['address']}" for c in floating]
    return cmds


def compact_moves(clients, monitors, workspaces, name=None):
    """Workspaces non vides de l'écran → premiers workspaces de cet écran, sans trou."""
    mon = next((m["id"] for m in monitors if m["name"] == name or (not name and m["focused"])), None)
    slots = sorted({w["id"] for w in workspaces if w["monitorID"] == mon and w["id"] > 0})
    used = sorted({c["workspace"]["id"] for c in clients
                   if c["monitor"] == mon and c["workspace"]["id"] > 0})
    return [(w, t) for w, t in zip(used, slots) if w != t]


def main():
    clients = hypr_json("clients")
    monitors = hypr_json("monitors")
    workspaces = hypr_json("workspaces")
    if sys.argv[1:2] == ["--compact"]:
        moves = compact_moves(clients, monitors, workspaces, (sys.argv[2:] or [None])[0])
    else:
        src, dst = int(sys.argv[1]), int(sys.argv[2])
        moves = [(src, dst)] if src != dst else []
    srcs = {s for s, _ in moves}
    if not any(c["workspace"]["id"] in srcs for c in clients):
        return

    active = hypr_json("activewindow").get("address")
    cursor = hypr_json("cursorpos")
    focused_ws = next(m["activeWorkspace"]["id"] for m in monitors if m["focused"])
    ws_mon = {w["id"]: w["monitorID"] for w in workspaces}
    touched = {ws_mon.get(w) for move in moves for w in move}

    # Plein écran / maximisé : retiré le temps de lire la vraie disposition
    full = [c for c in clients if c["workspace"]["id"] in srcs
            and (c["fullscreen"] or c["fullscreenClient"])]
    if full:
        batch([cmd for c in full for cmd in (
            f"dispatch focuswindow address:{c['address']}",
            "dispatch fullscreenstate 0 0")])
        clients = hypr_json("clients")

    base = default_ratio()
    cmds = []
    for src, dst in moves:
        cmds += plan(src, dst, [c for c in clients if c["workspace"]["id"] == src], base)
    for c in full:
        cmds += [f"dispatch focuswindow address:{c['address']}",
                 f"dispatch fullscreenstate {c['fullscreen']} {c['fullscreenClient']}"]

    # Vues : chaque écran touché réaffiche son workspace (ou sa nouvelle place
    # s'il a été déplacé) ; l'écran actif en dernier pour garder le focus
    dest = dict(moves)
    for m in sorted(monitors, key=lambda m: m["focused"]):
        if m["id"] in touched:
            shown = m["activeWorkspace"]["id"]
            cmds.append(f"dispatch workspace {dest.get(shown, shown)}")
    if active:
        cmds.append(f"dispatch focuswindow address:{active}")
    if focused_ws not in dest:
        cmds.append(f"dispatch movecursor {cursor['x']} {cursor['y']}")
    batch(cmds)


main()
