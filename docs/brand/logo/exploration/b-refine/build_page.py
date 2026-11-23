import os, re
D = os.path.dirname(os.path.abspath(__file__))
def inline(n):
    s = re.sub(r'<title>.*?</title>', '', open(os.path.join(D, n)).read())
    return s.replace('width="256" height="256"', 'width="100%" height="100%"')
rows = [("b0", "الحالي", "المعيّن المفرّغ مع الشق تحته يُقرأ ثقب مفتاح.", False),
        ("b1", "B1 · النقطة في الكعب", "معيّن مصمت في الكعب بهامش ثابت 8 وحدات: نقطة الإعجام التي تفرّق بين قراءة وأخرى، يحملها المصحف. لا ثقب مفتاح لأن المركز مصمت.", False),
        ("b2", "B2 · جسد واحد", "الصفحتان كتلة واحدة، والفتحة الوحيدة معيّن عند الطيّة. الأبسط والأثبت على 16px، وأكثر فخامة.", True),
        ("b3", "B3 · نقطتان", "معيّن مفرّغ إضافي فوق الكعب (قراءة بديلة). مستبعدة: النقطة الطافية تعيد شكل «شخص يقرأ».", False)]
def strip(k, bg, fg):
    return f'<div class="row" style="background:{bg}">' + "".join(
        f'<div class="sz"><div class="m" style="width:{p}px;height:{p}px;color:{fg}">{inline(k+".svg")}</div><span>{p}</span></div>'
        for p in (16, 24, 48, 128)) + '</div>'
cards = "".join(f'''<section class="card{' rec' if r else ''}"><h2>{t}{' · الترشيح' if r else ''}</h2>
{strip(k, '#fff', '#111')}{strip(k, '#15171a', '#fff')}<p>{d}</p></section>''' for k, t, d, r in rows)
open(os.path.join(D, "index.html"), "w").write(f'''<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="utf-8">
<title>B · تنقيح</title><style>
body{{margin:0;background:#f4f3ef;font-family:"SF Arabic","Geeza Pro",system-ui;color:#1b1b1b}}
main{{max-width:1240px;margin:auto;padding:40px}} h1{{margin:0 0 20px}}
.grid{{display:grid;grid-template-columns:repeat(2,1fr);gap:16px}}
.card{{background:#fff;border-radius:16px;padding:18px;border:2px solid transparent}} .rec{{border-color:#111}}
h2{{font-size:18px;margin:0 0 10px}} p{{font-size:13.5px;line-height:1.7}}
.row{{display:flex;align-items:flex-end;gap:14px;padding:12px;border-radius:10px;margin:6px 0;border:1px solid #e5e5e0}}
.sz{{display:flex;flex-direction:column;align-items:center;gap:4px}} .sz span{{font-size:10px;color:#888}}
.m svg path{{fill:currentColor}}
</style></head><body><main><h1>B · نافذة القراءة: تنقيح بالأسود والأبيض</h1><div class="grid">{cards}</div></main></body></html>''')
