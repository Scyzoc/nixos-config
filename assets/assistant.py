#!/usr/bin/env python3
# Assistant du bureau : une demande en français (« mets Ciao de Werenoi sur Spotify »)
# → Claude (claude -p, Haiku) la traduit en actions JSON → exécutées ici, sur liste blanche.
# Spotify : Claude trouve l'URL open.spotify.com par WebSearch (l'API Spotify exige
# Premium + OAuth depuis 2026), l'oEmbed public vérifie qu'elle existe, puis l'app
# desktop la joue par MPRIS (OpenUri). Minuteurs / chronomètre : IPC vers la barre
# Quickshell (TimerState.qml). Applis : liste des .desktop donnée à Claude, lancée par gtk-launch.
# Binaires passés par variables d'environnement (wrapper modules/assistant.nix).
import configparser
import datetime
import difflib
import glob
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import time
import urllib.parse
import urllib.request

PLAYERCTL = os.environ.get("ASSISTANT_PLAYERCTL", "playerctl")
HYPRCTL = os.environ.get("ASSISTANT_HYPRCTL", "hyprctl")
NOTIFY = os.environ.get("ASSISTANT_NOTIFY", "notify-send")
WPCTL = os.environ.get("ASSISTANT_WPCTL", "wpctl")
GDBUS = os.environ.get("ASSISTANT_GDBUS", "gdbus")
XDG_OPEN = os.environ.get("ASSISTANT_XDG_OPEN", "xdg-open")
QUICKSHELL = os.environ.get("ASSISTANT_QUICKSHELL", "quickshell")
GTK_LAUNCH = os.environ.get("ASSISTANT_GTK_LAUNCH", "gtk-launch")
STATE = os.path.join(os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "assistant")

SCHEMA = {
    "type": "object",
    "properties": {
        "reply": {"type": "string"},
        "actions": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "type": {"type": "string", "enum": ["spotify_play", "media", "volume", "open_url", "open_app",
                                                         "timer", "timer_cancel", "timer_list", "stopwatch"]},
                    "kind": {"type": "string", "enum": ["track", "artist", "album", "playlist"]},
                    "query": {"type": "string"},
                    "url": {"type": "string"},
                    "command": {"type": "string", "enum": ["play", "pause", "toggle", "next", "previous",
                                                            "start", "reset"]},
                    "seconds": {"type": "integer", "minimum": 1, "maximum": 604800},
                    "label": {"type": "string"},
                    "name": {"type": "string"},
                    "level": {"type": "integer", "minimum": 0, "maximum": 150},
                    "delta": {"type": "integer", "minimum": -100, "maximum": 100},
                    "mute": {"type": "boolean"},
                },
                "required": ["type"],
            },
        },
    },
    "required": ["reply", "actions"],
}

SYSTEM = """Tu es l'assistant du bureau Linux (NixOS, Hyprland) de l'utilisateur. Il te parle en français, \
à l'écrit ou à la voix (transcription Whisper : noms d'artistes parfois mal orthographiés, corrige-les).
Traduis sa demande en actions JSON. Actions possibles :
- spotify_play : lancer de la musique sur Spotify. kind = track (un titre), artist, album ou playlist ; \
query = « titre artiste » propre. Fais UNE recherche WebSearch « <query> open.spotify.com » et mets dans url \
l'URL https://open.spotify.com/<kind>/<id> EXACTE lue dans les résultats. N'invente jamais d'identifiant : \
url vide si rien de sûr. Sans titre précis (« mets du Werenoi »), kind = artist.
- media : command = play, pause, toggle, next (suivant), previous (précédent).
- volume : level = volume absolu en %, ou delta = +/- en %, ou mute = true/false.
- open_url : ouvrir un site. Nom de domaine dicté ou tapé (« youtube.com », « youtube point com ») ou site \
connu (« ouvre YouTube ») → url complète https://… (ex. https://youtube.com).
- open_app : ouvrir une application ; name = nom EXACT pris dans cette liste : {apps}. \
Si aucune ne correspond, dis-le dans reply (pas d'action). Un site non listé → open_url.
- timer : lancer un minuteur affiché dans la barre ; seconds = durée totale en secondes ; label = son objet \
s'il est donné (« minuteur de 10 min pour les pâtes » → label « Pâtes »), sinon vide.
- timer_cancel : annuler des minuteurs ; label = mot de leur nom, vide = tous.
- timer_list : temps restant des minuteurs (« il reste combien ? »).
- stopwatch : chronomètre dans la barre ; command = start (lancer / reprendre), pause (arrêter), reset (remettre à zéro).
reply : une phrase courte, naturelle, au tutoiement, qui dit ce que tu fais (ex. « Je lance Ciao de Werenoi. »). \
Pour une simple question sans action, actions = [] et la réponse dans reply. Si la demande est impossible avec \
ces actions, dis-le dans reply. Date et heure : {now}."""


def log(entry):
    os.makedirs(STATE, exist_ok=True)
    with open(os.path.join(STATE, "history.jsonl"), "a") as f:
        f.write(json.dumps(entry, ensure_ascii=False) + "\n")


class Notifier:
    """Une seule bulle, mise à jour à chaque étape (replace-id)."""

    def __init__(self):
        self.id = None

    def __call__(self, body, icon="dialog-information", urgency="normal"):
        cmd = [NOTIFY, "-a", "Assistant", "-i", icon, "-u", urgency, "-p"]
        if self.id:
            cmd += ["-r", self.id]
        try:
            out = subprocess.run(cmd + ["Assistant", body], capture_output=True, text=True, timeout=5).stdout.strip()
            self.id = out or self.id
        except (OSError, subprocess.TimeoutExpired):
            pass


def claude_bin():
    for c in (os.path.expanduser("~/.local/bin/claude"), shutil.which("claude")):
        if c and os.access(c, os.X_OK):
            return c
    raise RuntimeError("claude introuvable")


def apps():
    """Applications visibles du menu : nom (français si dispo) → identifiant .desktop."""
    dirs = [os.path.expanduser("~/.local/share")] + os.environ.get("XDG_DATA_DIRS", "").split(":") + \
        [f"/etc/profiles/per-user/{os.environ.get('USER', '')}/share", "/run/current-system/sw/share"]
    found, seen = {}, set()
    for d in dirs:
        base = os.path.join(d, "applications")
        for f in glob.glob(os.path.join(base, "**", "*.desktop"), recursive=True):
            did = os.path.relpath(f, base).replace("/", "-")
            if did in seen:
                continue
            seen.add(did)
            c = configparser.RawConfigParser(strict=False, interpolation=None)
            try:
                c.read(f, encoding="utf-8")
                e = c["Desktop Entry"]
            except Exception:
                continue
            if e.get("NoDisplay") == "true" or e.get("Hidden") == "true" or e.get("Type", "Application") != "Application":
                continue
            name = (e.get("Name[fr]") or e.get("Name") or "").strip()
            if name:
                found.setdefault(name, did[:-len(".desktop")])
    return found


def ask_claude(request):
    now = datetime.datetime.now().strftime("%A %d %B %Y, %H:%M")
    cmd = [claude_bin(), "-p", "--model", "haiku",
           "--tools", "WebSearch", "--allowedTools", "WebSearch",
           "--no-session-persistence", "--setting-sources", "", "--strict-mcp-config",
           "--output-format", "json", "--json-schema", json.dumps(SCHEMA),
           "--system-prompt", SYSTEM.replace("{now}", now).replace("{apps}", ", ".join(sorted(apps()))), request]
    p = subprocess.run(cmd, capture_output=True, text=True, stdin=subprocess.DEVNULL, timeout=90,
                       cwd=os.path.expanduser("~"))
    try:
        out = json.loads(p.stdout)
    except json.JSONDecodeError:
        raise RuntimeError((p.stderr or p.stdout or "réponse vide").strip().splitlines()[-1][:200])
    if out.get("is_error") or not out.get("structured_output"):
        raise RuntimeError(str(out.get("result") or "réponse invalide")[:200])
    return out["structured_output"]


# --- Actions ----------------------------------------------------------------------------

class Info(str):
    """Résultat à afficher à la place de la réponse de Claude (ex. temps restant)."""


def run(cmd, timeout=10):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout).stdout.strip()
    except (OSError, subprocess.TimeoutExpired):
        return ""


def hypr_exec(cmd):
    # Par Hyprland : l'appli lancée ne dépend pas du processus (ni du service) appelant
    run([HYPRCTL, "dispatch", "exec", cmd])


def spotify_ready(timeout=25):
    if "spotify" in run([PLAYERCTL, "-l"]).split():
        return True
    hypr_exec("spotify")
    end = time.time() + timeout
    while time.time() < end:
        time.sleep(0.5)
        if "spotify" in run([PLAYERCTL, "-l"]).split():
            time.sleep(2)    # MPRIS publié avant que l'appli accepte OpenUri
            return True
    return False


def oembed_title(url):
    try:
        q = "https://open.spotify.com/oembed?url=" + urllib.parse.quote(url, safe="")
        with urllib.request.urlopen(q, timeout=6) as r:
            return json.load(r).get("title") or "?"
    except Exception:
        return None


def spotify_play(a):
    url = (a.get("url") or "").split("?")[0]
    m = re.match(r"^https://open\.spotify\.com/(?:intl-\w+/)?(track|artist|album|playlist)/([A-Za-z0-9]{22})$", url)
    title = oembed_title(f"https://open.spotify.com/{m[1]}/{m[2]}") if m else None
    if not spotify_ready():
        return "Spotify ne démarre pas."
    if not title:
        # Rien de vérifié : on ouvre la recherche dans l'appli plutôt que jouer au hasard
        open_uri("spotify:search:" + urllib.parse.quote(a.get("query") or ""))
        return "Titre exact introuvable, recherche ouverte dans Spotify."
    # Juste après son lancement, Spotify ignore OpenUri quelques secondes : on renvoie
    # jusqu'à ce que le bon titre joue
    uri = f"spotify:{m[1]}:{m[2]}"
    for _ in range(8):
        open_uri(uri)
        time.sleep(1.5)
        if run([PLAYERCTL, "-p", "spotify", "status"]) == "Playing" and \
                (m[1] != "track" or run([PLAYERCTL, "-p", "spotify", "metadata", "mpris:trackid"]).endswith(m[2])):
            return None
    return f"Spotify n'a pas lancé « {title} »."


def open_uri(uri):
    # playerctl open ne transmet pas l'URI à Spotify : appel MPRIS direct
    run([GDBUS, "call", "--session", "--dest", "org.mpris.MediaPlayer2.spotify",
         "--object-path", "/org/mpris/MediaPlayer2", "--method", "org.mpris.MediaPlayer2.Player.OpenUri", uri])


def media(a):
    cmd = {"play": "play", "pause": "pause", "toggle": "play-pause",
           "next": "next", "previous": "previous"}[a.get("command", "toggle")]
    players = run([PLAYERCTL, "-l"]).split()
    target = ["-p", "spotify"] if "spotify" in players else []
    run([PLAYERCTL, *target, cmd])


def volume(a):
    sink = "@DEFAULT_AUDIO_SINK@"
    if "mute" in a:
        run([WPCTL, "set-mute", sink, "1" if a["mute"] else "0"])
    if "level" in a:
        run([WPCTL, "set-mute", sink, "0"])
        run([WPCTL, "set-volume", "-l", "1.5", sink, f"{a['level']}%"])
    elif "delta" in a:
        d = a["delta"]
        run([WPCTL, "set-volume", "-l", "1.5", sink, f"{abs(d)}%{'+' if d >= 0 else '-'}"])


def open_url(a):
    url = (a.get("url") or "").strip()
    if not re.match(r"^https?://", url):
        url = "https://" + url
    if not re.match(r"^https?://[\w.-]+\.[a-z]{2,}(?::\d+)?(/[^\s'\"]*)?$", url, re.I):
        return f"Adresse invalide : {url}"
    hypr_exec(XDG_OPEN + " " + shlex.quote(url))


def norm(s):
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def open_app(a):
    want = norm(a.get("name") or "")
    table = apps()
    by_norm = {norm(n): did for n, did in table.items()}
    did = by_norm.get(want) or next((d for n, d in by_norm.items() if want and want in n), None)
    if not did:
        close = difflib.get_close_matches(want, list(by_norm), n=1, cutoff=0.6)
        did = by_norm[close[0]] if close else None
    if not did:
        return f"Application « {a.get('name')} » introuvable."
    hypr_exec(GTK_LAUNCH + " " + shlex.quote(did))


def bar_ipc(*args):
    # Minuteurs : TimerState.qml dans la barre Quickshell (config « bar »)
    p = subprocess.run([QUICKSHELL, "ipc", "-c", "bar", "call", "timer", *map(str, args)],
                       capture_output=True, text=True, timeout=10)
    if p.returncode != 0:
        raise RuntimeError("barre Quickshell injoignable")
    return p.stdout.strip()


def timer(a):
    if not a.get("seconds"):
        return "Durée du minuteur manquante."
    bar_ipc("add", int(a["seconds"]), a.get("label") or "")


def timer_cancel(a):
    return Info(bar_ipc("cancel", a.get("label") or ""))


def timer_list(a):
    return Info(bar_ipc("list"))


def stopwatch(a):
    cmd = a.get("command") if a.get("command") in ("start", "pause", "reset", "toggle") else "toggle"
    out = bar_ipc("stopwatch", cmd)
    # En pause : le temps écoulé (« Chronomètre en pause à 1:23 ») plutôt que la réponse de Claude
    return Info(out) if cmd == "pause" else None


ACTIONS = {"spotify_play": spotify_play, "media": media, "volume": volume, "open_url": open_url,
           "open_app": open_app, "timer": timer, "timer_cancel": timer_cancel, "timer_list": timer_list,
           "stopwatch": stopwatch}


def main():
    request = " ".join(sys.argv[1:]).strip() or sys.stdin.read().strip()
    if not request:
        return 1
    say = Notifier()
    say("…  " + request, icon="system-search")
    t0 = time.time()
    try:
        plan = ask_claude(request)
    except Exception as e:
        say(f"Erreur : {e}", icon="dialog-error", urgency="critical")
        log({"t": t0, "request": request, "error": str(e)})
        return 1

    reply = plan.get("reply", "").strip()
    errors, infos = [], []
    for a in plan.get("actions", []):
        fn = ACTIONS.get(a.get("type"))
        if not fn:
            continue
        try:
            out = fn(a)
        except Exception as e:
            out = f"Erreur : {e}"
        if isinstance(out, Info):
            infos.append(out)
        elif out:
            errors.append(out)
    # Une action a échoué : « Je lance Ciao… » serait faux, on affiche l'erreur à la place
    say("\n".join(errors) or "\n".join(infos) or reply or "C'est fait.",
        icon="dialog-warning" if errors else "dialog-information")
    log({"t": t0, "s": round(time.time() - t0, 1), "request": request, "plan": plan, "errors": errors})
    return 0


if __name__ == "__main__":
    sys.exit(main())
