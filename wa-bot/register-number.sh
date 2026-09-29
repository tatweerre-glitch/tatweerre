#!/usr/bin/env bash
# ينقل البوت من الرقم التجريبي للرقم الحقيقي بعد ما يتضاف في WhatsApp Manager ويتأكد بكود الـ SMS.
set -e
ENV=/opt/wa-bot/.env
RAW=${RAW:-https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/main/wa-bot}
[ -f "$ENV" ] || { echo "❌ البوت مش متركب"; exit 1; }
get() { grep -m1 "^$1=" "$ENV" | cut -d= -f2-; }
TOK=$(get WHATSAPP_ACCESS_TOKEN); G=https://graph.facebook.com/v21.0

while true; do
  read -rp "Phone Number ID بتاع الرقم الحقيقي [Enter = 1382569334934160]: " PNID < /dev/tty
  PNID=$(echo "${PNID:-1382569334934160}" | tr -d ' \r')
  [[ "$PNID" =~ ^[0-9]{13,17}$ ]] && break || echo "   ⚠️ ده مش Phone Number ID (رقم طويل 15-16 خانة، مش رقم الموبايل). دوس Enter بس."
done
while true; do
  read -rp "WhatsApp Business Account ID [Enter = 1143578425129739]: " WABA < /dev/tty
  WABA=$(echo "${WABA:-1143578425129739}" | tr -d ' \r')
  [[ "$WABA" =~ ^[0-9]{13,17}$ ]] && break || echo "   ⚠️ دوس Enter بس"
done
echo "==> الرقم ده في ميتا:"
curl -sS "$G/$PNID?fields=display_phone_number,verified_name,name_status,code_verification_status,quality_rating" -H "Authorization: Bearer $TOK"; echo
read -rp "ده الرقم الصح (01043392721)؟ (y/n): " OK < /dev/tty; [ "$OK" = "y" ] || exit 1

STATUS=$(curl -sS "$G/$PNID?fields=code_verification_status" -H "Authorization: Bearer $TOK" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("code_verification_status",""))' 2>/dev/null || true)
if [ "$STATUS" != "VERIFIED" ]; then
  echo "==> الرقم لسه متأكدش"
  read -rp "لو وصلك كود SMS في آخر ١٠ دقايق اكتبه، أو دوس Enter عشان أبعتلك كود جديد: " CODE < /dev/tty
  CODE=$(echo "$CODE" | tr -cd '0-9voice')
  while true; do
    if [ -z "$CODE" ] || [ "$CODE" = "voice" ]; then
      M=SMS; [ "$CODE" = "voice" ] && M=VOICE
      echo "   ببعت كود ($M) على 01043392721..."
      curl -sS -X POST "$G/$PNID/request_code" -H "Authorization: Bearer $TOK" \
        --data-urlencode "code_method=$M" --data-urlencode "language=ar"; echo
      read -rp "اكتب الكود (أو voice لمكالمة): " CODE < /dev/tty
      CODE=$(echo "$CODE" | tr -cd '0-9voice')
      continue
    fi
    V=$(curl -sS -X POST "$G/$PNID/verify_code" -H "Authorization: Bearer $TOK" --data-urlencode "code=$CODE"); echo "$V"
    echo "$V" | grep -q '"success":true' && break
    read -rp "   ⚠️ الكود ماتقبلش — اكتبه تاني، أو دوس Enter لكود جديد: " CODE < /dev/tty
    CODE=$(echo "$CODE" | tr -cd '0-9voice')
  done
  echo "✔ الرقم اتأكد"
fi

while true; do
  read -rsp "اختار PIN من 6 أرقام (Two-step verification — احفظه عندك): " PIN < /dev/tty; echo
  [[ "$PIN" =~ ^[0-9]{6}$ ]] && break || echo "   ⚠️ لازم 6 أرقام"
done
echo "==> تسجيل الرقم في Cloud API"
R=$(curl -sS -X POST "$G/$PNID/register" -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
  -d "{\"messaging_product\":\"whatsapp\",\"pin\":\"$PIN\"}"); echo "$R"
echo "$R" | grep -q '"success":true' || { echo "❌ التسجيل ماتمش — ابعت الرسالة اللي فوق لـ Claude"; exit 1; }

echo "==> ربط الحساب بالبوت"
curl -sS -X POST "$G/$WABA/subscribed_apps" -H "Authorization: Bearer $TOK"; echo

python3 - "$ENV" "$PNID" "$WABA" <<'PY'
import sys
path, pnid, waba = sys.argv[1:]
vals = {"WHATSAPP_PHONE_NUMBER_ID": pnid, "WHATSAPP_WABA_ID": waba}
lines = [l for l in open(path, encoding="utf-8").read().splitlines() if l.split("=", 1)[0] not in vals]
lines += [f"{k}={v}" for k, v in vals.items()]
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
chmod 600 "$ENV"
# لو مكتب تطوير متسجل له رقم في offices.json، نشيله عشان ياخد الرقم الجديد من .env
python3 - <<'PY'
import json, os
p = "/opt/wa-bot/data/offices.json"
if os.path.exists(p):
    d = json.load(open(p, encoding="utf-8"))
    if d.get("tatweer", {}).pop("phone_number_id", None) is not None:
        json.dump(d, open(p, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
PY
echo "==> إعادة تشغيل البوت على الرقم الجديد"
curl -fsSL -o /root/install.sh "$RAW/install.sh" && bash /root/install.sh | tail -4
echo
echo "✅ البوت بقى على الرقم الحقيقي. جرّب: ابعت رسالة واتساب من موبايلك لـ 01043392721"
echo "   مهم: الـ Template لازم يتقدّم تاني على الحساب الحقيقي — شغّل followup-template.sh تاني."
