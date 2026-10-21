#!/usr/bin/env bash
# تركيب قسم الوحدات التفاعلي الجديد + إصلاحات SEO لموقع tatweereg.tech
#   1) نسخة احتياطية كاملة من الموقع وإعدادات nginx
#   2) استبدال قسم «وحدات متاحة» بالواجهة الجديدة (فلاتر، صور وفيديو، حجز معاينة، مقارنة، حاسبة)
#   3) تصليح صورة المشاركة (og:image) + وسوم تويتر/واتساب + بيانات الوحدات لجوجل
#   4) sitemap.xml + robots.txt + صفحة 404 حقيقية (بدل ما أي رابط غلط يفتح الرئيسية)
# أي خطوة تفشل بترجّع اللي قبلها، ومفيش حاجة بتتمسح.
set -euo pipefail

BRANCH=${BRANCH:-units-v2}
RAW="https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/$BRANCH/site-update/units-v2"
SITE=https://tatweereg.tech
TS=$(date +%Y%m%d-%H%M%S)
WORK=/root/tatweer-units-$TS
BACKUP=/root/tatweer-site-backup-$TS
C=""          # اسم الحاوية لو الموقع شغال جوه docker

say(){ printf '\n==> %s\n' "$*"; }
die(){ printf '\n!! %s\n' "$*" >&2; exit 1; }
X(){ if [ -n "$C" ]; then docker exec "$C" sh -c "$1"; else sh -c "$1"; fi; }
GET(){ if [ -n "$C" ]; then docker cp "$C:$1" "$2"; else cp -a "$1" "$2"; fi; }
PUT(){ if [ -n "$C" ]; then docker cp "$1" "$C:$2"; else cp "$1" "$2"; fi; }
code(){ curl -s -o /dev/null -w '%{http_code}' --max-time 20 "$SITE$1?tu=$TS" || echo ERR; }

command -v python3 >/dev/null || die "python3 مش موجود على السيرفر"
command -v curl >/dev/null || die "curl مش موجود على السيرفر"

say "تحميل ملفات التحديث"
mkdir -p "$WORK/files"
for f in units-section.html patch_units.py files/404.html files/sitemap.xml; do
  curl -fsSL --max-time 30 "$RAW/$f?$TS" -o "$WORK/$f" || die "مقدرتش أحمّل $f"
done
grep -q 'data-tu="v2"' "$WORK/units-section.html" || die "ملف القسم الجديد ناقص"

say "البحث عن ملفات الموقع"
is_site(){ X "grep -q 'section id=\"units\"' '$1/index.html' 2>/dev/null && grep -q 'تطوير العقارية' '$1/index.html'"; }
roots(){ X "grep -rhoE '^[[:space:]]*root[[:space:]]+[^;]+' /etc/nginx 2>/dev/null | awk '{print \$2}' | sort -u; echo /usr/share/nginx/html"; }
ROOT=""
if command -v docker >/dev/null 2>&1; then
  for c in static-sites-tatweer-1 $(docker ps --format '{{.Names}}'); do
    docker inspect "$c" >/dev/null 2>&1 || continue
    C=$c
    for r in $(roots 2>/dev/null); do if is_site "$r"; then ROOT=$r; break 2; fi; done
    C=""
  done
fi
if [ -z "$ROOT" ]; then
  C=""
  for r in $(roots 2>/dev/null) /var/www/html /var/www/tatweereg.tech; do if is_site "$r"; then ROOT=$r; break; fi; done
fi
[ -n "$ROOT" ] || die "مقدرتش ألاقي ملفات الموقع (index.html فيه قسم الوحدات). ابعتلي ناتج: docker ps"
CONF=$(X "grep -rlE 'root[[:space:]]+$ROOT;' /etc/nginx 2>/dev/null | head -1" || true)
HOST_DIR=""
[ -n "$C" ] && HOST_DIR=$(docker inspect "$C" --format "{{range .Mounts}}{{if eq .Destination \"$ROOT\"}}{{.Source}}{{end}}{{end}}")
echo "    مكان الموقع : ${C:+حاوية $C : }$ROOT"
echo "    إعدادات nginx: ${CONF:-(مش لاقيها — هتخطّى خطوة 404)}"
[ -n "$HOST_DIR" ] && echo "    مربوط بفولدر: $HOST_DIR"

say "نسخة احتياطية في $BACKUP"
mkdir -p "$BACKUP/html"
GET "$ROOT/." "$BACKUP/html/"
[ -n "$CONF" ] && GET "$CONF" "$BACKUP/nginx.conf"
echo "    تم ($(du -sh "$BACKUP" | cut -f1))"

before_root=$(code /); before_priv=$(code /privacy.html); before_logo=$(code /assets/logo.png)
before_crm=$(code /crm/); before_go=$(code /go/); before_api=$(code /api/offer-unit)

say "تعديل الصفحة الرئيسية"
cp "$BACKUP/html/index.html" "$WORK/index.html"
python3 "$WORK/patch_units.py" "$WORK/index.html" "$WORK/units-section.html"

say "رفع الملفات"
DEST=$ROOT; WRITE=PUT
if [ -n "$HOST_DIR" ] && [ -d "$HOST_DIR" ]; then DEST=$HOST_DIR; WRITE=cp; fi
$WRITE "$WORK/index.html" "$DEST/index.html"
$WRITE "$WORK/files/sitemap.xml" "$DEST/sitemap.xml"
$WRITE "$WORK/files/404.html" "$DEST/404.html"
cp "$BACKUP/html/robots.txt" "$WORK/robots.txt" 2>/dev/null || printf 'User-agent: *\nAllow: /\n' > "$WORK/robots.txt"
grep -qi '^sitemap:' "$WORK/robots.txt" || printf '\nSitemap: %s/sitemap.xml\n' "$SITE" >> "$WORK/robots.txt"
$WRITE "$WORK/robots.txt" "$DEST/robots.txt"
X "chmod a+r '$ROOT/index.html' '$ROOT/sitemap.xml' '$ROOT/404.html' '$ROOT/robots.txt'" || true

sleep 2
if ! curl -s --max-time 20 "$SITE/?tu=$TS" | grep -q 'data-tu="v2"'; then
  $WRITE "$BACKUP/html/index.html" "$DEST/index.html"
  die "الصفحة الجديدة مظهرتش على الموقع، فرجّعت القديمة. ابعتلي الناتج ده."
fi
echo "    القسم الجديد ظهر على الموقع ✓"

say "صفحة 404 حقيقية"
if [ -z "$CONF" ]; then
  echo "    اتخطّيت (مفيش ملف إعدادات)"
else
  cp "$BACKUP/nginx.conf" "$WORK/nginx.conf"
  python3 - "$WORK/nginx.conf" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p, encoding="utf-8").read(); o = s
# جوه location / بس: try_files ... /index.html  ->  =404
def fix(m):
    return re.sub(r'(try_files[^;]*?)\s+/index\.html\s*;', r'\1 =404;', m.group(0))
s = re.sub(r'location\s+/\s*\{[^{}]*\}', fix, s)
if not re.search(r'^\s*error_page\s+404\b', s, re.M):
    s = re.sub(r'(^\s*listen\s[^\n]*\n)', r'\1    error_page 404 /404.html;\n', s, count=1, flags=re.M)
open(p, "w", encoding="utf-8").write(s)
print("    تعديلات nginx:", "اتعملت" if s != o else "مفيش حاجة محتاجة تتغير")
PY
  if ! cmp -s "$WORK/nginx.conf" "$BACKUP/nginx.conf"; then
    write_conf(){ if [ -n "$C" ]; then docker exec -i "$C" sh -c "cat > '$CONF'" < "$1"; else cat "$1" > "$CONF"; fi; }
    restore_conf(){ write_conf "$BACKUP/nginx.conf"; X "nginx -s reload" || true; }
    write_conf "$WORK/nginx.conf"
    if X "nginx -t" >/dev/null 2>&1; then
      X "nginx -s reload"; sleep 2
      ok=1
      [ "$(code /)" = "$before_root" ] || ok=0
      [ "$(code /privacy.html)" = "$before_priv" ] || ok=0
      [ "$(code /assets/logo.png)" = "$before_logo" ] || ok=0
      [ "$(code /crm/)" = "$before_crm" ] || ok=0
      [ "$(code /go/)" = "$before_go" ] || ok=0
      [ "$(code /api/offer-unit)" = "$before_api" ] || ok=0
      if [ $ok = 1 ]; then echo "    تم ✓"; else restore_conf; echo "    صفحة تانية اتأثرت، فرجّعت إعدادات nginx زي ما كانت (باقي التحديث شغال)"; fi
    else
      restore_conf; echo "    nginx رفض التعديل، فرجّعت الإعدادات القديمة (باقي التحديث شغال)"
    fi
  fi
fi

say "اختبار نهائي"
for p in / /privacy.html /robots.txt /sitemap.xml /assets/apt96-main.jpg /assets/logo.png /crm/ /go/ /api/offer-unit /tu-test-404; do
  printf '    %-26s %s\n' "$p" "$(code "$p")"
done
curl -s --max-time 20 "$SITE/sitemap.xml?tu=$TS" | grep -q '<urlset' && echo "    sitemap.xml سليم ✓" || echo "    sitemap.xml لسه بيرجع صفحة تانية (ممكن الكاش — جرّب بعد شوية)"
n_phone=$(curl -s "$SITE/?tu=$TS" | grep -o 01286777111 | wc -l)
n_wa=$(curl -s "$SITE/?tu=$TS" | grep -o 01043392721 | wc -l)
echo "    رقم التليفون ظاهر $n_phone مرة، والواتساب $n_wa مرة"

say "خلصنا ✅"
echo "    للرجوع للنسخة القديمة في أي وقت:"
if [ -n "$C" ]; then echo "    docker cp $BACKUP/html/. $C:$ROOT/"; else echo "    cp -a $BACKUP/html/. $ROOT/"; fi
