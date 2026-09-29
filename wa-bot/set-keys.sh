#!/usr/bin/env bash
# يحدّث المفاتيح التلاتة في /opt/wa-bot/.env ويعيد تشغيل البوت ويربط ميتا.
# شغّله من ترمينال بيقبل اللصق (PowerShell: ssh root@186.241.26.230)
set -e
ENV=/opt/wa-bot/.env
RAW=https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/main/wa-bot
[ -f "$ENV" ] || { echo "❌ مفيش $ENV — شغّل install.sh الأول"; exit 1; }

ask() {  # $1 = label, $2 = min length
  local v
  while true; do
    read -rsp "$1: " v < /dev/tty; echo > /dev/tty
    v=$(printf %s "$v" | tr -d '\r\n\t ')
    if [ ${#v} -ge "$2" ]; then printf %s "$v"; return; fi
    echo "   ⚠️ المفتاح قصير (${#v} حرف) — غالبًا اللصق ماشتغلش. جرّب تاني." > /dev/tty
  done
}

echo "==> الصق كل مفتاح ودوس Enter (الكتابة مش هتظهر)"
TOK=$(ask "WhatsApp Access Token" 50)
SEC=$(ask "Meta App Secret" 20)
ANT=$(ask "Anthropic API Key" 30)
echo "   ✔ طول المفاتيح: token=${#TOK} secret=${#SEC} anthropic=${#ANT}"

python3 - "$ENV" "$TOK" "$SEC" "$ANT" <<'PY'
import sys
path, tok, sec, ant = sys.argv[1:]
vals = {"WHATSAPP_ACCESS_TOKEN": tok, "META_APP_SECRET": sec, "ANTHROPIC_API_KEY": ant}
lines = open(path, encoding="utf-8").read().splitlines()
out = []
for ln in lines:
    k = ln.split("=", 1)[0]
    out.append(f"{k}={vals.pop(k)}" if k in vals else ln)
out += [f"{k}={v}" for k, v in vals.items()]
open(path, "w", encoding="utf-8").write("\n".join(out) + "\n")
PY
chmod 600 "$ENV"

echo "==> إعادة تشغيل البوت بالمفاتيح الجديدة"
curl -fsSL -o /root/install.sh "$RAW/install.sh"
bash /root/install.sh

echo "==> ربط ميتا بالبوت"
curl -fsSL "$RAW/connect-meta.sh" | bash
