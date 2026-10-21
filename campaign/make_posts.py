#!/usr/bin/env python3
"""يولّد 3 بوستات 1080×1080 لحملة السيولة — كل بوست فيه اللوجو والتليفون والواتساب.
الاستخدام: python3 make_posts.py OUT_DIR IMG_BASE FONT_MODE(local|google) [FONT_DIR]
"""
import sys, os

out, img, mode = sys.argv[1], sys.argv[2].rstrip("/") + "/", sys.argv[3]
fdir = sys.argv[4] if len(sys.argv) > 4 else ""

if mode == "google":
    FONTS = '<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Arabic:wght@400;600;700&display=block" rel="stylesheet">'
else:
    FONTS = "<style>" + "".join(
        f"@font-face{{font-family:'IBM Plex Sans Arabic';font-weight:{w};src:url('file://{fdir}/ibm-plex-sans-arabic-{s}-{w}-normal.woff2') format('woff2')}}"
        for w in (400, 600, 700) for s in ("arabic", "latin")) + "</style>"

BASE_CSS = """
*{box-sizing:border-box;margin:0;padding:0}
html,body{width:1080px;height:1080px;overflow:hidden}
body{font-family:'IBM Plex Sans Arabic',Tahoma,sans-serif;direction:rtl;background:#1f2a44;color:#fff;position:relative}
.ph{position:absolute;inset:0;background-size:cover;background-position:center}
.shade{position:absolute;inset:0;background:linear-gradient(180deg,rgba(15,21,36,.15) 0%,rgba(15,21,36,.45) 36%,rgba(15,21,36,.9) 56%,#162036 100%)}
.top{position:absolute;top:44px;right:48px;left:48px;display:flex;justify-content:space-between;align-items:flex-start}
.logo{background:#fff;border-radius:18px;padding:12px 20px;display:flex}
.logo img{height:74px;width:auto;display:block}
.badge{background:#f5c400;color:#1f2a44;font-weight:700;font-size:34px;padding:10px 26px;border-radius:999px}
.content{position:absolute;right:56px;left:56px;bottom:190px}
.eyebrow{color:#e9dcc2;font-size:28px;font-weight:600;margin-bottom:10px}
h1{font-size:66px;line-height:1.2;font-weight:700;margin-bottom:22px}
h1 em{font-style:normal;color:#f5c400}
.chips{display:flex;flex-wrap:wrap;gap:12px;margin-bottom:24px}
.chips span{border:2px solid rgba(233,220,194,.55);background:rgba(255,255,255,.08);border-radius:999px;padding:6px 20px;font-size:28px;font-weight:600}
.price{display:flex;align-items:baseline;gap:14px}
.price b{font-size:74px;color:#f5c400;font-weight:700;line-height:1}
.price span{font-size:32px;color:#e9dcc2}
.foot{position:absolute;left:0;right:0;bottom:0;height:150px;background:#b08d57;display:flex;align-items:center;justify-content:space-around;padding:0 40px}
.foot div{display:flex;flex-direction:column;align-items:center;line-height:1.25}
.foot small{font-size:26px;color:#1f2a44;font-weight:600}
.foot b{font-size:46px;color:#fff;font-weight:700;direction:ltr;letter-spacing:1px}
.foot i{width:2px;height:84px;background:rgba(31,42,68,.35)}
.list{list-style:none;display:flex;flex-direction:column;gap:14px;margin-bottom:6px}
.list li{font-size:34px;font-weight:600;display:flex;gap:14px;align-items:center}
.list li:before{content:"✓";color:#1f2a44;background:#f5c400;width:46px;height:46px;border-radius:50%;display:grid;place-items:center;font-size:28px;flex:none}
"""

def page(photo, badge, body):
    return f"""<!doctype html><html lang="ar" dir="rtl"><head><meta charset="utf-8">{FONTS}<style>{BASE_CSS}</style></head><body>
<div class="ph" style="background-image:url('{photo}')"></div><div class="shade"></div>
<div class="top"><div class="logo"><img src="{img}logo.png" alt="تطوير العقارية"></div><div class="badge">{badge}</div></div>
<div class="content">{body}</div>
<div class="foot"><div><small>اتصل بينا</small><b>01286777111</b></div><i></i><div><small>واتساب</small><b>01043392721</b></div></div>
</body></html>"""

R04 = os.environ.get("R04_PHOTO", img + "maf-96-r-03-poster.jpg")
posts = {
    "1-إيجار-MAF-96-R-04": page(R04, "للإيجار", """
<div class="eyebrow">إسكان القوات المسلحة · مدينة الفردوس</div>
<h1>شقة 96 م² <em>متجددة حديثًا</em><br>وجاهزة للسكن</h1>
<div class="chips"><span>غرفتين + ريسبشن</span><span>دور أرضي</span><span>أمن وحراسة</span></div>
<div class="price"><b>6,000</b><span>جنيه شهريًا · كود MAF-96-R-04</span></div>"""),
    "2-تشطيب-ورفع-كفاءة": page(img + "apt96-2.jpg", "تشطيب ورفع كفاءة", """
<div class="eyebrow">لملاك شقق مدينة الفردوس</div>
<h1>شطّب شقتك <em>بمقايسة مكتوبة</em><br>قبل ما تدفع جنيه</h1>
<ul class="list"><li>سباكة · كهرباء · محارة · دهانات · أرضيات</li><li>إشراف هندسي وتسليم مطابق للمواصفات</li><li>الدفع على دفعات بإيصال رسمي لكل دفعة</li></ul>"""),
    "3-اعرض-شقتك": page(img + "apt96-main.jpg", "التسويق مجاني", """
<div class="eyebrow">عندك شقة في الفردوس؟</div>
<h1>اعرضها للبيع أو الإيجار<br><em>ونسوّقها لك مجانًا</em></h1>
<ul class="list"><li>رد خلال 24 ساعة من تسجيل الوحدة</li><li>إعلانات على الموقع وصفحاتنا</li><li>عقود نهائية موثّقة من الصندوق</li></ul>"""),
}
os.makedirs(out, exist_ok=True)
for name, html in posts.items():
    open(os.path.join(out, name + ".html"), "w", encoding="utf-8").write(html)
print("\n".join(posts))
