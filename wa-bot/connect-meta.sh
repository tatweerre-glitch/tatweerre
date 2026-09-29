#!/usr/bin/env bash
# يربط ميتا بالبوت (Webhook) من السيرفر مباشرة، بالمفاتيح المحفوظة في /opt/wa-bot/.env
set -e
ENV=/opt/wa-bot/.env
[ -f "$ENV" ] || { echo "❌ مفيش $ENV — شغّل install.sh الأول"; exit 1; }
get() { grep -m1 "^$1=" "$ENV" | cut -d= -f2-; }

APP_ID=1556748639103978
WABA_ID=2161026601120075
GRAPH=https://graph.facebook.com/v21.0
URL=https://bot.tatweereg.tech/webhook

echo "==> 1) تسجيل الـ Webhook في التطبيق"
curl -sS -X POST "$GRAPH/$APP_ID/subscriptions" \
  --data-urlencode "object=whatsapp_business_account" \
  --data-urlencode "callback_url=$URL" \
  --data-urlencode "verify_token=$(get WHATSAPP_VERIFY_TOKEN)" \
  --data-urlencode "fields=messages" \
  --data-urlencode "access_token=$APP_ID|$(get META_APP_SECRET)"
echo

echo "==> 2) ربط حساب واتساب بالتطبيق"
curl -sS -X POST "$GRAPH/$WABA_ID/subscribed_apps" \
  -H "Authorization: Bearer $(get WHATSAPP_ACCESS_TOKEN)"
echo

echo "==> 3) التأكد"
curl -sS "$GRAPH/$APP_ID/subscriptions?access_token=$APP_ID|$(get META_APP_SECRET)"
echo
echo "لو شايف {\"success\":true} مرتين فوق، ابعت رسالة واتساب للرقم التجريبي +1 555 161 4203"
