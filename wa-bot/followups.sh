#!/usr/bin/env bash
# يعرض حالة المتابعة التلقائية: مين هيتبعتله متابعة، ومين اتبعتله قبل كده.
docker exec -i tatweer-wa-bot python - <<'PY'
import followup, agents
from datetime import datetime
print("المتابعة:", "شغالة ✔" if followup.ENABLED else "مقفولة ✘",
      "| Template:", followup.TEMPLATE or "لسه مش متظبط (متابعة ٢ بتروح تنبيه تليجرام)",
      "| وقت هدوء دلوقتي" if followup.is_quiet_hours() else "")
c = followup.candidates()
print(f"\nمستحقين متابعة دلوقتي: {len(c)}")
for p, k, h in c:
    print(f"  +{p}  {k}  ساكت من {h:.0f} ساعة")
rows = agents._db.execute("SELECT phone, kind, sent_ts FROM followups ORDER BY sent_ts DESC LIMIT 20").fetchall()
print(f"\nآخر متابعات اتبعتت: {len(rows)}")
for p, k, t in rows:
    print(f"  +{p}  {k}  {t[:16]}")
PY
