import math, os, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
def glyph_path(fontfile, cp, box):
    f = TTFont(fontfile); gs = f.getGlyphSet(); g = f.getBestCmap()[cp]
    bp = BoundsPen(gs); gs[g].draw(bp); x0, y0, x1, y1 = bp.bounds
    sc = min(box[2] / (x1 - x0), box[3] / (y1 - y0))
    ox = box[0] + (box[2] - (x1 - x0) * sc) / 2 - x0 * sc
    oy = box[1] + (box[3] - (y1 - y0) * sc) / 2 + y1 * sc
    sp = SVGPathPen(gs); gs[g].draw(TransformPen(sp, (sc, 0, 0, -sc, ox, oy)))
    return sp.getCommands()
out = sys.argv[1]
def svg(body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img">'
            f'<title>{title}</title>{body}</svg>\n')
def rr(x0, y0, x1, y1, r):
    return (f"M{x0+r} {y0} H{x1-r} A{r} {r} 0 0 1 {x1} {y0+r} V{y1-r} A{r} {r} 0 0 1 {x1-r} {y1} "
            f"H{x0+r} A{r} {r} 0 0 1 {x0} {y1-r} V{y0+r} A{r} {r} 0 0 1 {x0+r} {y0} Z")
def dia(cx, cy, h): return f"M{cx} {cy-h} L{cx+h} {cy} L{cx} {cy+h} L{cx-h} {cy} Z"
def ring(cx, cy, R, r):  # annulus, evenodd
    return (f"M{cx-R} {cy} A{R} {R} 0 1 1 {cx+R} {cy} A{R} {R} 0 1 1 {cx-R} {cy} Z "
            f"M{cx-r} {cy} A{r} {r} 0 1 1 {cx+r} {cy} A{r} {r} 0 1 1 {cx-r} {cy} Z")
def arcband(cx, cy, R, r, a0, a1):  # annulus sector, angles in degrees (0 = right, 90 = down)
    p = lambda rad, a: (cx + rad*math.cos(math.radians(a)), cy + rad*math.sin(math.radians(a)))
    large = 1 if (a1 - a0) % 360 > 180 else 0
    (x0, y0), (x1, y1), (x2, y2), (x3, y3) = p(R, a0), p(R, a1), p(r, a1), p(r, a0)
    return (f"M{x0:.2f} {y0:.2f} A{R} {R} 0 {large} 1 {x1:.2f} {y1:.2f} L{x2:.2f} {y2:.2f} "
            f"A{r} {r} 0 {large} 0 {x3:.2f} {y3:.2f} Z")

# ── A · Abstract — "one rasm, two dottings"
# One skeleton (a baseline with a single tooth) carries dots in two places: above (solid) and below (open).
# Same written skeleton, two readings — the exact mechanism of qira'at (e.g. ya/ta on one undotted tooth).
U = 16
A = (f'<path d="{rr(48, 132, 208, 164, 16)}"/>'          # baseline, 160 x 32
     f'<path d="{rr(112, 76, 144, 164, 16)}"/>'          # the tooth, 32 wide
     f'<path d="{dia(108, 44, 14)} {dia(148, 44, 14)}"/>' # dots above: solid
     f'<path fill-rule="evenodd" d="{dia(108, 204, 15)} {dia(108, 204, 5)} {dia(148, 204, 15)} {dia(148, 204, 5)}"/>')  # dots below: open
A = f'<g transform="translate(0 4)">{A}</g>'

# ── B · Geometric mushaf — "the open mushaf is a reading point"
# Two leaves of an open mushaf, cut from one circle by the spine; their inner edges lift apart into a V,
# and the opening holds a single rhombus dot — the point where a reading is chosen.
# Leaves: outer edge straight, top and bottom edges sweep down into the spine (circular arcs, same radius),
# leaving a straight negative-space spine; the rhombus dot rests in the valley the two top edges make.
# The spine opens into a rhombus window (half-diagonal 26, centre y 124): the reading point sits inside the
# mushaf, cut from both leaves, instead of floating above it.
B = ('<path d="M120 92 A150 150 0 0 0 28 60 V188 A150 150 0 0 1 120 220 V142 L102 124 L120 106 Z"/>'
     '<path d="M136 92 A150 150 0 0 1 228 60 V188 A150 150 0 0 0 136 220 V142 L154 124 L136 106 Z"/>')
B = f'<g transform="translate(0 -12)">{B}</g>'

# ── C · Lettermark — "قرأ", the root of al-Qira'at, in a monoline geometric hand (weight 24)
W = 24
qhead = ring(178, 112, 36, 12)                          # initial qaf head, sits on the baseline (y 148)
base = rr(108, 124, 190, 148, 12)                       # connection to ra, baseline band y 124-148
ra = arcband(84, 136, 48, 24, -8, 90)                   # ra: drops below the line and turns left
ra_tip = f"M84 160 H72 A12 12 0 0 0 72 184 H84 Z"
alif = rr(26, 60, 50, 148, 12)                          # alif
# hamza (ء) above the alif: a small open head with a tail, built from an arc band and a bar
hamza = glyph_path("/Volumes/main/projects/quran/assets/fonts/noto_sans_arabic.ttf", 0x621, (22, 20, 34, 30))
qdots = f"{dia(164, 56, 11)} {dia(194, 56, 11)}"
C = (f'<path fill-rule="evenodd" d="{qhead}"/><path d="{base} {ra} {ra_tip}"/>'
     f'<path d="{alif}"/><path d="{hamza}"/><path d="{qdots}"/>')
C = f'<g transform="translate(8 24)">{C}</g>'

for k, body, t in (("a", A, "Concept A — rasm"), ("b", B, "Concept B — mushaf"), ("c", C, "Concept C — qara'a")):
    open(os.path.join(out, f"{k}.svg"), "w").write(svg(body, t))
