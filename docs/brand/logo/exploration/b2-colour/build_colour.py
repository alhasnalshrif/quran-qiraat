"""B2 colour study. Run: python3 build_colour.py"""
import os
D = os.path.dirname(os.path.abspath(__file__))
BODY = ('M128 92 A150 150 0 0 0 28 60 V188 A150 150 0 0 1 128 220 '
        'A150 150 0 0 1 228 188 V60 A150 150 0 0 0 128 92 Z')
NUQTA = 'M128 122 L152 146 L128 170 L104 146 Z'
def mark(body, dot, dy=-12):  # body with the rhombus as a real hole, then the coloured nuqta filling it
    dot_el = f'<path fill="{dot}" d="{NUQTA}"/>' if dot else ''
    return (f'<g transform="translate(0 {dy})"><path fill="{body}" fill-rule="evenodd" d="{BODY} {NUQTA}"/>{dot_el}</g>')
def svg(inner, title):
    return (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256" role="img">'
            f'<title>{title}</title>{inner}</svg>\n')
def icon(tile, body, dot):
    return f'<rect width="256" height="256" rx="58" fill="{tile}"/><g transform="translate(128 128) scale(.78) translate(-128 -128)">{mark(body, dot)}</g>'
P = [  # key, name, story, tile, icon-body, icon-dot, light-body, light-dot, dark-bg, dark-body, dark-dot
 ("p1", "حبر ونقطة حمراء", "حبر المصحف البني الداكن، والنقطة بالحُمرة كنقط أبي الأسود في المصاحف الأولى.",
  "#F5EFE3", "#2A2320", "#C2412D", "#2A2320", "#C2412D", "#1C1816", "#F5EFE3", "#E0553E"),
 ("p2", "زمردي ونقطة حمراء", "أخضر أفتح وأحيا من الحالي، والنقطة الحمراء تكسر الصورة النمطية «أخضر وذهبي».",
  "#1F6F5C", "#F7F2E7", "#D9503A", "#1F6F5C", "#C2412D", "#123E34", "#F7F2E7", "#E0553E"),
 ("p3", "حبر أزرق وذهبي", "كحلي عميق يوحي بالعلمية والدقة، مع نقطة ذهبية هادئة.",
  "#1E2B3A", "#F4EFE4", "#D2A84E", "#1E2B3A", "#B88A2E", "#141D27", "#F4EFE4", "#D2A84E"),
 ("p4", "زمردي وذهبي", "الأقرب لثيم التطبيق الحالي بعد تفتيح الأخضر.",
  "#F5EFE3", "#1F6F5C", "#C9A24B", "#1F6F5C", "#C9A24B", "#123E34", "#F5EFE3", "#D6B05A"),
 ("p5", "أحادي فاخر", "أسود دافئ وكريمي فقط؛ النقطة فتحة. أقصى بساطة، والتميز من الشكل وحده.",
  "#151413", "#F5EFE3", None, "#151413", None, "#151413", "#F5EFE3", None),
]
cards = []
for k, name, story, tile, ib, idot, lb, ld, dbg, db, dd in P:
    open(os.path.join(D, f"{k}-icon.svg"), "w").write(svg(icon(tile, ib, idot), name))
    open(os.path.join(D, f"{k}-light.svg"), "w").write(svg(mark(lb, ld), name))
    open(os.path.join(D, f"{k}-dark.svg"), "w").write(svg(mark(db, dd), name))
    sw = "".join(f'<i style="background:{c}" title="{c}"></i><code>{c}</code>' for c in dict.fromkeys(x for x in (tile, ib, idot, lb, ld) if x))
    small = "".join(f'<img src="{k}-icon.svg" width="{s}" height="{s}">' for s in (16, 24, 32, 48))
    cards.append(f'''<section><h2>{name}</h2><p>{story}</p>
<div class="trio"><img class="ic" src="{k}-icon.svg"><div class="lt"><img src="{k}-light.svg"></div><div class="dk" style="background:{dbg}"><img src="{k}-dark.svg"></div></div>
<div class="sm lt">{small}</div><div class="sm dk" style="background:#111">{small}</div><div class="sw">{sw}</div></section>''')
open(os.path.join(D, "index.html"), "w").write(f'''<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>B2 · الألوان</title>
<style>body{{margin:0;background:#efeee9;font-family:"SF Arabic","Geeza Pro",system-ui;color:#1b1b1b}}
main{{max-width:1280px;margin:auto;padding:36px}} h1{{margin:0 0 18px}}
.g{{display:grid;grid-template-columns:repeat(5,1fr);gap:14px}} section{{background:#fff;border-radius:16px;padding:16px}}
h2{{font-size:17px;margin:0}} p{{font-size:12.5px;line-height:1.6;min-height:60px;color:#444}}
.trio{{display:grid;gap:8px}} .trio img{{width:100%;display:block}} .ic{{border-radius:0}}
.lt,.dk{{border-radius:10px;padding:10px}} .lt{{background:#fff;border:1px solid #e6e4de}}
.sm{{display:flex;align-items:flex-end;gap:10px;margin-top:8px;padding:8px 10px}}
.sw{{display:flex;flex-wrap:wrap;align-items:center;gap:4px;margin-top:10px;font-size:10px}} .sw i{{width:14px;height:14px;border-radius:3px;display:inline-block;border:1px solid #0001}}
code{{margin-inline-end:6px;direction:ltr;unicode-bidi:isolate}}
</style></head><body><main><h1>B2 · جسد واحد: دراسة الألوان</h1><div class="g">{"".join(cards)}</div></main></body></html>''')
