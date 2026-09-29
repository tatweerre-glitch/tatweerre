#!/usr/bin/env bash
# يعرض بيانات العملاء المتسجلة وآخر رسايل كل عميل
docker exec -i tatweer-wa-bot python - <<'PY'
import sqlite3, json
db = sqlite3.connect("/data/bot.db")
print("عدد العملاء:", db.execute("SELECT COUNT(*) FROM leads").fetchone()[0], "| عدد الرسايل:", db.execute("SELECT COUNT(*) FROM messages").fetchone()[0])
for phone, data, upd in db.execute("SELECT phone, data, updated FROM leads"):
    d = json.loads(data)
    print(f"\n=== {phone} ({d.get('name','')}) — آخر تحديث {upd[:16]}")
    for k in ("intent", "qualification", "budget", "area_m2", "location", "payment", "rooms", "needs_human"):
        print(f"   {k}: {d.get(k)}")
    n = db.execute("SELECT COUNT(*) FROM messages WHERE phone=?", (phone,)).fetchone()[0]
    print(f"   عدد الرسايل المتسجلة: {n}")
PY
