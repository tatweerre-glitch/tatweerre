#!/usr/bin/env bash
# يغيّر باسورد لوحة العملاء (https://bot.tatweereg.tech/dashboard — المستخدم: tatweer)
set -e
ENV=/opt/wa-bot/.env
RAW=https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/main/wa-bot
[ -f "$ENV" ] || { echo "❌ مفيش $ENV"; exit 1; }
while true; do
  read -rsp "اكتب باسورد جديد للوحة (8 حروف أو أكتر): " P1 < /dev/tty; echo
  read -rsp "اكتبه تاني للتأكيد: " P2 < /dev/tty; echo
  P1=$(printf %s "$P1" | tr -d '\r\n'); P2=$(printf %s "$P2" | tr -d '\r\n')
  [ "$P1" = "$P2" ] || { echo "⚠️ الاتنين مش زي بعض، جرّب تاني"; continue; }
  [ ${#P1} -ge 8 ] || { echo "⚠️ قصير (${#P1})، لازم 8 أو أكتر"; continue; }
  break
done
python3 - "$ENV" "$P1" <<'PY'
import sys
path, pw = sys.argv[1:]
lines = [l for l in open(path, encoding="utf-8").read().splitlines() if not l.startswith("DASHBOARD_PASSWORD=")]
lines.append(f"DASHBOARD_PASSWORD={pw}")
open(path, "w", encoding="utf-8").write("\n".join(lines) + "\n")
PY
chmod 600 "$ENV"
echo "==> تحديث البوت"
curl -fsSL -o /root/install.sh "$RAW/install.sh" && bash /root/install.sh | tail -3
echo "✅ ادخل على https://bot.tatweereg.tech/dashboard — المستخدم: tatweer — والباسورد اللي لسه كاتبه"
