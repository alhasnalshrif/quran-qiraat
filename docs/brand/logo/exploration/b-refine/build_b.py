"""Concept B refinements. Run: python3 build_b.py <out-dir>"""
import os, sys
out = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.abspath(__file__))
def svg(body, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img">'
            f'<title>{title}</title>{body}</svg>\n')
def dia(cx, cy, h): return f"M{cx} {cy-h} L{cx+h} {cy} L{cx} {cy+h} L{cx-h} {cy} Z"
R = 150                     # one radius for every page edge
TOP, VALLEY, BOT, LOW = 60, 92, 188, 220   # outer-top, spine-top, outer-bottom, spine-bottom
OUT_L, OUT_R = 28, 228
CY = 146                    # optical centre of the leaves (where the rhombus sits)

def leaf_left(x, notch=None):
    d = f"M{x} {VALLEY} A{R} {R} 0 0 0 {OUT_L} {TOP} V{BOT} A{R} {R} 0 0 1 {x} {LOW} "
    if notch:                       # window: (half-height on the spine edge, apex x)
        h, ax = notch
        d += f"V{CY+h} L{ax} {CY} L{x} {CY-h} "
    return d + "Z"
def leaf_right(x, notch=None):
    d = f"M{x} {VALLEY} A{R} {R} 0 0 1 {OUT_R} {TOP} V{BOT} A{R} {R} 0 0 0 {x} {LOW} "
    if notch:
        h, ax = notch
        d += f"V{CY+h} L{ax} {CY} L{x} {CY-h} "
    return d + "Z"

# B0 — the version from the comparison page (rhombus window + slot = keyhole)
B0 = ('<path d="M120 92 A150 150 0 0 0 28 60 V188 A150 150 0 0 1 120 220 V142 L102 124 L120 106 Z"/>'
      '<path d="M136 92 A150 150 0 0 1 228 60 V188 A150 150 0 0 0 136 220 V142 L154 124 L136 106 Z"/>')

# B1 — "the dot held by the mushaf": a solid rhombus (the nuqta that separates one reading from another)
# sits in the spine, with an even 8-unit clearance cut from both leaves. Solid centre = no keyhole.
dot_h = 20; clear = 11.3                       # 8 units perpendicular on a 45° edge
win = dot_h + clear                            # window half-diagonal
B1 = (f'<path d="{leaf_left(120, (win - 8, 128 - win))}"/>'
      f'<path d="{leaf_right(136, (win - 8, 128 + win))}"/>'
      f'<path d="{dia(128, CY, dot_h)}"/>')

# B2 — one body: both leaves joined at the spine; the only opening is the rhombus at the fold.
B2 = ('<path fill-rule="evenodd" d="M128 92 A150 150 0 0 0 28 60 V188 A150 150 0 0 1 128 220 '
      'A150 150 0 0 1 228 188 V60 A150 150 0 0 0 128 92 Z ' + dia(128, CY, 24) + '"/>')

# B3 — B1 plus a second, open rhombus in the valley above: one text, the reading chosen (solid)
# and the alternative (open). Brings back the qira'at idea from concept A.
B3 = B1 + f'<path fill-rule="evenodd" d="{dia(128, 58, 15)} {dia(128, 58, 6)}"/>'

for k, body in (("b0", B0), ("b1", B1), ("b2", B2), ("b3", B3)):
    dy = -12 if k != "b3" else -4
    open(os.path.join(out, f"{k}.svg"), "w").write(svg(f'<g transform="translate(0 {dy})">{body}</g>', f"Concept B {k}"))
