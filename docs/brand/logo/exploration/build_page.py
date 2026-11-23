import os, re, html
D = os.path.dirname(os.path.abspath(__file__))
def inline(name):
    s = open(os.path.join(D, name)).read()
    s = re.sub(r'<title>.*?</title>', '', s)
    return re.sub(r'width="256" height="256"', 'width="100%" height="100%"', s)
C = [
 dict(k="a", tag="A · رمز تجريدي", name="رسمٌ واحد، نَقْطٌ متعدد",
  idea="هيكلٌ واحد (خط وسِنّ) تُوضع نقطتاه فوقه مرةً وتحته مرة: الرسم نفسه، والقراءة تختلف.",
  why=["يجسّد آلية القراءات بعينها: الرسم العثماني واحد، والإعجام والضبط يختلفان (مثل «يعلمون/تعلمون»).",
       "لا يرسم مصحفًا ولا هلالًا ولا زخرفة، فلا يشبه أي تطبيق قرآن معروف.",
       "النقاط المصمتة فوق والمفرّغة تحت: قراءة مقروءة وأخرى بديلة، وهو تسلسل بصري واضح."],
  risks=["تجريدي: يحتاج سطرًا يشرحه في المتجر والصفحة الأولى قبل أن يصير مألوفًا.",
         "النقاط المفرّغة تنغلق على 16px، فيلزم قصّ مبسّط بنقاط مصمتة للأحجام الصغيرة.",
         "الشكل ⊥ قد يُقرأ رمزًا رياضيًا لمن لا يعرف العربية."],
  s=[5,4,5,4,4]),
 dict(k="b", tag="B · مصحف هندسي", name="نافذة القراءة",
  idea="مصحف مفتوح من قوسين متماثلين، وكعبه ينفتح على معيّن مفرّغ: موضع القراءة في قلب المصحف.",
  why=["يُفهم فورًا أنه مصحف، حتى لغير الناطقين بالعربية.",
       "الأقوى على 16px: كتلتان كبيرتان وفراغ واحد واضح.",
       "المعيّن (شكل النقطة في الخط العربي) يربطه بالضبط والإعجام."],
  risks=["الأقرب لعُرف الفئة: «الكتاب المفتوح» شائع في تطبيقات القرآن والمكتبات والتعليم.",
         "الفراغ في الكعب قد يُقرأ ثقب مفتاح أو سنّ قلم.",
         "يقول «مصحف» ولا يقول «قراءات»، فلا يميّز التطبيق عن غيره."],
  s=[3,5,3,3,5]),
 dict(k="c", tag="C · حرفي عربي", name="قرأ",
  idea="جذر «القراءات» مكتوبًا بخط هندسي أحادي السُّمك: ق ر أ.",
  why=["الكلمة نفسها هي المعنى: جذر القراءة والقراءات.",
       "عربي أصيل بلا زخرفة جاهزة، ويصلح نواةً لخط مخصص لاسم التطبيق.",
       "سُمك واحد ونهايات مستديرة، فالتماسك الهندسي عالٍ."],
  risks=["الأكثر تفاصيل: الهمزة والنقطتان تختفي على 16px، ويحتاج قصًّا مبسطًا.",
         "يعتمد على القراءة؛ وغير العربي يراه شكلًا مجردًا.",
         "تشكيل الحروف هندسيًا يحتاج مراجعة خطاط لضمان صحة النِّسَب."],
  s=[4,3,5,4,3]),
]
crit = ["التميّز", "البساطة", "الارتباط بالتطبيق", "سهولة التذكّر", "قابلية الاستخدام"]
def sizes(k, bg, fg):
    cells = "".join(f'<div class="sz"><div class="m" style="width:{p}px;height:{p}px;color:{fg}">{inline(k+".svg")}</div><span>{p}</span></div>'
                    for p in (16, 24, 48, 128))
    return f'<div class="row" style="background:{bg}">{cells}</div>'
cards = ""
for c in C:
    total = sum(c["s"])
    bars = "".join(f'<tr><td>{n}</td><td><span class="bar"><i style="width:{v*20}%"></i></span></td><td>{v}/5</td></tr>' for n, v in zip(crit, c["s"]))
    cards += f'''<section class="card{' rec' if c['k']=='a' else ''}">
<div class="tag">{c['tag']}{' · الترشيح' if c['k']=='a' else ''}</div><h2>{c['name']}</h2>
<div class="hero"><div class="m" style="color:#111">{inline(c['k']+'.svg')}</div><div class="m dark" style="color:#fff">{inline(c['k']+'.svg')}</div></div>
<p class="idea">{c['idea']}</p>
{sizes(c['k'], '#ffffff', '#111')}{sizes(c['k'], '#15171a', '#fff')}
<h3>لماذا يعمل</h3><ul>{''.join(f'<li>{x}</li>' for x in c['why'])}</ul>
<h3>نقاط الضعف</h3><ul class="neg">{''.join(f'<li>{x}</li>' for x in c['risks'])}</ul>
<table>{bars}<tr class="t"><td>المجموع</td><td></td><td>{total}/25</td></tr></table></section>'''
page = f'''<!DOCTYPE html><html lang="ar" dir="rtl"><head><meta charset="utf-8"><title>مصحف القراءات · استكشاف الهوية</title>
<style>
body{{margin:0;background:#f4f3ef;font-family:"SF Arabic","Geeza Pro",system-ui,sans-serif;color:#1b1b1b;line-height:1.7}}
main{{max-width:1240px;margin:auto;padding:48px 40px}}
h1{{font-size:34px;margin:0 0 4px}} .sub{{color:#666;margin:0 0 28px}}
.brief{{display:grid;grid-template-columns:1fr 1fr 1fr;gap:16px;margin-bottom:28px}}
.brief div{{background:#fff;border-radius:14px;padding:16px 20px;font-size:14px}} .brief b{{display:block;font-size:15px;margin-bottom:4px}}
.grid{{display:grid;grid-template-columns:repeat(3,1fr);gap:18px}}
.card{{background:#fff;border-radius:18px;padding:22px;border:2px solid transparent}} .card.rec{{border-color:#111}}
.tag{{font-size:12px;letter-spacing:.04em;color:#777}} h2{{margin:2px 0 12px;font-size:24px}}
.hero{{display:grid;grid-template-columns:1fr 1fr;gap:10px}} .hero .m{{aspect-ratio:1;border-radius:12px;background:#f7f7f5;padding:10px}}
.hero .dark{{background:#15171a}} .m svg path{{fill:currentColor}}
.idea{{font-weight:600;font-size:15px}}
.row{{display:flex;align-items:flex-end;gap:16px;padding:12px 14px;border-radius:10px;margin:6px 0;border:1px solid #e5e5e0}}
.sz{{display:flex;flex-direction:column;align-items:center;gap:4px}} .sz span{{font-size:10px;color:#888;direction:ltr}}
h3{{font-size:14px;margin:14px 0 2px}} ul{{margin:0;padding-inline-start:18px;font-size:13.5px}} ul.neg li::marker{{color:#b44}}
table{{width:100%;font-size:13px;margin-top:12px;border-collapse:collapse}} td{{padding:3px 0}} td:first-child{{width:38%}} td:last-child{{text-align:left;direction:ltr;width:40px}}
.bar{{display:block;height:6px;background:#eee;border-radius:3px;margin:0 8px}} .bar i{{display:block;height:6px;background:#111;border-radius:3px}}
tr.t td{{font-weight:700;border-top:1px solid #ddd;padding-top:6px}}
.verdict{{background:#111;color:#fff;border-radius:18px;padding:24px 28px;margin-top:22px}} .verdict h2{{color:#fff}}
</style></head><body><main>
<h1>مصحف القراءات · استكشاف الهوية من الصفر</h1>
<p class="sub">ثلاثة اتجاهات مختلفة جذريًا، بالأسود والأبيض فقط. الألوان تأتي بعد اعتماد الفكرة.</p>
<div class="brief">
<div><b>التطبيق</b>مصحف يعمل دون اتصال: قارئ حفص بتخطيط 604 صفحات، ومقارنة شعبة وقالون، وفرش القراءات العشر في الهامش؛ النقر على الكلمة يعرض كل قراءاتها ومن قرأ بها.</div>
<div><b>الجمهور</b>طلاب علم القراءات والحفّاظ والمعلمون والمجيزون والباحثون. جمهور متخصص يقدّر الدقة والعلمية أكثر من البهرجة. الطابع المطلوب: علمي، دقيق، هادئ، معاصر.</div>
<div><b>ما نتجنّبه في الفئة</b>الهلال، والقبة والمحراب، والمصحف على الرحل، ونجمة الحزب والزخارف الجاهزة، والأخضر مع الذهبي كحل افتراضي، وأشعة النور، وخط الثلث المزخرف للفظ «القرآن».</div>
</div>
<div class="grid">{cards}</div>
<div class="verdict"><h2>الترشيح: A · رسمٌ واحد، نَقْطٌ متعدد</h2>
<p>هو الوحيد الذي يعبّر عن <b>علم القراءات نفسه</b> لا عن «القرآن» بعمومه: الرسم واحد والقراءات تتعدد في النَّقْط والضبط. بهذا يفصل التطبيق عن كل تطبيقات المصاحف، ويبقى بسيطًا بما يكفي لأيقونة.
B هو الأوضح والأأمن، لكنه الأقرب لما تفعله الفئة كلها. C هو الأجمل معنى، لكنه الأضعف على المقاسات الصغيرة ويحتاج خطاطًا ليكتمل.</p>
<p>لو اعتمدت A فالخطوة التالية: قصّ مبسّط لـ16px، ثم ضبط بصري للنِّسَب، ثم اختبار الألوان، ثم الحزمة.</p></div>
</main></body></html>'''
open(os.path.join(D, "index.html"), "w").write(page)
