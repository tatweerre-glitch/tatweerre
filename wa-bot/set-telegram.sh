#!/usr/bin/env bash
# يظبط تنبيهات تليجرام للبوت: ياخد توكن بوت تليجرام، يجيب الـ Chat ID، ويبعت رسالة تجربة.
# قبل التشغيل: ابعت أي رسالة للبوت من حسابك على تليجرام.
set -e
ENV=/opt/wa-bot/.env
RAW=https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/main/wa-bot
[ -f "$ENV" ] || { echo "❌ مفيش $ENV — شغّل install.sh الأول"; exit 1; }

read -rsp "Telegram Bot Token: " TOK < /dev/tty; echo
TOK=$(printf %s "$TOK" | tr -d '\r\n\t ')
[ ${#TOK} -ge 30 ] || { echo "❌ التوكن قصير (${#TOK}) — غالبًا اللصق ماشتغلش"; exit 1; }

ME=$(curl -s "https://api.telegram.org/bot$TOK/getMe")
echo "$ME" | grep -q '"ok":true' || { echo "❌ التوكن غلط: $ME"; exit 1; }
echo "✔ البوت: @$(echo "$ME" | python3 -c 'import sys,json;print(json.load(sys.stdin)["result"]["username"])')"

UPD=$(curl -s "https://api.telegram.org/bot$TOK/getUpdates")
if echo "$UPD" | grep -q "webhook is active"; then
  echo "❌ البوت ده مربوط بـ n8n (webhook) فمينفعش نقرا منه الرسايل."
  echo "   اعمل بوت جديد مخصوص للتنبيهات من @BotFather (/newbot) وشغّل السكريبت تاني بتوكنه."
  exit 1
fi
CHAT=$(echo "$UPD" | python3 -c '
import sys, json
r = json.load(sys.stdin).get("result", [])
ids = [u.get("message", {}).get("chat", {}).get("id") for u in r if u.get("message")]
print(ids[-1] if ids else "")')
[ -n "$CHAT" ] || { echo "❌ مالقيتش رسايل — ابعت أي رسالة للبوت من تليجرام بتاعك، واستنى ثواني، وشغّل السكريبت تاني."; exit 1; }
echo "✔ Chat ID: $CHAT"

python3 - "$ENV" "$TOK" "$CHAT" <<'PY'
import sys
path, tok, chat = sys.argv[1:]
vals = {"TELEGRAM_BOT_TOKEN": tok, "TELEGRAM_CHAT_ID": chat}
lines = open(path, encoding="utf-8").read().splitlines()
out = [f"{l.split('=',1)[0]}={vals.pop(l.split('=',1)[0])}" if l.split('=',1)[0] in vals else l for l in lines]
out += [f"{k}={v}" for k, v in vals.items()]
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
chmod 600 "$ENV"

curl -s -X POST "https://api.telegram.org/bot$TOK/sendMessage" \
  --data-urlencode "chat_id=$CHAT" \
  --data-urlencode "text=✅ تنبيهات بوت واتساب تطوير اشتغلت. أي عميل جاهز أو طالب موظف هيوصلك هنا." > /dev/null
echo "✔ اتبعتت رسالة تجربة على تليجرام"

echo "==> إعادة تشغيل البوت"
curl -fsSL -o /root/install.sh "$RAW/install.sh"
bash /root/install.sh
