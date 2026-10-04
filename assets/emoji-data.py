#!/usr/bin/env python3
"""Données du menu d'emojis (modules/quickshell-launcher/EmojiPicker.qml).

Usage : emoji-data.py <emoji-test.txt> <cldr/common> <police emoji> <dossier de sortie> <tailles…>

- emoji-test.txt (Unicode) : liste, ordre et catégories des emojis
- annotations CLDR (fr) : nom et mots-clés en français
- police emoji : on ne garde que les emojis qu'elle dessine en un seul glyphe
  (sinon : carré vide ou séquence éclatée en plusieurs dessins)

Sorties :
- emoji.json : { groups: [nom anglais], cols, emojis: [[emoji, groupe, nom, recherche, teintes, case, cases teintes]] }
  teintes : 5 variantes de couleur de peau (null si absente de la police) ou 0
  case / cases teintes : position dans les planches (-1 si absente)
- atlas-<taille>.png : planches de tous les dessins (emojis et teintes), <cols> par ligne,
  une par taille d'affichage. Le menu affiche des morceaux de ces images au lieu de
  texte : une seule image décodée, pas de rendu de police à chaque emoji (fluidité),
  et réduction Lanczos à la taille exacte (netteté)
- emoji.tsv : « emoji<TAB>nom » pour le menu rofi de secours
"""
import json
import re
import sys
import unicodedata
import xml.etree.ElementTree as ET

import io

import uharfbuzz as hb
from fontTools.ttLib import TTFont
from PIL import Image

test_file, cldr, font_file, out = sys.argv[1:5]
sizes = [int(x) for x in sys.argv[5:]]
COLS = 64

TONES = range(0x1F3FB, 0x1F400)
SKIP_GROUPS = {"Component"}


def key(s):
    """Clé de correspondance : sans sélecteur de variante (FE0F)."""
    return s.replace("\ufe0f", "")


def norm(s):
    s = s.lower().replace("’", "'").replace("œ", "oe").replace("æ", "ae").replace("\u202f", " ")
    s = unicodedata.normalize("NFD", s)
    return "".join(c for c in s if not unicodedata.combining(c))


# --- Police : l'emoji est-il dessiné en un seul glyphe ? ------------------------
with open(font_file, "rb") as f:
    hb_font = hb.Font(hb.Face(f.read()))


# Dessins PNG de la police (table CBDT, plus grande taille disponible)
tt = TTFont(font_file)
strike = max(zip(tt["CBLC"].strikes, tt["CBDT"].strikeData),
             key=lambda s: s[0].bitmapSizeTable.ppemX)[1]


def glyph(s):
    """Identifiant du glyphe, ou None si l'emoji n'est pas dessiné en un seul."""
    if not s:
        return None
    buf = hb.Buffer()
    buf.add_str(s)
    buf.guess_segment_properties()
    hb.shape(hb_font, buf, {})
    gids = [g.codepoint for g in buf.glyph_infos]
    # Glyphe sans dessin (ligature déclarée mais image absente) : invisible
    return gids[0] if len(gids) == 1 and tt.getGlyphName(gids[0]) in strike else None


def bitmap(gid):
    return Image.open(io.BytesIO(strike[tt.getGlyphName(gid)].imageData)).convert("RGBA")


# --- CLDR : noms et mots-clés français -----------------------------------------
names, keywords = {}, {}
for sub in ("annotations", "annotationsDerived"):
    root = ET.parse(f"{cldr}/{sub}/fr.xml").getroot()
    for a in root.iter("annotation"):
        k = key(a.get("cp"))
        if a.get("type") == "tts":
            names.setdefault(k, a.text.strip())
        else:
            keywords.setdefault(k, [w.strip() for w in a.text.split("|")])

# --- emoji-test.txt -------------------------------------------------------------
line_re = re.compile(r"^([0-9A-F ]+?)\s*;\s*fully-qualified\s*#\s*\S+\s+E[\d.]+\s+(.+)$")
groups, entries, by_key = [], [], {}
group = None
with open(test_file, encoding="utf-8") as f:
    for line in f:
        if line.startswith("# group:"):
            group = line.split(":", 1)[1].strip()
            if group not in SKIP_GROUPS:
                groups.append(group)
            continue
        m = line_re.match(line)
        if not m or group in SKIP_GROUPS:
            continue
        seq = "".join(chr(int(cp, 16)) for cp in m.group(1).split())
        en = m.group(2).strip()
        tones = {ord(c) for c in seq if ord(c) in TONES}
        if tones:
            # Variante de peau : rattachée à l'emoji de base si la teinte est unique
            if len(tones) == 1:
                base = by_key.get(key("".join(c for c in seq if ord(c) not in TONES)))
                if base is not None:
                    base["tones"][tones.pop() - 0x1F3FB] = seq
            continue
        e = {"e": seq, "g": len(groups) - 1, "en": en, "tones": [None] * 5}
        entries.append(e)
        by_key[key(seq)] = e

# --- Sortie ---------------------------------------------------------------------
emojis, tsv, cells, dropped = [], [], [], 0


def cell(gid):
    if gid is None:
        return -1
    cells.append(gid)
    return len(cells) - 1


for e in entries:
    gid = glyph(e["e"])
    if gid is None:
        dropped += 1
        continue
    k = key(e["e"])
    fr = names.get(k, e["en"]).replace("\u202f", " ")
    words = [fr] + [w for w in keywords.get(k, []) if w != fr] + [e["en"]]
    tone_gids = [glyph(t) for t in e["tones"]]
    tones = [t if g is not None else None for t, g in zip(e["tones"], tone_gids)]
    has_tones = any(tones)
    emojis.append([e["e"], e["g"], fr, norm(" · ".join(words)),
                   tones if has_tones else 0, cell(gid),
                   [cell(g) for g in tone_gids] if has_tones else 0])
    tsv.append(f"{e['e']}\t{fr}")

# Planches : chaque dessin réduit (Lanczos) et centré dans sa case
rows = (len(cells) + COLS - 1) // COLS
atlases = {n: Image.new("RGBA", (COLS * n, rows * n)) for n in sizes}
for i, gid in enumerate(cells):
    src = bitmap(gid)
    for n, atlas in atlases.items():
        f = n / max(src.size)
        w, h = max(1, round(src.width * f)), max(1, round(src.height * f))
        img = src.resize((w, h), Image.LANCZOS)
        atlas.paste(img, ((i % COLS) * n + (n - w) // 2, (i // COLS) * n + (n - h) // 2))
for n, atlas in atlases.items():
    atlas.save(f"{out}/atlas-{n}.png", optimize=True)

with open(f"{out}/emoji.json", "w", encoding="utf-8") as f:
    json.dump({"groups": groups, "cols": COLS, "emojis": emojis}, f, ensure_ascii=False, separators=(",", ":"))
with open(f"{out}/emoji.tsv", "w", encoding="utf-8") as f:
    f.write("\n".join(tsv) + "\n")

print(f"{len(emojis)} emojis, {len(cells)} dessins ({dropped} absents de la police)", file=sys.stderr)
