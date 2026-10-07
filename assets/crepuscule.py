"""Crépuscule — backend du filtre anti-lumière bleue (gammastep) et du mode sombre.

Lancé par le wrapper `crepuscule-ctl` (modules/crepuscule.nix), qui fournit les chemins
des binaires par variables d'environnement. Sous-commandes :

  state                       état complet en JSON (lu par Crepuscule.qml)
  apply                       régénère la config gammastep + les heures du soleil, relance le filtre si besoin
  gen                         régénère seulement les fichiers (ExecStartPre du service)
  enabled                     code 0 si le filtre doit tourner (ExecCondition du service)
  set <clé> <valeur>          filter.mode / filter.start / filter.end / filter.offset / filter.temp / filter.brightness
  set-city <nom> <région> <lat> <lon>
  geocode <recherche>         villes correspondantes en JSON (API Open-Meteo)
  theme <mode|hours|dark|light> [...]   délégué à la commande `theme` (theme-automation.nix)
"""

import json
import math
import os
import subprocess
import sys
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

HOME = os.path.expanduser("~")
CONF_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "crepuscule")
CONF = os.path.join(CONF_DIR, "config.json")
GAMMA_INI = os.path.join(CONF_DIR, "gammastep.ini")
SUN_CONF = os.path.join(CONF_DIR, "sun.conf")    # lu par theme-auto (mode sombre « soleil »)
THEME_CONF = os.path.join(HOME, ".config", "theme-automation", "hours.conf")

SYSTEMCTL = os.environ.get("CREPUSCULE_SYSTEMCTL", "systemctl")
GSETTINGS = os.environ.get("CREPUSCULE_GSETTINGS", "gsettings")
THEME = os.environ.get("CREPUSCULE_THEME", "theme")
UNIT = "crepuscule-filter.service"

TRANSITION = 30      # minutes de fondu au début et à la fin du filtre

DEFAULT = {
    "city": {"name": "Paris", "region": "Île-de-France, France", "lat": 48.8566, "lon": 2.3522},
    "filter": {
        "mode": "sun",          # sun | hours | always | off
        "start": "21:00",       # mode horaires
        "end": "07:00",
        "offset": 0,            # mode soleil : minutes d'avance sur le coucher (négatif = retard)
        "temp": 3500,           # K
        "brightness": 90,       # %
    },
}


# --- Config ------------------------------------------------------------------------------

def load():
    cfg = json.loads(json.dumps(DEFAULT))
    try:
        with open(CONF) as f:
            data = json.load(f)
        for k in ("city", "filter"):
            if isinstance(data.get(k), dict):
                cfg[k].update(data[k])
    except (OSError, ValueError):
        pass
    return cfg


def write_if_changed(path, text):
    """Écrit le fichier (atomiquement) seulement si son contenu change. Renvoie True si changé."""
    try:
        with open(path) as f:
            if f.read() == text:
                return False
    except OSError:
        pass
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(text)
    os.replace(tmp, path)
    return True


def save(cfg):
    write_if_changed(CONF, json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")


# --- Heures ------------------------------------------------------------------------------

def to_min(hhmm):
    h, m = hhmm.split(":")
    h, m = int(h), int(m)
    if not (0 <= h <= 23 and 0 <= m <= 59):
        raise ValueError(hhmm)
    return h * 60 + m


def fmt(minutes):
    minutes = int(round(minutes)) % 1440
    return "%02d:%02d" % (minutes // 60, minutes % 60)


def sun_times(lat, lon, day):
    """Lever / coucher du soleil (minutes locales depuis minuit) — algorithme NOAA, ±2 min.
    None si le soleil ne se lève ou ne se couche pas ce jour-là (régions polaires)."""
    g = 2 * math.pi / 365 * (day.timetuple().tm_yday - 1)
    eqtime = 229.18 * (0.000075 + 0.001868 * math.cos(g) - 0.032077 * math.sin(g)
                       - 0.014615 * math.cos(2 * g) - 0.040849 * math.sin(2 * g))
    decl = (0.006918 - 0.399912 * math.cos(g) + 0.070257 * math.sin(g)
            - 0.006758 * math.cos(2 * g) + 0.000907 * math.sin(2 * g)
            - 0.002697 * math.cos(3 * g) + 0.00148 * math.sin(3 * g))
    phi = math.radians(lat)
    x = math.cos(math.radians(90.833)) / (math.cos(phi) * math.cos(decl)) - math.tan(phi) * math.tan(decl)
    if not -1 <= x <= 1:
        return None
    ha = math.degrees(math.acos(x))
    midnight = datetime(day.year, day.month, day.day, tzinfo=timezone.utc)

    def local(utc_min):
        t = (midnight + timedelta(minutes=utc_min)).astimezone()
        return t.hour * 60 + t.minute + t.second / 60

    return local(720 - 4 * (lon + ha) - eqtime), local(720 - 4 * (lon - ha) - eqtime)


def filter_window(cfg):
    """(début, fin) du filtre en minutes, ou None (toujours actif / désactivé)."""
    f = cfg["filter"]
    if f["mode"] == "hours":
        return to_min(f["start"]), to_min(f["end"])
    if f["mode"] == "sun":
        sun = sun_times(cfg["city"]["lat"], cfg["city"]["lon"], date.today())
        if sun is None:
            return to_min(f["start"]), to_min(f["end"])
        rise, set_ = sun
        return set_ - int(f["offset"]), rise
    return None


def in_window(now, start, end):
    return (now >= start or now < end) if start > end else (start <= now < end)


# --- Génération des fichiers -------------------------------------------------------------

def gammastep_ini(cfg):
    f = cfg["filter"]
    temp = max(1000, min(6500, int(f["temp"])))
    bright = max(0.3, min(1.0, int(f["brightness"]) / 100))
    lines = ["[general]", "adjustment-method=wayland", "fade=1"]
    win = filter_window(cfg)
    if win is None:
        # Toujours actif : jour = nuit, l'horaire n'a plus d'effet
        lines += ["temp-day=%d" % temp, "temp-night=%d" % temp,
                  "brightness-day=%.2f" % bright, "brightness-night=%.2f" % bright,
                  "dawn-time=06:00", "dusk-time=20:00"]
    else:
        start, end = win
        # gammastep : fondu du soir (dusk) après celui du matin (dawn) dans la même journée
        dusk_a, dusk_b = start, min(start + TRANSITION, 1439)
        dawn_a, dawn_b = max(end - TRANSITION, 0), end
        lines += ["temp-day=6500", "temp-night=%d" % temp,
                  "brightness-day=1.0", "brightness-night=%.2f" % bright,
                  "dawn-time=%s-%s" % (fmt(dawn_a), fmt(dawn_b)),
                  "dusk-time=%s-%s" % (fmt(dusk_a), fmt(dusk_b))]
    return "\n".join(lines) + "\n"


def generate(cfg):
    """Écrit gammastep.ini et sun.conf. Renvoie True si la config gammastep a changé."""
    sun = sun_times(cfg["city"]["lat"], cfg["city"]["lon"], date.today())
    if sun is not None:
        write_if_changed(SUN_CONF, "SUNRISE=%s\nSUNSET=%s\n" % (fmt(sun[0]), fmt(sun[1])))
    return write_if_changed(GAMMA_INI, gammastep_ini(cfg))


def valid(cfg):
    """Message d'erreur si l'horaire n'est pas représentable par gammastep, sinon None."""
    win = filter_window(cfg)
    if win is None:
        return None
    start, end = win
    if start <= end + 2 * TRANSITION:
        return "Le début doit être le soir et la fin le matin (ex. 21:00 → 07:00)"
    return None


def systemctl(*args):
    return subprocess.run([SYSTEMCTL, "--user", *args], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode


def apply(cfg):
    changed = generate(cfg)
    if cfg["filter"]["mode"] == "off":
        systemctl("stop", UNIT)
    elif changed or systemctl("is-active", "--quiet", UNIT) != 0:
        systemctl("restart", UNIT)
    # Le mode sombre « soleil » relit sun.conf
    systemctl("start", "--no-block", "theme-auto.service")


# --- État ----------------------------------------------------------------------------------

def theme_state():
    conf = {"MODE": "hours", "DARK_HOUR": "20:00", "LIGHT_HOUR": "08:00"}
    try:
        with open(THEME_CONF) as f:
            for line in f:
                k, _, v = line.strip().partition("=")
                if k in conf and v:
                    conf[k] = v
    except OSError:
        pass
    try:
        scheme = subprocess.run([GSETTINGS, "get", "org.gnome.desktop.interface", "color-scheme"],
                                capture_output=True, text=True).stdout.strip()
    except OSError:
        scheme = ""
    return {"mode": conf["MODE"], "dark": conf["DARK_HOUR"], "light": conf["LIGHT_HOUR"],
            "current": "dark" if scheme == "'prefer-dark'" else "light"}


def state():
    cfg = load()
    now = datetime.now()
    now_min = now.hour * 60 + now.minute
    sun = sun_times(cfg["city"]["lat"], cfg["city"]["lon"], date.today())
    win = filter_window(cfg)
    mode = cfg["filter"]["mode"]
    active = mode == "always" or (win is not None and in_window(now_min, *win))
    out = {
        "city": cfg["city"],
        "filter": cfg["filter"],
        "sun": {"rise": fmt(sun[0]), "set": fmt(sun[1])} if sun else None,
        "window": {"start": fmt(win[0]), "end": fmt(win[1])} if win else None,
        "active": active and mode != "off",
        "running": systemctl("is-active", "--quiet", UNIT) == 0,
        "error": valid(cfg),
        "theme": theme_state(),
    }
    print(json.dumps(out, ensure_ascii=False))


# --- Commandes -----------------------------------------------------------------------------

def cmd_set(key, value):
    cfg = load()
    section, _, name = key.partition(".")
    if section != "filter" or name not in DEFAULT["filter"]:
        sys.exit("Clé inconnue : " + key)
    if name == "mode":
        if value not in ("sun", "hours", "always", "off"):
            sys.exit("Mode inconnu : " + value)
        cfg["filter"]["mode"] = value
    elif name in ("start", "end"):
        cfg["filter"][name] = fmt(to_min(value))
    elif name == "offset":
        cfg["filter"]["offset"] = max(-180, min(180, int(value)))
    elif name == "temp":
        cfg["filter"]["temp"] = max(1500, min(6500, int(value)))
    elif name == "brightness":
        cfg["filter"]["brightness"] = max(30, min(100, int(value)))
    save(cfg)
    if valid(cfg) is None:
        apply(cfg)


def cmd_set_city(name, region, lat, lon):
    cfg = load()
    cfg["city"] = {"name": name, "region": region, "lat": float(lat), "lon": float(lon)}
    save(cfg)
    if valid(cfg) is None:
        apply(cfg)


def cmd_geocode(query):
    url = "https://geocoding-api.open-meteo.com/v1/search?" + urllib.parse.urlencode(
        {"name": query, "count": 6, "language": "fr", "format": "json"})
    try:
        with urllib.request.urlopen(url, timeout=8) as r:
            data = json.load(r)
    except Exception:
        print(json.dumps({"error": "Recherche impossible (pas de connexion ?)", "results": []}))
        return
    results = []
    for c in data.get("results") or []:
        region = ", ".join(x for x in (c.get("admin1"), c.get("country")) if x)
        results.append({"name": c["name"], "region": region,
                        "lat": round(c["latitude"], 4), "lon": round(c["longitude"], 4)})
    print(json.dumps({"error": None if results else "Aucune ville trouvée", "results": results},
                     ensure_ascii=False))


def main():
    args = sys.argv[1:]
    cmd = args[0] if args else "state"
    if cmd == "state":
        state()
    elif cmd == "apply":
        cfg = load()
        if valid(cfg) is None:
            apply(cfg)
    elif cmd == "gen":
        generate(load())
    elif cmd == "enabled":
        cfg = load()
        sys.exit(0 if cfg["filter"]["mode"] != "off" and valid(cfg) is None else 1)
    elif cmd == "set" and len(args) == 3:
        cmd_set(args[1], args[2])
    elif cmd == "set-city" and len(args) == 5:
        cmd_set_city(*args[1:])
    elif cmd == "geocode" and len(args) == 2:
        cmd_geocode(args[1])
    elif cmd == "theme" and len(args) >= 2:
        sys.exit(subprocess.run([THEME, *args[1:]], stdout=subprocess.DEVNULL).returncode)
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
