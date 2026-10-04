# Génère la police "BatteryIcons" : icônes de batterie horizontales
# (contour épais arrondi, remplissage arrondi, borne détachée, éclair qui
# perce le contour en charge).
#   U+E000..U+E00A : niveau 0 %, 10 %, ..., 100 %
#   U+E00B         : en charge (sans jauge)
#   U+E00C..U+E016 : en charge avec jauge 0 %, 10 %, ..., 100 %
# Usage : python3 battery-icons-font.py <sortie.otf>
import sys

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.t2CharStringPen import T2CharStringPen
from pathops import LineCap, LineJoin, Path, PathOp, op

# --- Géométrie (unités de police, em = 1000) -------------------------------
# Proportions relevées au pixel sur l'image de référence (hauteur corps = 100) :
# corps 199x100, contour 4.5, espace 4.5, rayon ext. 17, rayon remplissage 15,
# borne 17x32 (rayon 8 côté droit) détachée de 5.
U = 5.6                           # 1 unité de référence -> unités de police
BODY_W, BODY_H = 199 * U, 100 * U # corps de la pile
Y0 = 50                           # bas du corps (au-dessus de la ligne de base)
STROKE = 4.5 * U                  # épaisseur du contour
GAP = 4.5 * U                     # espace contour <-> remplissage
R_OUT = 17 * U                    # rayon des coins extérieurs
R_IN = 15 * U                     # rayon du remplissage
NUB_GAP, NUB_W, NUB_H = 5 * U, 17 * U, 32 * U  # borne (détachée du corps)
R_NUB = 8 * U
SIDE = 40                         # marge gauche/droite
ADVANCE = round(SIDE + BODY_W + NUB_GAP + NUB_W + SIDE)

K = 0.5523  # approximation d'un quart de cercle en Bézier cubique


def round_rect(x0, y0, x1, y1, r, rl=None):
    """Rectangle arrondi (rl = rayon des coins gauches, r par défaut)."""
    p = Path()
    pen = p.getPen()
    r = min(r, (x1 - x0) / 2, (y1 - y0) / 2)
    rl = r if rl is None else min(rl, (x1 - x0) / 2, (y1 - y0) / 2)
    pen.moveTo((x0 + rl, y0))
    pen.lineTo((x1 - r, y0))
    pen.curveTo((x1 - r + K * r, y0), (x1, y0 + r - K * r), (x1, y0 + r))
    pen.lineTo((x1, y1 - r))
    pen.curveTo((x1, y1 - r + K * r), (x1 - r + K * r, y1), (x1 - r, y1))
    pen.lineTo((x0 + rl, y1))
    pen.curveTo((x0 + rl - K * rl, y1), (x0, y1 - rl + K * rl), (x0, y1 - rl))
    pen.lineTo((x0, y0 + rl))
    pen.curveTo((x0, y0 + rl - K * rl), (x0 + rl - K * rl, y0), (x0 + rl, y0))
    pen.closePath()
    return p


def polygon(points):
    p = Path()
    pen = p.getPen()
    pen.moveTo(points[0])
    for pt in points[1:]:
        pen.lineTo(pt)
    pen.closePath()
    return p


def union(*paths):
    out = paths[0]
    for q in paths[1:]:
        out = op(out, q, PathOp.UNION)
    return out


bx0, by0 = SIDE, Y0
bx1, by1 = SIDE + BODY_W, Y0 + BODY_H
cy = (by0 + by1) / 2

outline = op(
    round_rect(bx0, by0, bx1, by1, R_OUT),
    round_rect(bx0 + STROKE, by0 + STROKE, bx1 - STROKE, by1 - STROKE, R_OUT - STROKE),
    PathOp.DIFFERENCE,
)
nx0 = bx1 + NUB_GAP
nub = round_rect(nx0, cy - NUB_H / 2, nx0 + NUB_W, cy + NUB_H / 2, R_NUB, rl=0)
frame = union(outline, nub)

# Zone intérieure disponible pour le remplissage
ix0, iy0 = bx0 + STROKE + GAP, by0 + STROKE + GAP
ix1, iy1 = bx1 - STROKE - GAP, by1 - STROKE - GAP


def level_glyph(frac):
    if frac <= 0:
        return frame
    w = (ix1 - ix0) * frac
    return union(frame, round_rect(ix0, iy0, ix0 + w, iy1, R_IN))


def charging_glyph(frac=0):
    # Éclair relevé sur la référence (unités de référence, origine = coin
    # bas-gauche du corps) : dépasse en haut et en bas du corps
    pts = [(114, 113), (67, 45), (95, 44), (85, -18), (130, 58), (103, 59)]
    bolt_pts = [(bx0 + x * U, by0 + y * U) for x, y in pts]
    bolt = polygon(bolt_pts)
    # Le contour et la jauge sont coupés autour de l'éclair (marge 7.5)
    halo = polygon(bolt_pts)
    halo.stroke(2 * 7.5 * U, LineCap.BUTT_CAP, LineJoin.MITER_JOIN, 4)
    halo = union(halo, bolt)
    return union(op(level_glyph(frac), halo, PathOp.DIFFERENCE), bolt)


glyphs = {f"lvl{i}": level_glyph(i / 10) for i in range(11)}
glyphs["charging"] = charging_glyph()
glyphs.update({f"chg{i}": charging_glyph(i / 10) for i in range(11)})

order = [".notdef"] + list(glyphs)
cmap = {0xE000 + i: f"lvl{i}" for i in range(11)}
cmap[0xE00B] = "charging"
cmap.update({0xE00C + i: f"chg{i}" for i in range(11)})

fb = FontBuilder(1000, isTTF=False)
fb.setupGlyphOrder(order)
fb.setupCharacterMap(cmap)

charstrings = {".notdef": T2CharStringPen(ADVANCE, None).getCharString()}
for name, path in glyphs.items():
    pen = T2CharStringPen(ADVANCE, None)
    path.draw(pen)
    charstrings[name] = pen.getCharString()

fb.setupCFF("BatteryIcons-Regular", {"FullName": "BatteryIcons"}, charstrings, {})
fb.setupHorizontalMetrics({n: (ADVANCE, 0) for n in order})
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({"familyName": "BatteryIcons", "styleName": "Regular"})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
fb.setupPost()
fb.save(sys.argv[1])
