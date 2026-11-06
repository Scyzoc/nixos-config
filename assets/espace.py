#!/usr/bin/env python3
# espace — libérer de l'espace disque et ranger des dossiers par extension.
# Interface interactive (curses, bibliothèque standard uniquement).
#
#   espace                                menu interactif
#   espace ranger [DOSSIER] [--ext] [--oui]   rangement non interactif (aperçu sans --oui)
#
# Rien n'est supprimé sans confirmation. Les commandes root (générations Nix,
# ramasse-miettes, journal) sont lancées dans le terminal pour que sudo
# puisse demander le mot de passe.

import curses
import hashlib
import json
import locale
import os
import shutil
import subprocess
import sys
import threading
import time
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from pathlib import Path

os.environ.setdefault("ESCDELAY", "25")

HOME = Path.home()
ETAT = Path(os.environ.get("XDG_STATE_HOME", HOME / ".local/state")) / "espace"
JOURNAL = ETAT / "rangements.json"

# Jamais supprimés par l'outil, quoi que l'utilisateur coche
PROTEGES = [
    HOME / ".ssh",
    HOME / ".gnupg",
    HOME / "Documents/nixos",
    HOME / "Documents/nixos-private",
    HOME / "Documents/Obsidian",
    HOME / "nixos-private.gitcrypt-key",
    Path("/etc/nixos"),
]
# Suppression possible mais avec confirmation renforcée (taper OUI)
SENSIBLES = [HOME / "vmware", HOME / "Documents/Santé", HOME / "Documents/VM-iso"]
EXT_VM = {"vmdk", "vmem", "vmsn", "vmss", "nvram", "vmx", "vdi", "qcow2", "ova", "ovf"}

NOMS_CACHE = {
    "Cache", "Code Cache", "GPUCache", "CachedData", "CachedExtensionVSIXs",
    "DawnGraphiteCache", "DawnWebGPUCache", "GrShaderCache", "ShaderCache",
    "component_crx_cache",
}

CATEGORIES = {
    "Images": "png jpg jpeg gif webp svg bmp tif tiff ico heic avif dng raw xcf psd".split(),
    "Vidéos": "mp4 mkv avi mov webm flv wmv m4v mpg mpeg".split(),
    "Audio": "mp3 flac wav ogg m4a aac opus wma".split(),
    "PDF": ["pdf"],
    "Documents": "doc docx odt rtf txt md pptx ppt odp xls xlsx ods csv epub tex".split(),
    "Archives": "zip rar 7z tar gz xz zst bz2 tgz lz4".split(),
    "Disques et VM": "iso ova ovf vmdk img qcow2 vdi vhd vhdx".split(),
    "Réseau": "pka pkt pcap pcapng ovpn".split(),
    "Certificats": "pem crt cer key p12 pfx gpg asc csr".split(),
    "Code": ("py js mjs ts tsx jsx sh bash nix lua c h cpp rs go java php rb html css "
             "scss sql ipynb").split(),
    "Données": "json yaml yml toml xml ics log ini".split(),
    "Programmes": "deb rpm appimage exe msi apk jar flatpakref".split(),
    "Polices": "ttf otf woff woff2".split(),
}
EXT_VERS_CAT = {e: c for c, exts in CATEGORIES.items() for e in exts}
DOUBLES = ("tar.gz", "tar.xz", "tar.bz2", "tar.zst", "tar.lz4")
PARTIELS = {"part", "crdownload", "download", "tmp", "partial", "aria2"}


# ---------------------------------------------------------------- utilitaires

def taille_h(n):
    if n is None:
        return "?"
    n = float(n)
    for u in ("o", "Ko", "Mo", "Go", "To"):
        if n < 1024 or u == "To":
            if u == "o":
                return f"{int(n)} o"
            return f"{n:.1f} {u}".replace(".", ",")
        n /= 1024


def court(p):
    s = str(p)
    h = str(HOME)
    return "~" + s[len(h):] if s == h or s.startswith(h + "/") else s


def age_h(ts):
    j = int((time.time() - ts) / 86400)
    if j < 1:
        return "aujourd'hui"
    if j < 60:
        return f"{j} j"
    if j < 730:
        return f"{j // 30} mois"
    return f"{j // 365} ans"


def taille_arbre(chemin, liberable=False):
    """Taille disque réelle. liberable=True ignore les fichiers à liens durs
    (leur suppression ne libère rien tant qu'un autre lien existe)."""
    chemin = str(chemin)
    try:
        st = os.lstat(chemin)
    except OSError:
        return 0
    if not os.path.isdir(chemin) or os.path.islink(chemin):
        if liberable and st.st_nlink > 1:
            return 0
        return st.st_blocks * 512
    total, vus, pile = 0, set(), [chemin]
    while pile:
        d = pile.pop()
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        st = e.stat(follow_symlinks=False)
                        est_dir = e.is_dir(follow_symlinks=False)
                    except OSError:
                        continue
                    if est_dir:
                        pile.append(e.path)
                        continue
                    if st.st_nlink > 1:
                        if liberable:
                            continue
                        k = (st.st_dev, st.st_ino)
                        if k in vus:
                            continue
                        vus.add(k)
                    total += st.st_blocks * 512
        except OSError:
            pass
    return total


def sous(p, parent):
    p, parent = os.path.realpath(str(p)), os.path.realpath(str(parent))
    return p == parent or p.startswith(parent + os.sep)


def est_protege(p):
    return any(sous(p, x) for x in PROTEGES) or not sous(p, HOME)


def est_sensible(p):
    if any(sous(p, x) for x in SENSIBLES):
        return True
    return Path(str(p)).suffix.lower().lstrip(".") in EXT_VM


def supprimer(p, vider=False):
    """Supprime un fichier/dossier. vider=True : vide le dossier mais le garde."""
    p = Path(p)
    if est_protege(p):
        raise PermissionError(f"protégé : {court(p)}")
    if p.is_symlink() or p.is_file():
        p.unlink()
    elif p.is_dir():
        if vider:
            for e in os.scandir(p):
                if e.is_dir(follow_symlinks=False):
                    shutil.rmtree(e.path, ignore_errors=True)
                else:
                    try:
                        os.unlink(e.path)
                    except OSError:
                        pass
        else:
            shutil.rmtree(p, ignore_errors=True)


def processus_actif(nom):
    try:
        return subprocess.run(["pgrep", "-x", nom], capture_output=True).returncode == 0
    except OSError:
        return False


# --------------------------------------------------------------------- curses

def init_couleurs():
    curses.start_color()
    try:
        curses.use_default_colors()
        fond = -1
    except curses.error:
        fond = 0
    for i, c in enumerate((curses.COLOR_CYAN, curses.COLOR_GREEN, curses.COLOR_YELLOW,
                           curses.COLOR_RED, curses.COLOR_MAGENTA), start=1):
        curses.init_pair(i, c, fond)


CY = VE = JA = RO = MA = 0


def attrs():
    global CY, VE, JA, RO, MA
    CY, VE, JA, RO, MA = (curses.color_pair(i) for i in range(1, 6))


def put(scr, y, x, texte, attr=0, largeur=None):
    h, w = scr.getmaxyx()
    if y < 0 or y >= h or x >= w - 1:
        return
    n = (w - x - 1) if largeur is None else min(largeur, w - x - 1)
    if n <= 0:
        return
    try:
        scr.addnstr(y, x, texte, n, attr)
    except curses.error:
        pass


def tronque(s, n):
    return s if len(s) <= n else s[: max(n - 1, 0)] + "…"


def attendre(scr, texte, fn):
    """Exécute fn() dans un thread pendant qu'un spinner tourne."""
    res = {}
    etat = {"info": ""}

    def cible():
        try:
            res["v"] = fn(etat)
        except Exception as e:  # noqa: BLE001
            res["e"] = e

    t = threading.Thread(target=cible, daemon=True)
    t.start()
    cadre = "⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
    i = 0
    scr.timeout(100)
    while t.is_alive():
        scr.erase()
        put(scr, 1, 2, f"{cadre[i % len(cadre)]} {texte}", CY | curses.A_BOLD)
        if etat["info"]:
            put(scr, 3, 4, tronque(etat["info"], 90), curses.A_DIM)
        scr.refresh()
        scr.getch()
        i += 1
    scr.timeout(-1)
    if "e" in res:
        raise res["e"]
    return res.get("v")


def confirmer(scr, message, defaut=False):
    h, w = scr.getmaxyx()
    suffixe = " [O/n] " if defaut else " [o/N] "
    put(scr, h - 1, 0, " " * (w - 1))
    put(scr, h - 1, 1, message + suffixe, curses.A_REVERSE | JA)
    scr.refresh()
    while True:
        k = scr.getch()
        if k in (ord("o"), ord("O"), ord("y"), ord("Y")):
            return True
        if k in (ord("n"), ord("N"), 27):
            return False
        if k in (10, 13, curses.KEY_ENTER):
            return defaut


def saisir(scr, question, defaut=""):
    h, w = scr.getmaxyx()
    put(scr, h - 1, 0, " " * (w - 1))
    put(scr, h - 1, 1, f"{question} ", curses.A_REVERSE | JA)
    scr.refresh()
    curses.echo()
    try:
        curses.curs_set(1)
    except curses.error:
        pass
    try:
        brut = scr.getstr(h - 1, len(question) + 3, 60).decode("utf-8", "ignore").strip()
    except curses.error:
        brut = ""
    curses.noecho()
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    return brut or defaut


def message(scr, lignes, titre="", couleur=0):
    scr.erase()
    y = 1
    if titre:
        put(scr, y, 2, titre, CY | curses.A_BOLD)
        y += 2
    for l in lignes:
        put(scr, y, 2, l, couleur)
        y += 1
    put(scr, y + 1, 2, "Appuie sur une touche pour continuer", curses.A_DIM)
    scr.refresh()
    scr.getch()


def en_terminal(scr, commandes):
    """Lance des commandes (éventuellement sudo) dans le vrai terminal."""
    curses.def_prog_mode()
    curses.endwin()
    codes = []
    for cmd in commandes:
        print(f"\n\033[1;36m$ {' '.join(cmd)}\033[0m")
        try:
            codes.append(subprocess.run(cmd).returncode)
        except OSError as e:
            print(f"Erreur : {e}")
            codes.append(127)
    print("\n\033[2mEntrée pour revenir à espace…\033[0m")
    try:
        input()
    except EOFError:
        pass
    curses.reset_prog_mode()
    scr.refresh()
    return codes


def chemin_de(data):
    """Chemin associé à la donnée d'une ligne (Path, (Path, cible) ou dict de nettoyage)."""
    if isinstance(data, tuple):
        data = data[0]
    if isinstance(data, dict):
        ch = data.get("chemins") or []
        data = next((c for c in ch if Path(c).exists()), None)
    return Path(data) if data else None


def ouvrir_dossier(data):
    p = chemin_de(data)
    if p is None:
        return
    cible = p if p.is_dir() and p.parent == HOME else p.parent
    subprocess.Popen(["xdg-open", str(cible)], stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL)


class Liste:
    """Liste à cocher défilante. Lignes : dict(t='tete'|'item', label, taille,
    coche, note, alerte, data, groupe)."""

    def __init__(self, scr, titre, lignes, aide="", extra=None, vide="Rien à afficher."):
        self.scr, self.titre, self.lignes = scr, titre, lignes
        self.aide, self.extra, self.vide = aide, extra or {}, vide
        self.pos = self.haut = 0
        self.pos = self._premier()

    def _premier(self):
        for i, l in enumerate(self.lignes):
            if l["t"] == "item":
                return i
        return 0

    def coches(self):
        return [l for l in self.lignes if l["t"] == "item" and l["coche"]]

    def dessiner(self):
        scr = self.scr
        h, w = scr.getmaxyx()
        scr.erase()
        put(scr, 0, 1, self.titre, CY | curses.A_BOLD)
        put(scr, 1, 1, self.aide, curses.A_DIM)
        corps = h - 5
        if corps < 1:
            return
        if self.pos < self.haut:
            self.haut = self.pos
        if self.pos >= self.haut + corps:
            self.haut = self.pos - corps + 1
        if not self.lignes:
            put(scr, 3, 3, self.vide, curses.A_DIM)
        for r in range(corps):
            i = self.haut + r
            if i >= len(self.lignes):
                break
            l = self.lignes[i]
            y = 3 + r
            sel = i == self.pos
            base = curses.A_REVERSE if sel else 0
            if sel:
                put(scr, y, 0, " " * (w - 1), base)
            if l["t"] == "tete":
                put(scr, y, 1, "▸ " + tronque(l["label"], w - 5), base | CY | curses.A_BOLD)
                continue
            case = "[x]" if l["coche"] else "[ ]"
            put(scr, y, 2, case, base | (VE if l["coche"] else 0))
            put(scr, y, 6, f"{taille_h(l.get('taille')):>10}", base | JA)
            x = 18
            alerte = l.get("alerte", "")
            if alerte:
                put(scr, y, x, alerte, base | RO | curses.A_BOLD)
                x += len(alerte) + 1
            lib = tronque(l["label"], max(w - x - 2, 10))
            put(scr, y, x, lib, base)
            note = l.get("note", "")
            if note and x + len(lib) + 3 < w - 6:
                put(scr, y, x + len(lib) + 2, tronque(note, w - x - len(lib) - 5),
                    base | curses.A_DIM)
        cochees = self.coches()
        total = sum(l.get("taille") or 0 for l in cochees)
        put(scr, h - 2, 0, "─" * (w - 1), curses.A_DIM)
        put(scr, h - 1, 1,
            f"{len(cochees)} coché(s) · {taille_h(total)}  │ espace cocher · a tout · "
            f"n rien · o ouvrir · Entrée valider · q retour",
            curses.A_BOLD)
        scr.refresh()

    def deplacer(self, d):
        i = self.pos + d
        while 0 <= i < len(self.lignes):
            if self.lignes[i]["t"] == "item":
                self.pos = i
                return
            i += d
        if d > 0:
            # fin de liste : rester sur le dernier item
            for j in range(len(self.lignes) - 1, -1, -1):
                if self.lignes[j]["t"] == "item":
                    self.pos = j
                    return

    def basculer(self):
        if not self.lignes:
            return
        l = self.lignes[self.pos]
        if l["t"] == "item":
            l["coche"] = not l["coche"]

    def run(self):
        while True:
            self.dessiner()
            k = self.scr.getch()
            h = self.scr.getmaxyx()[0]
            if k in (ord("q"), 27):
                return None
            elif k in (curses.KEY_UP, ord("k")):
                self.deplacer(-1)
            elif k in (curses.KEY_DOWN, ord("j")):
                self.deplacer(1)
            elif k == curses.KEY_PPAGE:
                self.deplacer(-(h - 6))
            elif k == curses.KEY_NPAGE:
                self.deplacer(h - 6)
            elif k in (curses.KEY_HOME, ord("g")):
                self.pos = self._premier()
            elif k in (curses.KEY_END, ord("G")):
                self.pos = max(len(self.lignes) - 1, 0)
                if self.lignes and self.lignes[self.pos]["t"] != "item":
                    self.deplacer(-1)
            elif k == ord(" "):
                if self.lignes and self.lignes[self.pos]["t"] == "tete":
                    # coche/décoche tout le groupe
                    j = self.pos + 1
                    groupe = []
                    while j < len(self.lignes) and self.lignes[j]["t"] == "item":
                        groupe.append(self.lignes[j])
                        j += 1
                    etat = not all(g["coche"] for g in groupe)
                    for g in groupe:
                        g["coche"] = etat
                else:
                    self.basculer()
                    self.deplacer(1)
            elif k == ord("a"):
                for l in self.lignes:
                    if l["t"] == "item":
                        l["coche"] = True
            elif k == ord("n"):
                for l in self.lignes:
                    if l["t"] == "item":
                        l["coche"] = False
            elif k in (10, 13, curses.KEY_ENTER):
                if self.coches():
                    return self.coches()
            elif k == ord("o") and ord("o") not in self.extra:
                if self.lignes and self.lignes[self.pos]["t"] == "item":
                    ouvrir_dossier(self.lignes[self.pos].get("data"))
            elif k in self.extra:
                if self.extra[k](self, self.lignes[self.pos] if self.lignes else None) == "stop":
                    return None


def menu(scr, titre, entrees, entete=None, pos=0):
    """Menu à choix unique. entrees : [(label, description)]. Renvoie l'index ou None."""
    while True:
        scr.erase()
        h, w = scr.getmaxyx()
        put(scr, 0, 1, titre, CY | curses.A_BOLD)
        y = 2
        if entete:
            y = entete(scr, y)
        for i, (lib, desc) in enumerate(entrees):
            sel = i == pos
            base = curses.A_REVERSE if sel else 0
            if sel:
                put(scr, y + i, 0, " " * (w - 1), base)
            put(scr, y + i, 2, f"{i + 1}", base | JA)
            put(scr, y + i, 5, lib, base | curses.A_BOLD)
            put(scr, y + i, 5 + 34, tronque(desc, max(w - 42, 5)), base | curses.A_DIM)
        put(scr, h - 1, 1, "↑↓ choisir · Entrée ouvrir · q retour", curses.A_DIM)
        scr.refresh()
        k = scr.getch()
        if k in (ord("q"), 27):
            return None
        if k in (curses.KEY_UP, ord("k")):
            pos = (pos - 1) % len(entrees)
        elif k in (curses.KEY_DOWN, ord("j")):
            pos = (pos + 1) % len(entrees)
        elif ord("1") <= k <= ord("9") and k - ord("1") < len(entrees):
            return k - ord("1")
        elif k in (10, 13, curses.KEY_ENTER):
            return pos


def entete_disque(scr, y):
    u = shutil.disk_usage("/")
    pct = u.used / u.total * 100
    couleur = RO if pct >= 90 else JA if pct >= 75 else VE
    larg = 40
    plein = int(larg * u.used / u.total)
    put(scr, y, 2, "Disque /", curses.A_BOLD)
    put(scr, y, 12, "█" * plein, couleur)
    put(scr, y, 12 + plein, "░" * (larg - plein), curses.A_DIM)
    put(scr, y, 14 + larg,
        f"{pct:.0f} %  ·  {taille_h(u.used)} / {taille_h(u.total)}  ·  libre {taille_h(u.free)}",
        couleur | curses.A_BOLD)
    return y + 2


# ------------------------------------------------------------------ nettoyage

def caches_apps():
    res = []

    def rec(d, prof):
        try:
            entrees = list(os.scandir(d))
        except OSError:
            return
        for e in entrees:
            if not e.is_dir(follow_symlinks=False):
                continue
            if e.name in NOMS_CACHE:
                res.append(Path(e.path))
            elif prof > 0:
                rec(e.path, prof - 1)

    rec(str(HOME / ".config"), 3)
    return res


def morceaux_lmstudio():
    res = []
    base = HOME / ".lmstudio/models"
    for racine, _, fichiers in os.walk(base):
        for f in fichiers:
            if f.endswith(".part"):
                res.append(Path(racine) / f)
    return res


def definitions_nettoyage():
    c = HOME / ".cache"
    corbeille = HOME / ".local/share/Trash"
    return [
        dict(id="spotify", grp="sur", label="Cache Spotify",
             note="se retélécharge à l'écoute", chemins=[c / "spotify"], proc="spotify"),
        dict(id="brave", grp="sur", label="Cache Brave",
             note="pages web en cache", chemins=[c / "BraveSoftware"], proc="brave"),
        dict(id="chrome-ia", grp="sur", label="Modèle IA embarqué de Chrome",
             note="OptGuideOnDeviceModel, retéléchargé par Chrome",
             chemins=[HOME / ".config/google-chrome/OptGuideOnDeviceModel"], proc="chrome"),
        dict(id="apps", grp="sur", label="Caches des applis (Discord, VS Code, Obsidian…)",
             note="Cache, Code Cache, GPUCache, VSIX en cache", chemins=caches_apps()),
        dict(id="pnpm-cache", grp="sur", label="Cache pnpm", note="~/.cache/pnpm",
             chemins=[c / "pnpm"]),
        dict(id="npm", grp="sur", label="Cache npm", note="~/.npm/_cacache",
             chemins=[HOME / ".npm/_cacache"]),
        dict(id="nix-cache", grp="sur", label="Cache d'évaluation Nix", note="~/.cache/nix",
             chemins=[c / "nix"]),
        dict(id="petits", grp="sur", label="Vignettes, shaders, Firefox, Epiphany, Stremio",
             note="caches divers",
             chemins=[c / n for n in ("thumbnails", "mesa_shader_cache", "mozilla",
                                      "epiphany", "stremio", "shumate")]),
        dict(id="corbeille", grp="sur", label="Corbeille", note="vidage définitif",
             chemins=[corbeille / "files", corbeille / "info"]),
        dict(id="lms-part", grp="verif", label="Téléchargements LM Studio inachevés (.part)",
             note="perd la progression si un téléchargement est en cours", fichiers=True, chemins=morceaux_lmstudio()),
        dict(id="pnpm-store", grp="verif", label="Store pnpm global",
             note="les node_modules existants restent valides",
             chemins=[HOME / ".local/share/pnpm/store"]),
        dict(id="cliphist", grp="verif", label="Historique du presse-papier",
             note="efface cliphist", chemins=[c / "cliphist"]),
    ]


def estimer_nix(etat):
    """(nb générations système, taille max libérable par le GC)."""
    etat["info"] = "nix-store --gc --print-dead…"
    nb = len(list(Path("/nix/var/nix/profiles").glob("system-*-link")))
    taille = 0
    try:
        sortie = subprocess.run(["nix-store", "--gc", "--print-dead"], capture_output=True,
                                text=True, timeout=120).stdout.split()
        for p in sortie:
            taille += taille_arbre(p)
    except (OSError, subprocess.TimeoutExpired):
        taille = None
    return nb, taille


def taille_journal():
    return taille_arbre("/var/log/journal")


def scanner_nettoyage(etat):
    defs = definitions_nettoyage()

    def calc(d):
        etat["info"] = d["label"]
        d["taille"] = sum(taille_arbre(p, liberable=True) for p in d["chemins"])
        d["ouvert"] = bool(d.get("proc")) and processus_actif(d["proc"])
        return d

    with ThreadPoolExecutor(max_workers=6) as ex:
        defs = list(ex.map(calc, defs))
    return [d for d in defs if d["taille"] > 0], estimer_nix(etat), taille_journal()


def ecran_nettoyage(scr):
    avant = shutil.disk_usage("/").free
    defs, (nb_gens, taille_gc), j = attendre(scr, "Analyse des caches et du store Nix…",
                                              scanner_nettoyage)
    lignes = []

    def item(d, coche):
        note = d["note"] + ("  ⚠ ouvert : ferme-le pour tout libérer" if d.get("ouvert") else "")
        return dict(t="item", label=d["label"], taille=d["taille"], coche=coche, note=note,
                    data=d)

    sur = sorted((d for d in defs if d["grp"] == "sur"), key=lambda d: -d["taille"])
    verif = sorted((d for d in defs if d["grp"] == "verif"), key=lambda d: -d["taille"])
    if sur:
        lignes.append(dict(t="tete", label="Caches régénérables (sans risque)"))
        lignes += [item(d, True) for d in sur]
    if verif:
        lignes.append(dict(t="tete", label="À vérifier (cochés à la main)"))
        lignes += [item(d, False) for d in verif]
    lignes.append(dict(t="tete", label="Système (demande ton mot de passe sudo)"))
    lignes.append(dict(t="item", label=f"Nix : supprimer les anciennes générations ({nb_gens} actuellement)",
                       taille=None, coche=False,
                       note="garde les N dernières, puis lance le ramasse-miettes",
                       data=dict(id="nix-gens")))
    lignes.append(dict(t="item", label="Nix : ramasse-miettes (chemins déjà inutilisés)",
                       taille=taille_gc, coche=True,
                       note="« jusqu'à » : liens durs possibles", data=dict(id="nix-gc")))
    if j > 120 * 1024 * 1024:
        lignes.append(dict(t="item", label="Journal systemd : réduire à 100 Mo",
                           taille=max(j - 100 * 1024 * 1024, 0), coche=False,
                           data=dict(id="journal")))

    sel = Liste(scr, "Nettoyage — caches, corbeille, Nix",
                lignes, "Espace sur une ligne pour cocher, sur un titre pour tout le groupe").run()
    if not sel:
        return
    ids = {l["data"]["id"] for l in sel}
    utilisateur = [l["data"] for l in sel if "chemins" in l["data"]]
    systeme = [i for i in ("nix-gens", "nix-gc", "journal") if i in ids]
    if "nix-gens" in systeme and "nix-gc" not in systeme:
        systeme.insert(1, "nix-gc")
    garder = 3
    if "nix-gens" in systeme:
        try:
            garder = max(1, int(saisir(scr, "Générations système à garder ?", "3")))
        except ValueError:
            garder = 3
    estimation = sum(l.get("taille") or 0 for l in sel)
    if not confirmer(scr, f"Libérer jusqu'à {taille_h(estimation)} ? Suppression définitive."):
        return

    def faire(etat):
        total = 0
        for d in utilisateur:
            etat["info"] = d["label"]
            for p in d["chemins"]:
                try:
                    supprimer(p, vider=Path(p).is_dir())
                except OSError:
                    pass
            total += d["taille"]
        return total

    if utilisateur:
        attendre(scr, "Suppression en cours…", faire)
    cmds = []
    if "nix-gens" in systeme:
        cmds.append(["sudo", "nix-env", "--profile", "/nix/var/nix/profiles/system",
                     "--delete-generations", f"+{garder}"])
        cmds.append(["sudo", "/nix/var/nix/profiles/system/bin/switch-to-configuration", "boot"])
    if "nix-gc" in systeme:
        cmds.append(["sudo", "nix-collect-garbage"])
    if "journal" in systeme:
        cmds.append(["sudo", "journalctl", "--vacuum-size=100M"])
    if cmds:
        en_terminal(scr, cmds)
    gagne = shutil.disk_usage("/").free - avant
    message(scr, [f"Espace libre : {taille_h(avant)} → {taille_h(shutil.disk_usage('/').free)}",
                  f"Gagné : {taille_h(max(gagne, 0))}"], "Nettoyage terminé", VE)


# ------------------------------------------------------------ artefacts de dev

def scanner_dev(etat):
    racines = [HOME / d for d in ("Documents", "Desktop", "Projets", "Downloads")]
    trouves = []
    for racine in racines:
        pile = [str(racine)]
        while pile:
            d = pile.pop()
            etat["info"] = d
            try:
                entrees = list(os.scandir(d))
            except OSError:
                continue
            noms = {e.name for e in entrees}
            for e in entrees:
                try:
                    if not e.is_dir(follow_symlinks=False):
                        continue
                except OSError:
                    continue
                n, p = e.name, e.path
                cible = None
                if n == "node_modules":
                    cible = "node_modules"
                elif n == ".next":
                    cible = ".next"
                elif n == "dist" and "package.json" in noms:
                    cible = "dist"
                elif n == "target" and "Cargo.toml" in noms:
                    cible = "target"
                elif n in (".venv", "venv") and os.path.exists(os.path.join(p, "pyvenv.cfg")):
                    cible = "venv"
                if cible:
                    t = taille_arbre(p)
                    if t >= 5 * 1024 * 1024:
                        trouves.append((t, Path(p), cible, os.stat(p).st_mtime))
                    continue
                if n.startswith(".") or n in ("nixos", "nixos-private", ".git"):
                    continue
                pile.append(p)
    return sorted(trouves, key=lambda x: -x[0])


def ecran_dev(scr):
    trouves = attendre(scr, "Recherche de node_modules, .next, dist, venv…", scanner_dev)
    regen = {"node_modules": "npm/pnpm install", ".next": "se régénère au prochain build",
             "dist": "à rebuild", "target": "cargo build", "venv": "à recréer"}
    lignes = [dict(t="item", label=court(p), taille=t, coche=(c in ("node_modules", ".next")),
                   note=f"{c} · {regen[c]} · modifié il y a {age_h(m)}", data=p)
              for t, p, c, m in trouves]
    sel = Liste(scr, "Artefacts de développement régénérables", lignes,
                "Dossiers reconstructibles : supprime ceux des projets que tu n'ouvres plus",
                vide="Aucun artefact ≥ 5 Mo trouvé.").run()
    if not sel:
        return
    total = sum(l["taille"] for l in sel)
    if not confirmer(scr, f"Supprimer {len(sel)} dossier(s), {taille_h(total)} ?"):
        return
    erreurs = []

    def faire(etat):
        for l in sel:
            etat["info"] = court(l["data"])
            try:
                supprimer(l["data"])
            except OSError as e:
                erreurs.append(str(e))

    attendre(scr, "Suppression en cours…", faire)
    message(scr, [f"{taille_h(total)} libérés ({len(sel) - len(erreurs)} dossier(s))"]
            + erreurs[:5], "Terminé", VE)


# ---------------------------------------------------------------- gros fichiers

SEUILS = [100, 250, 500, 1000, 2000]


def scanner_gros(etat):
    res = []
    dev = os.stat(HOME).st_dev
    pile = [str(HOME)]
    corbeille = str(HOME / ".local/share/Trash")
    while pile:
        d = pile.pop()
        etat["info"] = d
        try:
            with os.scandir(d) as it:
                for e in it:
                    try:
                        if e.is_dir(follow_symlinks=False):
                            if e.path != corbeille and os.stat(e.path).st_dev == dev:
                                pile.append(e.path)
                        elif e.is_file(follow_symlinks=False):
                            st = e.stat(follow_symlinks=False)
                            t = st.st_blocks * 512
                            if t >= 100 * 1024 * 1024 and st.st_nlink == 1:
                                res.append((t, Path(e.path), st.st_mtime))
                    except OSError:
                        continue
        except OSError:
            continue
    return sorted(res, key=lambda x: -x[0])


def etiquette(p):
    s = str(p)
    ext = p.suffix.lower().lstrip(".")
    if est_protege(p):
        return "PROTÉGÉ"
    if "/vmware/" in s or ext in EXT_VM:
        return "VM"
    if "/.lmstudio/models" in s:
        return "IA"
    return ""


def ecran_gros(scr):
    brut = attendre(scr, "Recherche des gros fichiers dans ~ …", scanner_gros)
    etat = {"seuil": 1}  # index dans SEUILS

    def construire():
        mini = SEUILS[etat["seuil"]] * 1024 * 1024
        return [dict(t="item", label=court(p), taille=t, coche=False,
                     alerte=etiquette(p), note=f"modifié il y a {age_h(m)}", data=p)
                for t, p, m in brut if t >= mini]

    def plus(liste, _l):
        etat["seuil"] = min(etat["seuil"] + 1, len(SEUILS) - 1)
        liste.lignes, liste.pos = construire(), 0
        liste.titre = f"Gros fichiers ≥ {SEUILS[etat['seuil']]} Mo"

    def moins(liste, _l):
        etat["seuil"] = max(etat["seuil"] - 1, 0)
        liste.lignes, liste.pos = construire(), 0
        liste.titre = f"Gros fichiers ≥ {SEUILS[etat['seuil']]} Mo"

    liste = Liste(scr, f"Gros fichiers ≥ {SEUILS[etat['seuil']]} Mo", construire(),
                  "+ / - : changer le seuil · VM = machine virtuelle",
                  extra={ord("+"): plus, ord("-"): moins})
    sel = liste.run()
    if not sel:
        return
    interdits = [l for l in sel if est_protege(l["data"])]
    sel = [l for l in sel if l not in interdits]
    if not sel:
        message(scr, ["Tous les fichiers cochés sont protégés."], "Refusé", RO)
        return
    total = sum(l["taille"] for l in sel)
    sensibles = [l for l in sel if est_sensible(l["data"])]
    if sensibles:
        txt = saisir(scr, f"{len(sensibles)} fichier(s) de VM/données sensibles. Tape OUI pour confirmer :")
        if txt != "OUI":
            return
    elif not confirmer(scr, f"Supprimer {len(sel)} fichier(s), {taille_h(total)} ?"):
        return
    erreurs = []
    for l in sel:
        try:
            supprimer(l["data"])
        except OSError as e:
            erreurs.append(str(e))
    message(scr, [f"{taille_h(total)} libérés"] + erreurs[:5], "Terminé", VE)


# --------------------------------------------------------------------- doublons

DOSSIERS_DOUBLONS = ("Documents", "Downloads", "Desktop", "Pictures", "Videos", "Music")
IGNORES = {"node_modules", ".git", ".next", "dist", "nixos", "nixos-private", "Obsidian", "vmware"}


def hash_fichier(chemin, partiel=False):
    h = hashlib.blake2b(digest_size=16)
    try:
        with open(chemin, "rb") as f:
            if partiel:
                h.update(f.read(65536))
            else:
                for bloc in iter(lambda: f.read(1 << 20), b""):
                    h.update(bloc)
    except OSError:
        return None
    return h.hexdigest()


def scanner_doublons(etat):
    par_taille = defaultdict(list)
    for nom in DOSSIERS_DOUBLONS:
        pile = [str(HOME / nom)]
        while pile:
            d = pile.pop()
            etat["info"] = d
            try:
                with os.scandir(d) as it:
                    for e in it:
                        try:
                            if e.is_dir(follow_symlinks=False):
                                if e.name not in IGNORES and not e.name.startswith("."):
                                    pile.append(e.path)
                            elif e.is_file(follow_symlinks=False):
                                st = e.stat(follow_symlinks=False)
                                if st.st_size >= 100 * 1024:
                                    par_taille[st.st_size].append((e.path, st.st_mtime))
                        except OSError:
                            continue
            except OSError:
                continue
    groupes = []
    for taille, fichiers in par_taille.items():
        if len(fichiers) < 2:
            continue
        partiels = defaultdict(list)
        for p, m in fichiers:
            etat["info"] = p
            partiels[hash_fichier(p, True)].append((p, m))
        for lot in partiels.values():
            if len(lot) < 2:
                continue
            complets = defaultdict(list)
            for p, m in lot:
                complets[hash_fichier(p)].append((p, m))
            for g in complets.values():
                if len(g) > 1:
                    groupes.append((taille, g))
    return sorted(groupes, key=lambda x: -(x[0] * (len(x[1]) - 1)))[:150]


def cle_garde(entree):
    chemin, mtime = entree
    nom = os.path.basename(chemin).lower()
    copie = any(m in nom for m in (" (1)", " (2)", " (3)", " copy", " copie", "(1)."))
    return (copie, len(chemin), mtime)


def ecran_doublons(scr):
    groupes = attendre(scr, "Recherche de doublons (Documents, Téléchargements, Images…)",
                       scanner_doublons)
    lignes = []
    for i, (taille, g) in enumerate(groupes):
        g = sorted(g, key=cle_garde)
        lignes.append(dict(t="tete", label=f"{len(g)} copies de {taille_h(taille)} — "
                                             f"gaspillé {taille_h(taille * (len(g) - 1))}"))
        for j, (p, m) in enumerate(g):
            lignes.append(dict(t="item", label=court(p), taille=taille, coche=(j > 0),
                               note="← à garder" if j == 0 else f"modifié il y a {age_h(m)}",
                               data=Path(p), groupe=i))
    sel = Liste(scr, "Doublons exacts (contenu identique)", lignes,
                "La première copie est conservée par défaut. Au moins une copie par groupe doit rester.",
                vide="Aucun doublon ≥ 100 Ko trouvé.").run()
    if not sel:
        return
    coches = defaultdict(int)
    taille_groupe = defaultdict(int)
    for l in lignes:
        if l["t"] == "item":
            taille_groupe[l["groupe"]] += 1
            coches[l["groupe"]] += 1 if l["coche"] else 0
    if any(coches[g] >= taille_groupe[g] for g in coches):
        message(scr, ["Tu as coché toutes les copies d'un même fichier.",
                      "Décoche-en au moins une par groupe."], "Refusé", RO)
        return
    total = sum(l["taille"] for l in sel)
    if not confirmer(scr, f"Supprimer {len(sel)} copie(s), {taille_h(total)} ?"):
        return
    erreurs = []
    for l in sel:
        try:
            supprimer(l["data"])
        except OSError as e:
            erreurs.append(str(e))
    message(scr, [f"{taille_h(total)} libérés"] + erreurs[:5], "Terminé", VE)


# --------------------------------------------------------------------- rangement

def extension(nom):
    bas = nom.lower()
    for d in DOUBLES:
        if bas.endswith("." + d):
            return d
    if "." not in bas.strip("."):
        return ""
    e = bas.rsplit(".", 1)[1]
    return e if e.isalnum() and len(e) <= 8 else ""


def destination(nom, mode):
    e = extension(nom)
    if mode == "ext":
        return e if e else "sans extension"
    return EXT_VERS_CAT.get(e.split(".")[-1] if e else "", "Autres")


def plan_rangement(dossier, mode):
    """Liste de (source, dossier cible) pour les fichiers à la racine de `dossier`."""
    plan, ignores = [], 0
    for e in sorted(os.scandir(dossier), key=lambda e: e.name.lower()):
        try:
            if e.name.startswith(".") or e.is_symlink() or not e.is_file(follow_symlinks=False):
                continue
            if time.time() - e.stat().st_mtime < 120 or extension(e.name) in PARTIELS:
                ignores += 1
                continue
        except OSError:
            continue
        plan.append((Path(e.path), destination(e.name, mode)))
    return plan, ignores


def dest_libre(chemin):
    if not chemin.exists():
        return chemin
    i = 2
    while True:
        cand = chemin.with_name(f"{chemin.stem} ({i}){chemin.suffix}")
        if not cand.exists():
            return cand
        i += 1


def appliquer_rangement(dossier, plan):
    mouvements = []
    for src, cible in plan:
        dossier_cible = Path(dossier) / cible
        dossier_cible.mkdir(exist_ok=True)
        dst = dest_libre(dossier_cible / src.name)
        shutil.move(str(src), str(dst))
        mouvements.append([str(src), str(dst)])
    if mouvements:
        ETAT.mkdir(parents=True, exist_ok=True)
        try:
            histo = json.loads(JOURNAL.read_text())
        except (OSError, ValueError):
            histo = []
        histo.append(dict(date=datetime.now().isoformat(timespec="seconds"),
                          dossier=str(dossier), mouvements=mouvements))
        JOURNAL.write_text(json.dumps(histo[-20:], ensure_ascii=False, indent=1))
    return mouvements


def annuler_rangement():
    try:
        histo = json.loads(JOURNAL.read_text())
    except (OSError, ValueError):
        return None
    if not histo:
        return None
    dernier = histo.pop()
    rendus = 0
    dossiers = set()
    for src, dst in reversed(dernier["mouvements"]):
        if os.path.exists(dst) and not os.path.exists(src):
            shutil.move(dst, src)
            dossiers.add(os.path.dirname(dst))
            rendus += 1
    for d in dossiers:
        try:
            os.rmdir(d)
        except OSError:
            pass
    JOURNAL.write_text(json.dumps(histo, ensure_ascii=False, indent=1))
    return dernier, rendus


def ecran_ranger(scr):
    choix = [("Téléchargements", HOME / "Downloads"), ("Bureau", HOME / "Desktop"),
             ("Documents (racine seulement)", HOME / "Documents"),
             ("Images (racine seulement)", HOME / "Pictures"),
             ("Autre dossier…", None)]
    descs = []
    for lib, p in choix:
        if p and p.is_dir():
            n = sum(1 for e in os.scandir(p) if e.is_file(follow_symlinks=False)
                    and not e.name.startswith("."))
            descs.append(f"{n} fichier(s) à la racine — {court(p)}")
        else:
            descs.append("saisir un chemin")
    i = menu(scr, "Ranger quel dossier ?", [(c[0], d) for c, d in zip(choix, descs)])
    if i is None:
        return
    dossier = choix[i][1]
    if dossier is None:
        txt = saisir(scr, "Chemin du dossier :")
        dossier = Path(os.path.expanduser(txt)) if txt else None
    if not dossier or not dossier.is_dir():
        message(scr, ["Dossier introuvable."], "Erreur", RO)
        return
    m = menu(scr, f"Ranger {court(dossier)} — comment ?",
             [("Par catégorie", "Images/, Vidéos/, PDF/, Archives/, Code/ …"),
              ("Par extension", "png/, pdf/, zip/, tar.gz/ … un dossier par extension")])
    if m is None:
        return
    mode = "cat" if m == 0 else "ext"
    plan, ignores = plan_rangement(dossier, mode)
    if not plan:
        message(scr, ["Aucun fichier à ranger à la racine de ce dossier."], "Rien à faire")
        return
    groupes = defaultdict(list)
    for src, cible in plan:
        groupes[cible].append(src)
    lignes = []
    for cible in sorted(groupes, key=lambda c: -len(groupes[c])):
        fichiers = groupes[cible]
        tot = sum(f.stat().st_size for f in fichiers)
        lignes.append(dict(t="tete", label=f"{cible}/  —  {len(fichiers)} fichier(s), {taille_h(tot)}"))
        for f in fichiers:
            lignes.append(dict(t="item", label=f.name, taille=f.stat().st_size, coche=True,
                               data=(f, cible)))
    sel = Liste(scr, f"Aperçu du rangement de {court(dossier)}", lignes,
                f"Décoche ce que tu veux laisser en place · {ignores} fichier(s) récent(s)/partiel(s) ignorés").run()
    if not sel:
        return
    if not confirmer(scr, f"Déplacer {len(sel)} fichier(s) ? (annulable avec « Annuler le dernier rangement »)", True):
        return
    mouv = appliquer_rangement(dossier, [l["data"] for l in sel])
    message(scr, [f"{len(mouv)} fichier(s) rangés dans {court(dossier)}."], "Rangement terminé", VE)


def ecran_annuler(scr):
    r = annuler_rangement()
    if r is None:
        message(scr, ["Aucun rangement à annuler."], "Annuler")
    else:
        d, n = r
        message(scr, [f"{n} fichier(s) remis en place dans {court(d['dossier'])}",
                      f"(rangement du {d['date']})"], "Rangement annulé", VE)


def ecran_gdu(scr):
    en_terminal(scr, [["gdu", str(HOME)]])


# ------------------------------------------------------------------------ principal

def principal(scr):
    init_couleurs()
    attrs()
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    entrees = [
        ("Nettoyage", "caches, corbeille, Nix (générations + GC), journal"),
        ("Artefacts de dev", "node_modules, .next, dist, venv des projets"),
        ("Gros fichiers", "VM, modèles IA, archives, ISO… à trier un par un"),
        ("Doublons", "fichiers identiques dans Documents, Téléchargements…"),
        ("Ranger un dossier", "classer par catégorie ou par extension"),
        ("Annuler le dernier rangement", "remet les fichiers comme avant"),
        ("Explorer avec gdu", "navigation détaillée dans ~"),
    ]
    actions = [ecran_nettoyage, ecran_dev, ecran_gros, ecran_doublons, ecran_ranger,
               ecran_annuler, ecran_gdu]
    pos = 0
    while True:
        i = menu(scr, "espace — libérer et ranger", entrees, entete_disque, pos)
        if i is None:
            return
        pos = i
        actions[i](scr)


def cli_ranger(args):
    mode = "ext" if "--ext" in args else "cat"
    appliquer = "--oui" in args
    pos = [a for a in args if not a.startswith("--")]
    dossier = Path(os.path.expanduser(pos[0])) if pos else HOME / "Downloads"
    if not dossier.is_dir():
        print(f"Dossier introuvable : {dossier}", file=sys.stderr)
        return 1
    plan, ignores = plan_rangement(dossier, mode)
    groupes = defaultdict(list)
    for src, cible in plan:
        groupes[cible].append(src)
    for cible in sorted(groupes):
        print(f"\033[1;36m{cible}/\033[0m  ({len(groupes[cible])})")
        for f in groupes[cible]:
            print(f"   {f.name}")
    print(f"\n{len(plan)} fichier(s), {ignores} ignoré(s).")
    if not appliquer:
        print("Aperçu seulement. Ajoute --oui pour appliquer.")
        return 0
    n = len(appliquer_rangement(dossier, plan))
    print(f"{n} fichier(s) déplacés. Annulable depuis le menu « espace ».")
    return 0


AIDE = """espace — libérer de l'espace et ranger par extension

  espace                                  menu interactif
  espace ranger [DOSSIER] [--ext] [--oui]  aperçu du rangement (--oui pour appliquer,
                                           --ext pour un dossier par extension)
"""


def main():
    args = sys.argv[1:]
    if args and args[0] in ("-h", "--aide", "--help"):
        print(AIDE)
        return 0
    if args and args[0] == "ranger":
        return cli_ranger(args[1:])
    locale.setlocale(locale.LC_ALL, "")
    if not sys.stdout.isatty():
        print(AIDE)
        return 1
    curses.wrapper(principal)
    return 0


if __name__ == "__main__":
    sys.exit(main())
