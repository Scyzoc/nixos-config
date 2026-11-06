"""Démon du mode Cours : détecte les cours de l'emploi du temps Atlas.

Lit le rapport du jour d'Atlas (outil MCP get_report), garde les cours non annulés,
et maintient $XDG_RUNTIME_DIR/cours-auto tant qu'un cours est en cours.
Un forçage manuel (cours on / off) est levé à chaque début ou fin de cours.
"""
import datetime
import importlib.util
import json
import os
import subprocess
import sys
import time

RUNTIME = os.environ.get("XDG_RUNTIME_DIR", "/tmp")
AUTO = RUNTIME + "/cours-auto"
FORCE_ON = RUNTIME + "/cours-mode"
FORCE_OFF = RUNTIME + "/cours-off"
REFRESH = 600       # relecture d'Atlas (s)
TICK = 30           # recalcul de l'état (s)
NOTIFY = os.environ.get("COURS_NOTIFY", "notify-send")
ATLAS = sys.argv[1]


def load_client():
    spec = importlib.util.spec_from_file_location("atlas_task", ATLAS)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.Client


def fetch_courses(Client):
    with Client() as c:
        r = c.request("tools/call", {"name": "get_report", "arguments": {}})
    data = json.loads(r["content"][0]["text"])
    courses = []
    for e in data.get("events", []):
        if e.get("cancelled") or e.get("canceled") or e.get("annule"):
            continue
        if e.get("start") and e.get("end"):
            courses.append((e["start"], e["end"], e.get("title", "")))
    return data.get("today"), courses


def current(courses, now):
    hm = now.strftime("%H:%M")
    for start, end, title in courses:
        if start <= hm < end:
            return title
    return None


def rm(path):
    try:
        os.remove(path)
    except OSError:
        pass


def main():
    Client = load_client()
    courses, day, last_fetch, active = [], None, 0, False
    while True:
        now = datetime.datetime.now()
        if now.timestamp() - last_fetch > REFRESH or day != now.strftime("%Y-%m-%d"):
            try:
                _, courses = fetch_courses(Client)
                day = now.strftime("%Y-%m-%d")
            except Exception as e:
                print("cours-sync :", e, file=sys.stderr)
                if day != now.strftime("%Y-%m-%d"):
                    courses = []
            last_fetch = now.timestamp()
        title = current(courses, now)
        if bool(title) != active:
            active = bool(title)
            rm(FORCE_ON)
            rm(FORCE_OFF)
            if active:
                open(AUTO, "w").close()
                subprocess.run([NOTIFY, "-a", "Cours", "-h",
                                "string:x-canonical-private-synchronous:cours",
                                "Mode Cours activé", title])
            else:
                rm(AUTO)
                subprocess.run([NOTIFY, "-a", "Cours", "-h",
                                "string:x-canonical-private-synchronous:cours",
                                "Mode Cours désactivé", "Fin du cours"])
        time.sleep(TICK)


main()
