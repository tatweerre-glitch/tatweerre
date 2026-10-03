#!/usr/bin/env python3
"""Patch the live Tatweer homepage (index.html) in place.

Every replacement checks that its anchor appears the expected number of times.
If anything doesn't match, nothing is written and the script exits non-zero.
Running it again on an already-patched file is a no-op.
"""
import json
import sys

NEW_DISPLAY = "01286777111"
NEW_INTL = "201286777111"

SCHEMA = {
    "@context": "https://schema.org",
    "@type": "RealEstateAgent",
    "name": "تطوير العقارية",
    "alternateName": "Tatweer Real Estate",
    "url": "https://tatweereg.tech/",
    "logo": "https://tatweereg.tech/img/logo.png",
    "image": "https://tatweereg.tech/img/apt96-main.jpg",
    "description": "بيع وشراء الشقق في إسكان القوات المسلحة بمدينة الفردوس بعقود نهائية موثّقة، وتشطيب ورفع كفاءة الوحدات السكنية بمقايسات واضحة.",
    "telephone": "+" + NEW_INTL,
    "email": "info@tatweereg.tech",
    "address": {
        "@type": "PostalAddress",
        "streetAddress": "504أ مدينة الفردوس للقوات المسلحة، الدور الأرضي، مكتب 2",
        "addressLocality": "مدينة 6 أكتوبر",
        "addressRegion": "الجيزة",
        "addressCountry": "EG",
    },
    "areaServed": "مدينة الفردوس، 6 أكتوبر، الجيزة",
    "sameAs": [
        "https://www.facebook.com/tatweereg.tech/",
        "https://www.instagram.com/adam_moh1234",
        "https://www.tiktok.com/@adamm384",
        "https://www.youtube.com/@tatweerRE",
    ],
}

HEAD_ADD = (
    '<link rel="icon" type="image/png" sizes="32x32" href="img/favicon-32.png">\n'
    '<link rel="apple-touch-icon" href="img/apple-touch-icon.png">'
)

LD = (
    '<script type="application/ld+json">\n'
    + json.dumps(SCHEMA, ensure_ascii=False, indent=2)
    + "\n</script>\n</head>"
)

FOOTER_OLD = ('<span>تطوير العقارية — مدينة الفردوس · اتصال <span dir="ltr">01064753335</span>'
              ' · واتساب <span dir="ltr">01043392721</span></span>')
FOOTER_NEW = ('<span>تطوير العقارية — مدينة الفردوس · اتصال وواتساب <span dir="ltr">'
              + NEW_DISPLAY + '</span> · <a href="privacy.html">سياسة الخصوصية</a></span>')

BTN_OLD = '<button class="btn btn-wa" type="submit">ابعت على واتساب</button>'
BTN_NEW = (BTN_OLD + '\n        <p style="font-size:13px;color:var(--muted)">بياناتك بتتبعت لينا على واتساب بس. '
           'اعرف أكتر في <a href="privacy.html">سياسة الخصوصية</a>.</p>')

# (anchor, replacement, expected count). Order matters: the footer line is
# replaced before the bare phone numbers it contains.
STEPS = [
    ('<link rel="icon" href="img/logo.png">', HEAD_ADD, 1),
    ("</head>", LD, 1),
    (FOOTER_OLD, FOOTER_NEW, 1),
    (BTN_OLD, BTN_NEW, 1),
    ("01043392721", NEW_DISPLAY, 7),   # 5 wa.me links + JS PHONE + contact card
    ("01064753335", NEW_DISPLAY, 3),   # 2 tel: links + contact card
]


def main(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()

    if "application/ld+json" in src and "favicon-32.png" in src:
        print("index.html: already patched, nothing to do")
        return 0

    out = src
    for old, new, want in STEPS:
        got = out.count(old)
        if got != want:
            print(f"ABORT: expected {want}x but found {got}x of: {old[:60]!r}", file=sys.stderr)
            print("index.html was NOT changed.", file=sys.stderr)
            return 2
        out = out.replace(old, new)

    for leftover in ("01043392721", "01064753335"):
        if leftover in out:
            print(f"ABORT: old number {leftover} still present", file=sys.stderr)
            return 2

    with open(path, "w", encoding="utf-8") as f:
        f.write(out)
    print(f"index.html: patched ({len(src)} -> {len(out)} chars)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
