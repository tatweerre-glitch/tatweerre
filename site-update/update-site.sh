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
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
AHgAAA==
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
