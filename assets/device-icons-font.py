# Génère la police "DeviceIcons" : icônes d'appareils Bluetooth absentes des
# Nerd Fonts, tracées depuis des SVG potrace (couleur = couleur du texte).
#   U+E000 : écouteurs (earbuds.svg, paire d'AirPods au contour)
# Usage : python3 device-icons-font.py <earbuds.svg> <sortie.otf>
import sys
import xml.etree.ElementTree as ET

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.t2CharStringPen import T2CharStringPen
from fontTools.pens.transformPen import TransformPen
from fontTools.svgLib.path import parse_path

ADVANCE_PAD = 40     # marge gauche/droite
Y_BOTTOM = -20       # bas du dessin (sous la ligne de base, comme les icônes md)
HEIGHT = 720         # hauteur du dessin (em = 1000)


def load_svg(path):
    """Tracés potrace bruts : repère y vers le haut (le <g> ne fait que retourner l'axe)."""
    rec = RecordingPen()
    for el in ET.parse(path).iter():
        if el.tag.endswith("path"):
            parse_path(el.attrib["d"], rec)
    return rec


def glyph_from_svg(path):
    rec = load_svg(path)
    bp = BoundsPen(None)
    rec.replay(bp)
    x0, y0, x1, y1 = bp.bounds
    s = HEIGHT / (y1 - y0)
    advance = round((x1 - x0) * s + 2 * ADVANCE_PAD)
    pen = T2CharStringPen(advance, None)
    rec.replay(TransformPen(pen, (s, 0, 0, s, ADVANCE_PAD - x0 * s, Y_BOTTOM - y0 * s)))
    return advance, pen.getCharString()


earbuds_adv, earbuds_cs = glyph_from_svg(sys.argv[1])

order = [".notdef", "earbuds"]
fb = FontBuilder(1000, isTTF=False)
fb.setupGlyphOrder(order)
fb.setupCharacterMap({0xE000: "earbuds"})
fb.setupCFF(
    "DeviceIcons-Regular", {"FullName": "DeviceIcons"},
    {".notdef": T2CharStringPen(600, None).getCharString(), "earbuds": earbuds_cs}, {},
)
fb.setupHorizontalMetrics({".notdef": (600, 0), "earbuds": (earbuds_adv, 0)})
fb.setupHorizontalHeader(ascent=800, descent=-200)
fb.setupNameTable({"familyName": "DeviceIcons", "styleName": "Regular"})
fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, usWinAscent=800, usWinDescent=200)
fb.setupPost()
fb.save(sys.argv[2])
