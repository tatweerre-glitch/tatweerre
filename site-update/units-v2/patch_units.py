#!/usr/bin/env python3
"""يركّب قسم الوحدات التفاعلي الجديد ويصلّح بيانات المشاركة والـSEO في index.html.

- كل خطوة بتتأكد إن العلامة اللي بتدوّر عليها موجودة بالعدد المتوقع، ولو لأ مفيش أي حاجة بتتكتب.
- تشغيله أكتر من مرة آمن: القسم بيتبدّل بالنسخة الأحدث، والوسوم مش بتتكرر.

الاستخدام: python3 patch_units.py index.html units-section.html
"""
import json
import re
import sys

SITE = "https://tatweereg.tech"
BASE = "/assets/"

# نفس بيانات الوحدات اللي في القسم — بتتحول لبيانات منظمة لجوجل
LISTINGS = [
    ("MAF-96-R-04", "شقة 96 متر للإيجار — دور أرضي، متجددة حديثًا", "rent", 96, 6000, "maf-96-r-03-poster.jpg"),
    ("77", "شقة 77 متر للبيع — أرضي مرتفع بفيو مفتوح", "sale", 77, 1300000, "apt77-poster.jpg"),
    ("MAF-96-R-01", "شقة 96 متر للإيجار — الدور الأرضي، وسط المدينة", "rent", 96, None, "apt96r-1.jpg"),
    ("MAF-96-S-01", "شقة 96 متر للبيع — الدور الثالث أمام البوابة", "sale", 96, None, "apt96-main.jpg"),
]

HEAD_META = [
    ('property="og:locale"', '<meta property="og:locale" content="ar_EG">'),
    ('property="og:site_name"', '<meta property="og:site_name" content="تطوير العقارية">'),
    ('property="og:image:alt"', '<meta property="og:image:alt" content="إطلالة من بلكونة شقة في مدينة الفردوس — تطوير العقارية">'),
    ('name="twitter:card"', '<meta name="twitter:card" content="summary_large_image">'),
    ('name="twitter:image"', f'<meta name="twitter:image" content="{SITE}/assets/apt96-main.jpg">'),
]


def listings_ld():
    items = []
    for i, (code, name, deal, area, price, img) in enumerate(LISTINGS, 1):
        offer = {
            "@type": "Offer",
            "businessFunction": "http://purl.org/goodrelations/v1#" + ("LeaseOut" if deal == "rent" else "Sell"),
            "priceCurrency": "EGP",
            "availability": "https://schema.org/InStock",
            "url": f"{SITE}/#u-{code}",
        }
        if price:
            offer["price"] = price
            if deal == "rent":
                offer["priceSpecification"] = {"@type": "UnitPriceSpecification", "price": price,
                                               "priceCurrency": "EGP", "unitCode": "MON"}
        items.append({
            "@type": "ListItem",
            "position": i,
            "item": {
                "@type": "Apartment",
                "name": name,
                "identifier": code,
                "url": f"{SITE}/#u-{code}",
                "image": f"{SITE}{BASE}{img}",
                "floorSize": {"@type": "QuantitativeValue", "value": area, "unitCode": "MTK"},
                "numberOfBedrooms": 2,
                "numberOfBathroomsTotal": 1,
                "address": {"@type": "PostalAddress", "addressLocality": "مدينة الفردوس، 6 أكتوبر",
                            "addressRegion": "الجيزة", "addressCountry": "EG"},
                "offers": offer,
            },
        })
    data = {"@context": "https://schema.org", "@type": "ItemList",
            "name": "وحدات متاحة — تطوير العقارية", "itemListElement": items}
    return ('<script type="application/ld+json" id="tu-listings-ld">\n'
            + json.dumps(data, ensure_ascii=False, indent=2) + "\n</script>\n")


def die(msg):
    print("ABORT: " + msg, file=sys.stderr)
    print("index.html ماتغيّرش.", file=sys.stderr)
    sys.exit(2)


def main(index_path, section_path):
    src = open(index_path, encoding="utf-8").read()
    section = open(section_path, encoding="utf-8").read().replace("__BASE__", BASE).strip() + "\n\n"
    out = src

    # 1) استبدال قسم الوحدات بالكامل (من بداية #units لحد بداية #offer)
    a = [m.start() for m in re.finditer(r'<section id="units"', out)]
    b = [m.start() for m in re.finditer(r'<section id="offer"', out)]
    if len(a) != 1 or len(b) != 1 or b[0] < a[0]:
        die(f'لقيت <section id="units"> {len(a)} مرة و <section id="offer"> {len(b)} مرة (المتوقع مرة واحدة لكل واحد وبالترتيب)')
    old = out[a[0]:b[0]]
    if old.count("<section") != 1:
        die("قسم الوحدات فيه أقسام جوه بعض بشكل مش متوقع")
    out = out[:a[0]] + section + out[b[0]:]

    # 2) صور المشاركة وبيانات جوجل كانت بتشاور على /img/ اللي مش موجود
    out = out.replace(f"{SITE}/img/", f"{SITE}/assets/")
    if 'property="og:image"' not in out:
        die("مش لاقي og:image")

    # 3) وسوم مشاركة ناقصة (بتتضاف مرة واحدة بس)
    m = re.search(r'<meta property="og:image"[^>]*>', out)
    add = "".join("\n" + tag for key, tag in HEAD_META if key not in out)
    if add:
        out = out[:m.end()] + add + out[m.end():]

    # 4) بيانات الوحدات لجوجل (بتتبدّل لو موجودة)
    out = re.sub(r'<script type="application/ld\+json" id="tu-listings-ld">.*?</script>\n?', "", out, flags=re.S)
    if out.count("</head>") != 1:
        die("</head> مش موجود مرة واحدة")
    out = out.replace("</head>", listings_ld() + "</head>")

    for must in ('data-tu="v2"', "01286777111", "01043392721", "tu-listings-ld", 'id="offer"', 'id="contact"'):
        if must not in out:
            die("بعد التعديل مش لاقي " + must)

    open(index_path, "w", encoding="utf-8").write(out)
    print(f"index.html: اتعدّل ({len(src)} -> {len(out)} حرف)")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)
    main(sys.argv[1], sys.argv[2])
