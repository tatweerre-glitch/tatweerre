#!/usr/bin/env bash
# يجرّب تنبيه تليجرام من غير واتساب: عميل وهمي بيطلب يكلم حد، والبوت يمشي نفس المسار الحقيقي
# (Claude router ← الرد ← التسجيل ← تنبيه تليجرام)، وبعدين العميل الوهمي بيتمسح.
docker exec -i tatweer-wa-bot python - <<'PY'
import asyncio, agents
P = "tatweer:200000000000"
async def main():
    reply = await agents.handle_message(P, "عميل تجربة (اختبار التنبيه)", "السلام عليكم، عايز شقة ٣ أوض في الفردوس كاش، وعايز أكلم حد من الشركة")
    r = agents.LEADS.get(P, {})
    print("رد البوت (مااتبعتش لحد):", reply)
    print("محتاج موظف:", r.get("needs_human"))
    print("✅ المفروض تنبيه وصلك على تليجرام دلوقتي" if r.get("needs_human") else "⚠️ الـ router ماعتبروش محتاج موظف — ابعت النتيجة لـ Claude")
asyncio.run(main())
for t in ("messages", "leads", "followups"):
    agents._db.execute(f"DELETE FROM {t} WHERE phone=?", (P,))
agents._db.commit()
print("🧹 العميل الوهمي اتمسح")
PY
