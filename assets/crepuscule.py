"""Crépuscule — backend du filtre anti-lumière bleue et du mode sombre.

Le filtre passe par un shader d'écran Hyprland (decoration:screen_shader) : ni gammastep
(protocole gamma) ni hyprsunset (CTM) ne fonctionnent ici, AQ_NO_ATOMIC=1 (home.nix) met
le KMS en mode legacy, sans gamma ni CTM (« No support for gamma on the legacy iface »).

Lancé par le wrapper `crepuscule-ctl` (modules/crepuscule.nix), qui fournit les chemins
des binaires par variables d'environnement. Sous-commandes :

  state                       état complet en JSON (lu par Crepuscule.qml)
  daemon                      boucle du filtre (service crepuscule-filter) : applique le shader voulu
  apply                       recalcule les heures du soleil et prévient le démon
  enabled                     code 0 si le filtre doit tourner (ExecCondition du service)
  set <clé> <valeur>          filter.mode / filter.start / filter.end / filter.offset / filter.temp / filter.brightness
  set-city <nom> <région> <lat> <lon>
  geocode <recherche>         villes correspondantes en JSON (API Open-Meteo)
  theme <mode|hours|dark|light> [...]   délégué à la commande `theme` (theme-automation.nix)
"""

import glob
import json
import math
import os
import signal
import socket
import subprocess
import sys
import threading
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

HOME = os.path.expanduser("~")
CONF_DIR = os.path.join(os.environ.get("XDG_CONFIG_HOME", os.path.join(HOME, ".config")), "crepuscule")
CONF = os.path.join(CONF_DIR, "config.json")
SUN_CONF = os.path.join(CONF_DIR, "sun.conf")    # lu par theme-auto (mode sombre « soleil »)
THEME_CONF = os.path.join(HOME, ".config", "theme-automation", "hours.conf")
SHADER_DIR = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "crepuscule")

SYSTEMCTL = os.environ.get("CREPUSCULE_SYSTEMCTL", "systemctl")
GSETTINGS = os.environ.get("CREPUSCULE_GSETTINGS", "gsettings")
HYPRCTL = os.environ.get("CREPUSCULE_HYPRCTL", "hyprctl")
THEME = os.environ.get("CREPUSCULE_THEME", "theme")
UNIT = "crepuscule-filter.service"

TRANSITION = 30      # minutes de fondu au début et à la fin du filtre
TICK = 20            # secondes entre deux vérifications du démon

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
        return (set_ - int(f["offset"])) % 1440, rise
    return None


def night_factor(cfg, now_min):
    """0 (jour, pas de filtre) → 1 (filtre complet), fondu de TRANSITION min au début et à la fin."""
    mode = cfg["filter"]["mode"]
    if mode == "off":
        return 0.0
    win = filter_window(cfg)
    if win is None:
        return 1.0
    start, end = win
    length = (end - start) % 1440
    d = (now_min - start) % 1440
    if length == 0 or d >= length:
        return 0.0
    ramp = min(TRANSITION, length / 2)
    return max(0.0, min(1.0, d / ramp, (length - d) / ramp))


# --- Shader ------------------------------------------------------------------------------

def kelvin_rgb(k):
    """Couleur d'un corps noir (approximation de Tanner Helland), composantes 0-1."""
    t = k / 100
    r = 255 if t <= 66 else 329.698727446 * (t - 60) ** -0.1332047592
    g = 99.4708025861 * math.log(t) - 161.1195681661 if t <= 66 else 288.1221695283 * (t - 60) ** -0.0755148492
    b = 255 if t >= 66 else (0 if t <= 19 else 138.5177312231 * math.log(t - 10) - 305.0447927307)
    return [max(0.0, min(1.0, c / 255)) for c in (r, g, b)]


def target(cfg, now_min):
    """(température K, luminosité 0-1) voulues maintenant ; (6500, 1.0) = pas de filtre."""
    f = night_factor(cfg, now_min)
    temp = 6500 - (6500 - int(cfg["filter"]["temp"])) * f
    bright = 1 - (1 - int(cfg["filter"]["brightness"]) / 100) * f
    return int(round(temp / 50) * 50), round(bright, 2)


SHADER = """#version 300 es
// Crépuscule : filtre %(temp)d K, luminosité %(bright).2f (généré par crepuscule.py)
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() {
    vec4 c = texture(tex, v_texcoord);
    fragColor = vec4(c.rgb * vec3(%(r).4f, %(g).4f, %(b).4f), c.a);
}
"""


def shader_path(temp, bright):
    """Fichier shader pour ces valeurs (un nom par valeur : Hyprland recompile à chaque changement)."""
    path = os.path.join(SHADER_DIR, "filtre-%d-%d.frag" % (temp, round(bright * 100)))
    if not os.path.exists(path):
        ref = kelvin_rgb(6500)
        rgb = [c / w * bright for c, w in zip(kelvin_rgb(temp), ref)]
        write_if_changed(path, SHADER % {"temp": temp, "bright": bright, "r": rgb[0], "g": rgb[1], "b": rgb[2]})
    return path


def hypr(*args):
    return subprocess.run([HYPRCTL, *args], capture_output=True, text=True).stdout


def current_shader():
    try:
        return json.loads(hypr("getoption", "decoration:screen_shader", "-j")).get("str", "")
    except ValueError:
        return None


def set_shader(path):
    hypr("keyword", "decoration:screen_shader", path or "[[EMPTY]]")


def clear_shader():
    if (current_shader() or "").startswith(SHADER_DIR):
        set_shader("")


def watch_reload():
    """Rechargement de la config Hyprland (rebuild…) = shader effacé : SIGUSR1 pour le reposer."""
    path = os.path.join(os.environ.get("XDG_RUNTIME_DIR", ""), "hypr",
                        os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", ""), ".socket2.sock")
    try:
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.connect(path)
        for line in sock.makefile(encoding="utf-8", errors="replace"):
            if line.startswith("configreloaded>>"):
                os.kill(os.getpid(), signal.SIGUSR1)
    except OSError:
        pass    # sans le socket, le tick de TICK s rattrape


def daemon():
    """Applique le shader voulu toutes les TICK s, ou tout de suite sur SIGUSR1 (réglage
    modifié). Réapplique aussi si un rechargement de la config Hyprland l'a effacé."""
    signal.pthread_sigmask(signal.SIG_BLOCK, {signal.SIGUSR1, signal.SIGTERM, signal.SIGINT})
    threading.Thread(target=watch_reload, daemon=True).start()
    os.makedirs(SHADER_DIR, exist_ok=True)
    while True:
        cfg = load()
        now = datetime.now()
        temp, bright = target(cfg, now.hour * 60 + now.minute + now.second / 60)
        want = "" if temp >= 6500 and bright >= 1 else shader_path(temp, bright)
        cur = current_shader()
        if cur is not None and cur.replace("[[EMPTY]]", "") != want:
            # Ne pas écraser un shader posé par autre chose que Crépuscule
            if want or cur.startswith(SHADER_DIR):
                set_shader(want)
            for old in glob.glob(os.path.join(SHADER_DIR, "filtre-*.frag")):
                if old != want:
                    os.remove(old)
        sig = signal.sigtimedwait({signal.SIGUSR1, signal.SIGTERM, signal.SIGINT}, TICK)
        if sig is not None and sig.si_signo != signal.SIGUSR1:
            clear_shader()
            return


# --- Application des réglages ------------------------------------------------------------

def update_sun(cfg):
    sun = sun_times(cfg["city"]["lat"], cfg["city"]["lon"], date.today())
    if sun is not None:
        write_if_changed(SUN_CONF, "SUNRISE=%s\nSUNSET=%s\n" % (fmt(sun[0]), fmt(sun[1])))


def valid(cfg):
    """Message d'erreur si l'horaire est vide, sinon None."""
    win = filter_window(cfg)
    if win is not None and win[0] == win[1]:
        return "Le début et la fin du filtre sont à la même heure"
    return None


def systemctl(*args):
    return subprocess.run([SYSTEMCTL, "--user", *args], stdout=subprocess.DEVNULL,
                          stderr=subprocess.DEVNULL).returncode


def apply(cfg, start=True):
    """start=False (timer quotidien) : ne démarre pas le filtre s'il ne tourne pas — au boot,
    le timer peut passer avant la session graphique (Hyprland pas encore lancé)."""
    update_sun(cfg)
    if cfg["filter"]["mode"] == "off" or valid(cfg) is not None:
        systemctl("stop", UNIT)
    elif systemctl("is-active", "--quiet", UNIT) == 0:
        systemctl("kill", "--signal=USR1", UNIT)
    elif start:
        systemctl("start", UNIT)
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
    sun = sun_times(cfg["city"]["lat"], cfg["city"]["lon"], date.today())
    win = filter_window(cfg)
    temp, bright = target(cfg, now.hour * 60 + now.minute + now.second / 60)
    out = {
        "city": cfg["city"],
        "filter": cfg["filter"],
        "sun": {"rise": fmt(sun[0]), "set": fmt(sun[1])} if sun else None,
        "window": {"start": fmt(win[0]), "end": fmt(win[1])} if win else None,
        "active": temp < 6500 or bright < 1,
        "now": {"temp": temp, "brightness": round(bright * 100)},
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
    apply(cfg)


def cmd_set_city(name, region, lat, lon):
    cfg = load()
    cfg["city"] = {"name": name, "region": region, "lat": float(lat), "lon": float(lon)}
    save(cfg)
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
    elif cmd == "daemon":
        daemon()
    elif cmd == "apply":
        apply(load(), start=False)
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
