#!/usr/bin/env bash
# تحديث موقع تطوير العقارية (tatweereg.tech)
#  - رقم الاتصال والواتساب 01286777111
#  - أيقونة الموقع (favicon) + بيانات منظمة لجوجل (RealEstateAgent)
#  - صفحة سياسة الخصوصية + صفحة 404 + robots.txt + sitemap.xml
# بياخد نسخة احتياطية الأول، وبيلغي أي تعديل على nginx لو الاختبار فشل.
set -euo pipefail

C=static-sites-tatweer-1
TS=$(date +%Y%m%d-%H%M%S)
WORK=/root/tatweer-site-update-$TS
BACKUP=/root/tatweer-site-backup-$TS

say(){ printf '\n==> %s\n' "$*"; }
die(){ printf '\n!! %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null || die "docker مش موجود — شغّل السكربت على سيرفر Hostinger"
command -v python3 >/dev/null || die "python3 مش موجود على السيرفر"
docker inspect "$C" >/dev/null 2>&1 || die "مش لاقي الحاوية $C"

say "فك ملفات التحديث"
mkdir -p "$WORK"
base64 -d > "$WORK/pkg.tgz" <<'PKG_EOF'
__PAYLOAD__
PKG_EOF
tar -xzf "$WORK/pkg.tgz" -C "$WORK"

say "تحديد مكان ملفات الموقع"
CONF=$(docker exec "$C" sh -c 'ls /etc/nginx/conf.d/*.conf 2>/dev/null | head -1')
[ -n "$CONF" ] || die "مش لاقي ملف إعدادات nginx جوه الحاوية"
ROOT_IN=$(docker exec "$C" sh -c "grep -m1 -E '^[[:space:]]*root[[:space:]]' $CONF" | awk '{print $2}' | tr -d ';' || true)
ROOT_IN=${ROOT_IN:-/usr/share/nginx/html}
docker exec "$C" test -f "$ROOT_IN/index.html" || die "مش لاقي index.html في $ROOT_IN"
HOST_DIR=$(docker inspect "$C" --format "{{range .Mounts}}{{if eq .Destination \"$ROOT_IN\"}}{{.Source}}{{end}}{{end}}")
echo "    nginx conf : $CONF"
echo "    web root   : $ROOT_IN"
echo "    host folder: ${HOST_DIR:-(مفيش — الملفات جوه الحاوية نفسها)}"

say "نسخة احتياطية في $BACKUP"
mkdir -p "$BACKUP"
docker cp "$C:$ROOT_IN/." "$BACKUP/html/"
docker cp "$C:$CONF" "$BACKUP/$(basename "$CONF")"

say "تعديل الصفحة الرئيسية"
cp "$BACKUP/html/index.html" "$WORK/index.html"
python3 "$WORK/patch_index.py" "$WORK/index.html"
cp "$WORK/index.html" "$WORK/files/index.html"

say "رفع الملفات"
if [ -n "$HOST_DIR" ] && [ -d "$HOST_DIR" ]; then
  cp -r "$WORK/files/." "$HOST_DIR/"
  echo "    اتنسخت في $HOST_DIR (دائم)"
else
  docker cp "$WORK/files/." "$C:$ROOT_IN/"
  echo "    اتنسخت جوه الحاوية."
  echo "    تنبيه: لو الحاوية اتعملها re-create التعديل هيضيع؛ ابعتلي ده عشان نخليه دائم."
fi
docker exec "$C" sh -c "chmod -R a+rX $ROOT_IN" || true

say "تفعيل صفحة 404 في nginx"
if docker exec "$C" grep -qE '^[[:space:]]*error_page[[:space:]]+404' "$CONF"; then
  echo "    صفحة 404 متفعّلة بالفعل"
else
  # awk + "cat >" (مش sed -i) عشان يشتغل حتى لو ملف الإعدادات mounted من السيرفر
  docker exec "$C" sh -c "awk '
    /^[[:space:]]*#[[:space:]]*error_page[[:space:]]+404/ && !d { print \"    error_page 404 /404.html;\"; d=1; next }
    { print }
    END { if (!d) exit 3 }' $CONF > /tmp/nginx.new" && rc=0 || rc=$?
  if [ "$rc" = 3 ]; then
    docker exec "$C" sh -c "awk '
      { print }
      /^[[:space:]]*listen[[:space:]]/ && !d { print \"    error_page 404 /404.html;\"; d=1 }' $CONF > /tmp/nginx.new"
  fi
  docker exec "$C" sh -c "cat /tmp/nginx.new > $CONF && rm -f /tmp/nginx.new"
  if docker exec "$C" nginx -t >/dev/null 2>&1; then
    docker exec "$C" nginx -s reload
    echo "    تم"
  else
    docker cp "$BACKUP/$(basename "$CONF")" "$C:$CONF"
    echo "    nginx رفض التعديل، فرجّعت الإعدادات القديمة (الصفحة نفسها اترفعت عادي)"
  fi
fi

say "اختبار"
sleep 2
for p in / /robots.txt /sitemap.xml /privacy.html /img/favicon-32.png /not-found-test; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "https://tatweereg.tech$p" || echo ERR)
  printf '    %-26s %s\n' "$p" "$code"
done
n_new=$(curl -s https://tatweereg.tech/ | grep -o 01286777111 | wc -l)
n_old=$(curl -s https://tatweereg.tech/ | grep -cE '01043392721|01064753335' || true)
echo "    الرقم الجديد ظهر $n_new مرة، والأرقام القديمة: $n_old"

say "معلومة لخطوة www (ابعتها لي)"
docker inspect "$C" --format '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}{{"\n"}}{{end}}' \
  | grep -E 'working_dir|config_files|\.rule=|middlewares' | sed 's/^/    /' || true
curl -s -o /dev/null -w '    www -> %{http_code} %{redirect_url}\n' http://www.tatweereg.tech/ || true

say "خلصنا ✅  (للرجوع للنسخة القديمة: docker cp $BACKUP/html/. $C:$ROOT_IN/)"
