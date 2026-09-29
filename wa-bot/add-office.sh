#!/usr/bin/env bash
# يضيف مكتب جديد للبوت (أو يعدّل مكتب موجود): رقم الواتساب بتاعه، باسورد اللوحة، وجروب تليجرام للتنبيهات.
# شغّله من PowerShell:  ssh -t root@186.241.26.230 "curl -fsSL -o a.sh <رابط السكريبت> && bash a.sh"
set -e
ENV=/opt/wa-bot/.env
OFF=/opt/wa-bot/data/offices.json
[ -f "$ENV" ] || { echo "❌ البوت مش متركب"; exit 1; }
get() { grep -m1 "^$1=" "$ENV" | cut -d= -f2-; }
ask() { local v; read -rp "$1: " v < /dev/tty; printf %s "$v" | tr -d '\r'; }
asks() { local v; read -rsp "$1: " v < /dev/tty; echo > /dev/tty; printf %s "$v" | tr -d '\r\n\t '; }

echo "==> مكتب جديد — اكتب البيانات ودوس Enter بعد كل واحدة"
while true; do
  CODE=$(ask "كود المكتب بالإنجليزي الصغير (ده اسم المستخدم في اللوحة، مثال: elnour)" | tr 'A-Z' 'a-z' | tr -d ' ')
  [[ "$CODE" =~ ^[a-z0-9][a-z0-9-]{1,30}$ ]] && break || echo "   ⚠️ حروف إنجليزي صغيرة وأرقام بس"
done
NAME=$(ask "اسم الشركة (زي ما البوت هيقوله للعميل)")
PHONE=$(ask "رقم الشركة اللي البوت يديه للعملاء (مثال: 01012345678)" | tr -d ' -')
AREA=$(ask "المناطق/المشاريع اللي المكتب شغال فيها (سطر واحد، تقدر تعدله بعدين من اللوحة)")
PNID=$(ask "Phone Number ID بتاع رقم واتساب المكتب (من ميتا)" | tr -d ' ')
WABA=$(ask "WhatsApp Business Account ID بتاع المكتب (من ميتا)" | tr -d ' ')
echo "   التوكن: لو رقم المكتب جوه حساب البيزنس بتاعك في ميتا، دوس Enter وخلاص (هيستخدم التوكن الأساسي)."
TOKEN=$(asks "Access Token خاص بالمكتب (اختياري)")
while true; do
  P1=$(asks "باسورد لوحة المكتب (8 حروف أو أكتر)"); P2=$(asks "اكتبه تاني")
  [ "$P1" = "$P2" ] && [ ${#P1} -ge 8 ] && break || echo "   ⚠️ مش زي بعض أو أقل من 8"
done

TG=$(get TELEGRAM_BOT_TOKEN); CHAT=""
if [ -n "$TG" ]; then
  BOTNAME=$(curl -s "https://api.telegram.org/bot$TG/getMe" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["username"])' 2>/dev/null || true)
  echo "==> تنبيهات تليجرام: خلّي صاحب المكتب يبعت أي رسالة لـ @$BOTNAME (أو يضيفه في جروب المكتب ويكتب فيه)."
  read -rp "   بعد ما يبعت دوس Enter (أو اكتب skip وEnter لو هتعملها بعدين): " S < /dev/tty
  if [ "$S" != "skip" ]; then
    CHAT=$(curl -s "https://api.telegram.org/bot$TG/getUpdates" | python3 -c '
import sys, json
r = [u.get("message") or u.get("my_chat_member") or {} for u in json.load(sys.stdin).get("result", [])]
c = [x["chat"] for x in r if x.get("chat")]
last = c[-1] if c else {}
print(str(last["id"]) + "|" + (last.get("title") or last.get("first_name") or "") if c else "")')
    if [ -n "$CHAT" ]; then
      echo "   آخر رسالة جاية من: ${CHAT#*|}"
      read -rp "   ده صاحب المكتب؟ (y/n): " OK < /dev/tty
      [ "$OK" = "y" ] && CHAT=${CHAT%%|*} || CHAT=""
    else
      echo "   ⚠️ مالقيتش رسايل — هتقدر تضيفها بعدين بتشغيل السكريبت تاني بنفس الكود."
    fi
  fi
fi

python3 - "$OFF" "$CODE" "$NAME" "$PHONE" "$AREA" "$PNID" "$WABA" "$TOKEN" "$P1" "$CHAT" <<'PY'
import json, os, sys, re
path, code, name, phone, area, pnid, waba, token, pw, chat = sys.argv[1:]
data = {}
if os.path.exists(path):
    data = json.load(open(path, encoding="utf-8"))
for other, o in data.items():
    if other != code and o.get("phone_number_id") == pnid:
        sys.exit(f"❌ رقم الواتساب ده متسجل بالفعل لمكتب {other}")
if phone and not re.match(r"^(?:\+?20|0)1[0125]\d{8}$", phone):
    sys.exit("❌ رقم الشركة مش موبايل مصري صحيح")
cur = data.get(code, {})
cur.update({"name": name or cur.get("name", ""), "phone": phone or cur.get("phone", ""),
            "area_context": area or cur.get("area_context", ""), "phone_number_id": pnid, "waba_id": waba,
            "dashboard_password": pw})
if token: cur["access_token"] = token
if chat: cur["telegram_chat_id"] = chat
cur.setdefault("extra_rules", "")
data[code] = cur
tmp = path + ".tmp"
json.dump(data, open(tmp, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
os.chmod(tmp, 0o600); os.replace(tmp, path)
print(f"✔ المكتب {code} اتحفظ")
PY

echo "==> ربط رقم المكتب بالبوت في ميتا"
USE_TOKEN=${TOKEN:-$(get WHATSAPP_ACCESS_TOKEN)}
curl -sS -X POST "https://graph.facebook.com/v21.0/$WABA/subscribed_apps" -H "Authorization: Bearer $USE_TOKEN"; echo
[ -n "$CHAT" ] && curl -s -X POST "https://api.telegram.org/bot$TG/sendMessage" --data-urlencode "chat_id=$CHAT" \
  --data-urlencode "text=✅ تنبيهات بوت واتساب «$NAME» اشتغلت هنا." > /dev/null && echo "✔ رسالة تجربة اتبعتت على تليجرام"

echo
echo "✅ خلصنا. البوت بيرد على رقم المكتب من دلوقتي (من غير restart)."
echo "   لوحة المكتب: https://bot.tatweereg.tech/dashboard — المستخدم: $CODE — والباسورد اللي كتبته"
echo "   لو ظهر فوق {\"success\":true} يبقى الربط مع ميتا تمام."
