#!/usr/bin/env python3
"""Étend une image sur tous les écrans (mode « span » du sélecteur de fonds).

Usage : wallpaper-span.py <image> [fade|none]
Env   : AWWW, MAGICK, HYPRCTL, SPAN_CACHE
Rectangle englobant des écrans (taille logique : rotation et échelle prises en
compte) ; l'image le recouvre (recadrage centré), puis chaque écran reçoit sa part.
"""
import fcntl
import json
import os
import subprocess
import sys

img = sys.argv[1]
trans = sys.argv[2] if len(sys.argv) > 2 else "fade"
awww, magick, hyprctl = os.environ["AWWW"], os.environ["MAGICK"], os.environ["HYPRCTL"]
cache = os.environ["SPAN_CACHE"]
os.makedirs(cache, exist_ok=True)
# Un seul calcul à la fois (applications rapprochées : clics, rebranchement d'écran)
lock = open(os.path.join(cache, ".lock"), "w")
fcntl.flock(lock, fcntl.LOCK_EX)

mons = []
for m in json.loads(subprocess.check_output([hyprctl, "monitors", "-j"])):
    w, h = m["width"], m["height"]
    if m["transform"] % 2:
        w, h = h, w
    s = m.get("scale") or 1
    mons.append((m["name"], m["x"], m["y"], round(w / s), round(h / s), w, h))
if not mons:
    sys.exit(1)

x0 = min(m[1] for m in mons)
y0 = min(m[2] for m in mons)
bw = max(m[1] + m[3] for m in mons) - x0
bh = max(m[2] + m[4] for m in mons) - y0

big = os.path.join(cache, "span-full.miff")
subprocess.check_call([magick, img + "[0]", "-auto-orient", "-resize", f"{bw}x{bh}^",
                       "-gravity", "center", "-extent", f"{bw}x{bh}", big])

for name, x, y, lw, lh, pw, ph in mons:
    out = os.path.join(cache, f"span-{name}.png")
    subprocess.check_call([magick, big, "-gravity", "NorthWest", "-crop", f"{lw}x{lh}+{x - x0}+{y - y0}", "+repage",
                           "-resize", f"{pw}x{ph}!", out])
    cmd = [awww, "img", out, "-o", name, "--transition-type", trans]
    if trans != "none":
        cmd += ["--transition-duration", "1.2", "--transition-bezier", ".25,.1,.25,1",
                "--transition-fps", "144"]
    subprocess.check_call(cmd)
