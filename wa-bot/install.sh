#!/usr/bin/env bash
# تثبيت بوت واتساب تطوير على سيرفر Hostinger (جنب n8n + Traefik)
set -e
# حماية: السكريبت ده للسيرفر (Linux + Docker) بس
if [ "$(uname -s)" != "Linux" ] || ! command -v docker >/dev/null 2>&1 || ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q '^n8n-traefik-1$'; then
  echo "❌ السكريبت ده لازم يشتغل على سيرفر Hostinger (VPS ← Browser terminal)، مش على جهازك."
  echo "   ماتكتبش أي مفاتيح هنا. اقفل الشاشة دي وافتح الترمينال بتاع السيرفر."
  exit 1
fi
DOMAIN="${BOT_DOMAIN:-bot.tatweereg.tech}"
APP_DIR=/opt/wa-bot
mkdir -p "$APP_DIR"
cd "$APP_DIR"
echo "==> كتابة ملفات البوت في $APP_DIR"
cat > main.py <<'__EOF_TATWEER__'
"""
Webhook واتساب — يستقبل رسايل العملاء من Meta ويوزعها على الوكلاء.

تشغيل محلي:   uvicorn main:app --host 0.0.0.0 --port 8000
"""
import logging
import os
from collections import deque

from dotenv import load_dotenv

load_dotenv()

from fastapi import BackgroundTasks, FastAPI, HTTPException, Query, Request  # noqa: E402
from fastapi.responses import PlainTextResponse  # noqa: E402

import agents  # noqa: E402
import followup  # noqa: E402
import whatsapp  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("wa-bot")

VERIFY_TOKEN = os.getenv("WHATSAPP_VERIFY_TOKEN", "")

app = FastAPI(title="Tatweer WhatsApp Agents")

# Meta ممكن تبعت نفس الرسالة أكتر من مرة — نمنع الرد المكرر
_seen_ids: deque = deque(maxlen=2000)


@app.on_event("startup")
async def start_followups():
    import asyncio
    app.state.followup_task = asyncio.create_task(followup.loop())


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/")
def root():
    return {"service": "tatweer-wa-bot", "ok": True}


@app.get("/webhook", response_class=PlainTextResponse)
def verify_webhook(
    mode: str = Query(None, alias="hub.mode"),
    token: str = Query(None, alias="hub.verify_token"),
    challenge: str = Query(None, alias="hub.challenge"),
):
    """خطوة التحقق اللي Meta بتعملها مرة واحدة لما تسجل الـ Webhook."""
    if mode == "subscribe" and VERIFY_TOKEN and token == VERIFY_TOKEN:
        return challenge
    raise HTTPException(status_code=403, detail="verification failed")


@app.post("/webhook")
async def receive(request: Request, background: BackgroundTasks):
    raw = await request.body()
    if not whatsapp.verify_signature(raw, request.headers.get("X-Hub-Signature-256")):
        raise HTTPException(status_code=401, detail="bad signature")

    payload = await request.json()
    for msg in whatsapp.extract_messages(payload):
        if msg["id"] in _seen_ids:
            continue
        _seen_ids.append(msg["id"])
        # نرد على Meta بـ 200 فورًا، والمعالجة تكمل في الخلفية
        background.add_task(process, msg)
    return {"status": "received"}


async def process(msg: dict):
    try:
        await whatsapp.mark_read(msg["id"])
        if msg["type"] not in ("text", "button", "interactive"):
            await whatsapp.send_text(
                msg["from"],
                "وصلتني رسالتك 🙏 ممكن تكتبلي طلبك كتابة عشان أقدر أساعدك أسرع؟",
            )
            return
        log.info("msg from %s (ad=%s): %s", msg["from"], msg["from_ad"], msg["text"])
        reply = await agents.handle_message(msg["from"], msg["name"], msg["text"], msg["from_ad"])
        await whatsapp.send_text(msg["from"], reply)
    except Exception:
        log.exception("failed processing message %s", msg.get("id"))

__EOF_TATWEER__

cat > whatsapp.py <<'__EOF_TATWEER__'
"""
التعامل مع WhatsApp Cloud API من Meta:
- التحقق من توقيع الرسائل الواردة (أمان)
- استخراج الرسائل من الـ payload
- إرسال الردود
"""
import hashlib
import hmac
import os

import httpx

GRAPH_VERSION = os.getenv("GRAPH_API_VERSION", "v21.0")
PHONE_NUMBER_ID = os.getenv("WHATSAPP_PHONE_NUMBER_ID", "")
ACCESS_TOKEN = os.getenv("WHATSAPP_ACCESS_TOKEN", "")
APP_SECRET = os.getenv("META_APP_SECRET", "")


def verify_signature(raw_body: bytes, signature_header: str | None) -> bool:
    """يتأكد إن الرسالة جاية فعلًا من Meta (هيدر X-Hub-Signature-256)."""
    if not APP_SECRET:
        # وقت التجربة المحلية بس — على السيرفر لازم APP_SECRET يكون متظبط
        return True
    if not signature_header or not signature_header.startswith("sha256="):
        return False
    expected = hmac.new(APP_SECRET.encode(), raw_body, hashlib.sha256).hexdigest()
    return hmac.compare_digest(expected, signature_header.removeprefix("sha256="))


def extract_messages(payload: dict) -> list[dict]:
    """يطلع الرسائل النصية من الـ webhook payload بشكل مبسط."""
    out = []
    for entry in payload.get("entry", []):
        for change in entry.get("changes", []):
            value = change.get("value", {})
            names = {
                c.get("wa_id"): c.get("profile", {}).get("name", "")
                for c in value.get("contacts", [])
            }
            for msg in value.get("messages", []):
                mtype = msg.get("type")
                if mtype == "text":
                    text = msg["text"]["body"]
                elif mtype == "button":
                    text = msg["button"].get("text", "")
                elif mtype == "interactive":
                    inter = msg["interactive"]
                    text = (inter.get("button_reply") or inter.get("list_reply") or {}).get("title", "")
                else:
                    # صور/صوت/موقع... نسجلها كنوع بس لحد ما نضيف دعمها
                    text = f"[{mtype}]"
                out.append({
                    "id": msg["id"],
                    "from": msg["from"],
                    "name": names.get(msg["from"], ""),
                    "type": mtype,
                    "text": text,
                    # referral موجود لو العميل جاي من إعلان Click-to-WhatsApp
                    "from_ad": "referral" in msg,
                    "ad_info": msg.get("referral"),
                })
    return out


async def send_text(to: str, body: str) -> dict:
    """يبعت رسالة نصية للعميل (مسموح بيها جوه نافذة الـ 24 ساعة)."""
    url = f"https://graph.facebook.com/{GRAPH_VERSION}/{PHONE_NUMBER_ID}/messages"
    payload = {
        "messaging_product": "whatsapp",
        "to": to,
        "type": "text",
        "text": {"body": body[:4096]},
    }
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(url, json=payload, headers={"Authorization": f"Bearer {ACCESS_TOKEN}"})
        r.raise_for_status()
        return r.json()


async def send_template(to: str, name: str, lang: str, body_params: list[str]) -> dict:
    """يبعت Template معتمد من ميتا (الطريقة الوحيدة المسموحة بعد ما نافذة الـ 24 ساعة تقفل)."""
    url = f"https://graph.facebook.com/{GRAPH_VERSION}/{PHONE_NUMBER_ID}/messages"
    template = {"name": name, "language": {"code": lang}}
    if body_params:
        template["components"] = [{"type": "body", "parameters": [{"type": "text", "text": p} for p in body_params]}]
    payload = {"messaging_product": "whatsapp", "to": to, "type": "template", "template": template}
    async with httpx.AsyncClient(timeout=20) as client:
        r = await client.post(url, json=payload, headers={"Authorization": f"Bearer {ACCESS_TOKEN}"})
        r.raise_for_status()
        return r.json()


async def mark_read(message_id: str) -> None:
    """يعلّم الرسالة كمقروءة (علامتين زرق) — بيدي انطباع احترافي."""
    url = f"https://graph.facebook.com/{GRAPH_VERSION}/{PHONE_NUMBER_ID}/messages"
    payload = {"messaging_product": "whatsapp", "status": "read", "message_id": message_id}
    async with httpx.AsyncClient(timeout=10) as client:
        await client.post(url, json=payload, headers={"Authorization": f"Bearer {ACCESS_TOKEN}"})

__EOF_TATWEER__

cat > agents.py <<'__EOF_TATWEER__'
"""
توزيع الرسائل على الوكلاء.

المسار الحالي (نسخة أولى قابلة للبيع — ٣ وظايف أساسية):
  رسالة العميل ← planner-router (يحدد النية ودرجة التأهيل)
              ← real-estate-agent (يرد على العميل)
              ← crm-publisher (يسجل العميل وحالته)

باقي الوكلاء (task-executor, marketing-creative, qa-agent) بيتضافوا بعدين
بنفس الطريقة: دالة async تاخد السياق وترجع نتيجة.
"""
import json
import os
from datetime import datetime

from anthropic import AsyncAnthropic

MODEL = os.getenv("CLAUDE_MODEL", "claude-sonnet-5-5")
COMPANY = os.getenv("COMPANY_NAME", "تطوير للخدمات العقارية")
COMPANY_PHONE = os.getenv("COMPANY_PHONE", "")

client = AsyncAnthropic()  # بياخد ANTHROPIC_API_KEY من البيئة

# ---- تخزين دائم (SQLite في /data) — المحادثات والعملاء بيفضلوا بعد أي restart ----
import sqlite3

DB_PATH = os.getenv("DB_PATH", os.path.join(os.path.dirname(os.getenv("LEADS_FILE", "leads.json")) or ".", "bot.db"))
_db = sqlite3.connect(DB_PATH, check_same_thread=False)
_db.executescript("""
CREATE TABLE IF NOT EXISTS messages (id INTEGER PRIMARY KEY, phone TEXT, role TEXT, content TEXT, ts TEXT);
CREATE INDEX IF NOT EXISTS idx_messages_phone ON messages(phone, id);
CREATE TABLE IF NOT EXISTS leads (phone TEXT PRIMARY KEY, data TEXT, updated TEXT);
""")
_db.commit()


class _History:
    """آخر ٢٠ رسالة لكل عميل — بتتقري وتتكتب في قاعدة البيانات."""
    def __getitem__(self, phone):
        rows = _db.execute(
            "SELECT role, content FROM (SELECT id, role, content FROM messages WHERE phone=? ORDER BY id DESC LIMIT 20) ORDER BY id",
            (phone,)).fetchall()
        return _Hist(phone, rows)


class _Hist(list):
    def __init__(self, phone, rows):
        super().__init__(rows)
        self.phone = phone

    def append(self, item):
        role, content = item
        _db.execute("INSERT INTO messages(phone, role, content, ts) VALUES (?,?,?,?)",
                    (self.phone, role, content, datetime.now().isoformat()))
        _db.commit()
        super().append(item)


class _Leads(dict):
    def __init__(self):
        super().__init__({p: json.loads(d) for p, d in _db.execute("SELECT phone, data FROM leads")})

    def save(self, phone):
        _db.execute("INSERT OR REPLACE INTO leads(phone, data, updated) VALUES (?,?,?)",
                    (phone, json.dumps(self[phone], ensure_ascii=False), datetime.now().isoformat()))
        _db.commit()


HISTORY = _History()
LEADS = _Leads()


def _text(resp) -> str:
    """يجمع النص من الرد ويتجاهل أي بلوكات تانية (زي thinking)."""
    return "".join(b.text for b in resp.content if getattr(b, "type", "") == "text").strip()


import re as _re
_PHONE_RE = _re.compile(r"(?:\+?20|0)1[0125][\s\-]?\d{3,4}[\s\-]?\d{4}")


def _clean_phones(reply: str) -> str:
    """شبكة أمان: أي رقم موبايل مصري في الرد غير رقم الشركة بيتشال."""
    allowed = _re.sub(r"\D", "", COMPANY_PHONE)[-10:]
    def fix(m):
        return m.group(0) if allowed and _re.sub(r"\D", "", m.group(0))[-10:] == allowed else "نفس الرقم ده"
    return _PHONE_RE.sub(fix, reply)


ROUTER_PROMPT = """أنت planner-router في نظام وكلاء لشركة عقارات مصرية.
مهمتك تحلل رسالة العميل وترجع JSON فقط بالشكل ده بدون أي كلام زيادة:
{
  "intent": "buy" | "rent" | "sell" | "inquiry" | "greeting" | "complaint" | "other",
  "qualification": "hot" | "warm" | "cold",
  "budget": "المبلغ لو اتذكر أو null",
  "area_m2": "المساحة لو اتذكرت أو null",
  "location": "المنطقة لو اتذكرت أو null",
  "payment": "كاش أو تقسيط لو اتذكر أو null",
  "rooms": "عدد الأوض لو اتذكر أو null",
  "needs_human": true | false,
  "missing_info": ["الحاجات الناقصة عشان نأهل العميل، مثلا: الميزانية، المساحة، طريقة الدفع"]
}
hot = عنده ميزانية وجاهز يعاين قريب. warm = مهتم بس ناقص معلومات. cold = استفسار عام.
needs_human = true لو العميل طلب يكلم حد، أو فيه شكوى، أو جاهز يدفع/يعاين."""

AGENT_PROMPT = f"""أنت real-estate-agent، مساعد مبيعات في شركة "{COMPANY}" بترد على العملاء على واتساب.
- اتكلم بالعامية المصرية المحترمة، ردود قصيرة ومباشرة (٢-٤ سطور) زي أي موظف مبيعات شاطر.
- هدفك: ترد فورًا، وتأهل العميل بسؤال واحد في المرة عن الحاجة الناقصة (الميزانية، المساحة، المنطقة، كاش ولا تقسيط، إمتى عايز يستلم).
- ممنوع تخترع أسعار أو وحدات أو مواعيد. لو مش عارف، قول إن مستشار من الشركة هيتواصل معاه بالتفاصيل.
- ممنوع تذكر رقم أي عمارة حقيقي. استخدم كود الوحدة بس (مثال: MAF-96-S-01).
- لو العميل جاهز يعاين أو طلب يكلم حد، قوله إن زميلك هيكلمه قريب{(' أو يتصل على ' + COMPANY_PHONE) if COMPANY_PHONE else ''}.
- الشركة شغالة في "مدينة الفردوس للقوات المسلحة" في 6 أكتوبر (الجيزة). لو العميل قال "الفردوس" أو شارع جوه الفردوس، ده كفاية — متسألش عن المدينة أو المحافظة.
- رقم الشركة ده رقم العميل يتصل بيه. لو زميلك هيكلم العميل، قول "زميلي هيكلمك" بس — متقولش "هيكلمك على رقم كذا".
- ممنوع تكتب أي رقم تليفون غير رقم الشركة{(' ' + COMPANY_PHONE) if COMPANY_PHONE else ''}. متخترعش رقم للعميل ولا لزميلك. لو زميلك هيكلمه، قول "هيكلمك على نفس الرقم ده".
- متأكدش معلومة العميل ماقالهاش (زي كاش أو تقسيط أو ميعاد) — اسأل عنها.
- متقولش إنك ذكاء اصطناعي إلا لو العميل سأل صراحة — ولو سأل، قول الحقيقة."""


async def planner_router(phone: str, text: str) -> dict:
    history = "\n".join(f"{r}: {m}" for r, m in HISTORY[phone])
    resp = await client.messages.create(
        model=MODEL,
        max_tokens=2000,
        system=ROUTER_PROMPT,
        messages=[{"role": "user", "content": f"المحادثة السابقة:\n{history or '(مفيش)'}\n\nالرسالة الجديدة:\n{text}"}],
    )
    raw = _text(resp)
    try:
        start, end = raw.index("{"), raw.rindex("}") + 1
        return json.loads(raw[start:end])
    except ValueError:
        return {"intent": "other", "qualification": "cold", "needs_human": False, "missing_info": []}


def _known_facts(phone: str, routing: dict) -> str:
    """المعلومات المتسجلة عن العميل (من قاعدة البيانات + الرسالة الحالية)."""
    lead = dict(LEADS.get(phone, {}))
    lead.update({k: v for k, v in routing.items() if v and k in ("budget", "area_m2", "location", "payment", "rooms")})
    labels = {"budget": "الميزانية", "area_m2": "المساحة", "location": "المنطقة", "payment": "طريقة الدفع", "rooms": "عدد الأوض"}
    parts = [f"{labels[k]}: {lead[k]}" for k in labels if lead.get(k)]
    return "، ".join(parts) or "مفيش"


FALLBACK_REPLY = "تمام، وصلتني 👍 زميلي من الشركة هيتابع معاك في أقرب وقت."


async def real_estate_agent(phone: str, name: str, text: str, routing: dict) -> str:
    msgs = []
    for role, content in HISTORY[phone]:
        msgs.append({"role": "user" if role == "عميل" else "assistant", "content": content})
    note = (
        f"[معلومات داخلية من الـ router — متذكرهاش للعميل: اسم العميل: {name or 'غير معروف'}، "
        f"النية: {routing.get('intent')}، التأهيل: {routing.get('qualification')}، "
        f"الناقص: {', '.join(routing.get('missing_info') or []) or 'مفيش'}، "
        f"اللي العميل قاله قبل كده ومتسجل: {_known_facts(phone, routing)} — متسألش عنه تاني]\n\n{text}"
    )
    msgs.append({"role": "user", "content": note})
    # الـ API محتاج المحادثة تبدأ بـ user ويتبادلوا — ننضف أي تكرار
    cleaned = []
    for m in msgs:
        if cleaned and cleaned[-1]["role"] == m["role"]:
            cleaned[-1]["content"] += "\n" + m["content"]
        else:
            cleaned.append(m)
    if cleaned[0]["role"] != "user":
        cleaned.pop(0)
    resp = await client.messages.create(model=MODEL, max_tokens=3000, system=AGENT_PROMPT, messages=cleaned)
    return _clean_phones(_text(resp))


async def crm_publisher(phone: str, name: str, routing: dict, from_ad: bool) -> None:
    """يسجل/يحدث بيانات العميل. حاليًا في الذاكرة + ملف JSON — بعدين نربطه بالـ CRM/التطبيق."""
    lead = LEADS.setdefault(phone, {"phone": phone, "first_seen": datetime.now().isoformat(), "from_ad": from_ad})
    lead.update({
        "name": name or lead.get("name", ""),
        "last_seen": datetime.now().isoformat(),
        "intent": routing.get("intent"),
        "qualification": routing.get("qualification"),
        "needs_human": routing.get("needs_human", False),
    })
    for key in ("budget", "area_m2", "location", "payment", "rooms"):
        if routing.get(key):
            lead[key] = routing[key]
    LEADS.save(phone)
    with open(os.getenv("LEADS_FILE", "leads.json"), "w", encoding="utf-8") as f:
        json.dump(LEADS, f, ensure_ascii=False, indent=2)


_last_notify: dict[str, float] = {}


def _should_notify(phone: str, every_sec: int = 6 * 3600) -> bool:
    """تنبيه واحد لكل عميل كل ٦ ساعات — عشان تليجرام مايتملاش."""
    import time
    now = time.time()
    if now - _last_notify.get(phone, 0) < every_sec:
        return False
    _last_notify[phone] = now
    return True


async def handle_message(phone: str, name: str, text: str, from_ad: bool = False) -> str:
    """نقطة الدخول: رسالة واحدة ← رد واحد."""
    import followup
    followup.on_customer_message(phone, text)
    routing = await planner_router(phone, text)
    reply = await real_estate_agent(phone, name, text, routing)
    if not reply:
        # الرد طلع فاضي — نرد رد آمن ونبلّغ الفريق بدل ما العميل يستنى
        import logging
        logging.getLogger("wa-bot").warning("empty reply for %s — using fallback", phone)
        reply = FALLBACK_REPLY
        routing["needs_human"] = True
    HISTORY[phone].append(("عميل", text))
    HISTORY[phone].append(("وكيل", reply))
    await crm_publisher(phone, name, routing, from_ad)
    followup.on_customer_message(phone, text)  # مرة تانية عشان عميل جديد لسه متسجل دلوقتي
    if routing.get("needs_human") and _should_notify(phone):
        await notify_team(phone, name, text, routing)
    return reply


async def notify_team(phone: str, name: str, text: str, routing: dict) -> None:
    """ينبّه الفريق على تليجرام لما عميل يحتاج موظف (بيستخدم البوت اللي عندك)."""
    token, chat_id = os.getenv("TELEGRAM_BOT_TOKEN"), os.getenv("TELEGRAM_CHAT_ID")
    if not (token and chat_id):
        return
    import httpx
    msg = (f"🔥 عميل محتاج متابعة ({routing.get('qualification')})\n"
           f"الاسم: {name or '-'}\nالرقم: +{phone}\nواتساب: https://wa.me/{phone}\n"
           f"النية: {routing.get('intent')}\nالطلب: {_known_facts(phone, routing)}\nآخر رسالة: {text}")
    async with httpx.AsyncClient(timeout=10) as c:
        await c.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": chat_id, "text": msg})

__EOF_TATWEER__

cat > followup.py <<'__EOF_TATWEER__'
"""
المتابعة التلقائية للعملاء اللي سكتوا.

  • متابعة ١ (جوه نافذة الـ ٢٤ ساعة): لو العميل ساكت من ١٨ ساعة أو أكتر وآخر رسالة كانت مننا،
    البوت يبعتله رسالة قصيرة طبيعية تكمّل الكلام (Claude بيكتبها من المحادثة).
  • متابعة ٢ (بعد ٣ أيام): برا نافذة الـ ٢٤ ساعة ميتا مش بتسمح غير بـ Template معتمد.
    لو FOLLOWUP_TEMPLATE متظبط في .env بنبعته، ولو مش متظبط بنبعت تنبيه تليجرام للفريق يكلمه بنفسه.

قواعد: مفيش متابعة لعميل طلب موظف (الفريق ماسكه)، أو قال "مش مهتم"، أو كلامه كان تحية بس.
مفيش إرسال بالليل (بتوقيت القاهرة). أي رسالة جديدة من العميل بتبدأ الدورة من الأول.
"""
import asyncio
import logging
import os
import re
from datetime import datetime
from zoneinfo import ZoneInfo

import agents
import whatsapp

log = logging.getLogger("wa-bot")

ENABLED = os.getenv("FOLLOWUP_ENABLED", "1") == "1"
CHECK_EVERY_MIN = int(os.getenv("FOLLOWUP_CHECK_MIN", "10"))
NUDGE1_AFTER_H = float(os.getenv("FOLLOWUP1_HOURS", "18"))
NUDGE2_AFTER_H = float(os.getenv("FOLLOWUP2_HOURS", "72"))
WINDOW_H = 23.5                      # هامش أمان قبل ما نافذة الـ ٢٤ ساعة تقفل
TEMPLATE = os.getenv("FOLLOWUP_TEMPLATE", "")          # اسم الـ Template المعتمد من ميتا
TEMPLATE_LANG = os.getenv("FOLLOWUP_TEMPLATE_LANG", "ar")
QUIET_FROM, QUIET_TO = 22, 9         # مفيش رسايل من ١٠ بالليل لـ ٩ الصبح (القاهرة)
CAIRO = ZoneInfo("Africa/Cairo")
ACTIVE_INTENTS = {"buy", "rent", "sell", "inquiry"}

OPT_OUT_RE = re.compile(r"مش مهتم|مش عايز|متبعتليش|متبعتش|بطّ?ل ?(تبعت|رسايل)|الغ[يى] الاشتراك|\bstop\b", re.I)

agents._db.executescript("""
CREATE TABLE IF NOT EXISTS followups (phone TEXT, kind TEXT, sent_ts TEXT, PRIMARY KEY (phone, kind));
""")
agents._db.commit()


# ---------- بتتنده من handle_message مع كل رسالة جديدة من العميل ----------
def on_customer_message(phone: str, text: str) -> None:
    """العميل رد ← نصفّر المتابعات. ولو قال مش مهتم ← نوقف المتابعة خالص."""
    agents._db.execute("DELETE FROM followups WHERE phone=?", (phone,))
    agents._db.commit()
    lead = agents.LEADS.get(phone)
    if lead is not None:
        opted = bool(OPT_OUT_RE.search(text or ""))
        if lead.get("opted_out", False) != opted:
            lead["opted_out"] = opted
            agents.LEADS.save(phone)


def _last_messages(phone: str):
    """(آخر رسالة من العميل، آخر رسالة من البوت، دور آخر رسالة)."""
    rows = agents._db.execute(
        "SELECT role, ts FROM messages WHERE phone=? ORDER BY id DESC LIMIT 40", (phone,)).fetchall()
    last_customer = next((datetime.fromisoformat(ts) for r, ts in rows if r == "عميل"), None)
    last_role = rows[0][0] if rows else None
    return last_customer, last_role


def _sent(phone: str, kind: str) -> bool:
    return agents._db.execute("SELECT 1 FROM followups WHERE phone=? AND kind=?", (phone, kind)).fetchone() is not None


def _mark(phone: str, kind: str, now: datetime) -> None:
    agents._db.execute("INSERT OR REPLACE INTO followups(phone, kind, sent_ts) VALUES (?,?,?)",
                       (phone, kind, now.isoformat()))
    agents._db.commit()


def is_quiet_hours(cairo_now: datetime | None = None) -> bool:
    h = (cairo_now or datetime.now(CAIRO)).hour
    return h >= QUIET_FROM or h < QUIET_TO


def candidates(now: datetime | None = None) -> list[tuple[str, str, float]]:
    """مين محتاج متابعة دلوقتي: [(phone, 'nudge1' | 'nudge2', ساعات السكوت)]."""
    now = now or datetime.now()
    out = []
    for phone, lead in list(agents.LEADS.items()):
        if lead.get("opted_out") or lead.get("needs_human"):
            continue
        if lead.get("intent") not in ACTIVE_INTENTS:
            continue
        last_customer, last_role = _last_messages(phone)
        if not last_customer or last_role != "وكيل":
            continue  # العميل هو اللي كاتب آخر رسالة ← البوت لسه هيرد، مش متابعة
        silent_h = (now - last_customer).total_seconds() / 3600
        if NUDGE1_AFTER_H <= silent_h < WINDOW_H and not _sent(phone, "nudge1"):
            out.append((phone, "nudge1", silent_h))
        elif silent_h >= NUDGE2_AFTER_H and not _sent(phone, "nudge2"):
            out.append((phone, "nudge2", silent_h))
    return out


NUDGE_PROMPT = agents.AGENT_PROMPT + """

[مهمة خاصة] العميل ساكت من حوالي يوم. اكتب رسالة متابعة واحدة قصيرة جدًا (سطر أو اتنين) تكمّل من آخر نقطة في الكلام:
فكّره بطلبه، واسأله السؤال الجاي اللي محتاجينه، أو اعرض إن زميلك يكلمه. من غير ضغط ومن غير اعتذار عن الإزعاج.
ممنوع تخترع وحدات أو أسعار أو عروض. اكتب الرسالة بس من غير أي مقدمة."""

NUDGE1_FALLBACK = "أهلًا بحضرتك تاني 👋 لسه مهتم نكمل ونشوفلك الوحدة المناسبة؟ لو حابب زميلي يكلمك قولّي."


async def _write_nudge(phone: str) -> str:
    msgs = [{"role": "user" if r == "عميل" else "assistant", "content": c} for r, c in agents.HISTORY[phone]]
    msgs.append({"role": "user", "content": f"[داخلي: العميل ساكت. اللي متسجل عنه: {agents._known_facts(phone, {})}. اكتب رسالة المتابعة دلوقتي]"})
    cleaned = []
    for m in msgs:
        if cleaned and cleaned[-1]["role"] == m["role"]:
            cleaned[-1]["content"] += "\n" + m["content"]
        else:
            cleaned.append(m)
    if cleaned[0]["role"] != "user":
        cleaned.pop(0)
    try:
        resp = await agents.client.messages.create(model=agents.MODEL, max_tokens=2000, system=NUDGE_PROMPT, messages=cleaned)
        text = agents._clean_phones(agents._text(resp))
    except Exception:
        log.exception("nudge generation failed for %s", phone)
        text = ""
    return text or NUDGE1_FALLBACK


async def _notify(text: str) -> None:
    token, chat_id = os.getenv("TELEGRAM_BOT_TOKEN"), os.getenv("TELEGRAM_CHAT_ID")
    if not (token and chat_id):
        return
    import httpx
    async with httpx.AsyncClient(timeout=10) as c:
        await c.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": chat_id, "text": text})


async def run_once(now: datetime | None = None, ignore_quiet: bool = False) -> list[str]:
    """دورة واحدة: يبعت المتابعات المستحقة ويرجع ملخص باللي اتعمل."""
    now = now or datetime.now()
    if not ignore_quiet and is_quiet_hours():
        return []
    done = []
    for phone, kind, silent_h in candidates(now):
        lead = agents.LEADS.get(phone, {})
        name = lead.get("name") or ""
        try:
            if kind == "nudge1":
                text = await _write_nudge(phone)
                await whatsapp.send_text(phone, text)
                agents.HISTORY[phone].append(("وكيل", text))
                done.append(f"{phone}: متابعة ١ اتبعتت")
            elif TEMPLATE:
                await whatsapp.send_template(phone, TEMPLATE, TEMPLATE_LANG, [name.split()[0] if name else "حضرتك"])
                agents.HISTORY[phone].append(("وكيل", f"[رسالة متابعة Template: {TEMPLATE}]"))
                done.append(f"{phone}: متابعة ٢ (Template) اتبعتت")
            else:
                await _notify(
                    f"⏰ عميل ساكت من {int(silent_h // 24)} أيام ومحتاج مكالمة\n"
                    f"الاسم: {name or '-'}\nالرقم: +{phone}\nواتساب: https://wa.me/{phone}\n"
                    f"الطلب: {agents._known_facts(phone, {})}\n"
                    f"(البوت مش هيقدر يبعتله غير بعد اعتماد Template المتابعة من ميتا)")
                done.append(f"{phone}: متابعة ٢ ← تنبيه تليجرام")
            _mark(phone, kind, now)
        except Exception:
            log.exception("follow-up %s failed for %s", kind, phone)
    for d in done:
        log.info("follow-up: %s", d)
    return done


async def loop() -> None:
    if not ENABLED:
        log.info("follow-up: disabled")
        return
    log.info("follow-up: on (every %s min, nudge1 after %sh, nudge2 after %sh, template=%s)",
             CHECK_EVERY_MIN, NUDGE1_AFTER_H, NUDGE2_AFTER_H, TEMPLATE or "-")
    while True:
        await asyncio.sleep(60)  # نستنى دقيقة بعد التشغيل
        try:
            await run_once()
        except Exception:
            log.exception("follow-up loop error")
        await asyncio.sleep(CHECK_EVERY_MIN * 60 - 60)

__EOF_TATWEER__

cat > requirements.txt <<'__EOF_TATWEER__'
fastapi>=0.110
uvicorn[standard]>=0.29
httpx>=0.27
anthropic>=0.40
python-dotenv>=1.0
tzdata>=2024.1

__EOF_TATWEER__

cat > Dockerfile <<'__EOF_TATWEER__'
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY *.py ./
ENV LEADS_FILE=/data/leads.json
VOLUME ["/data"]
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]

__EOF_TATWEER__

# ---- الإعدادات: المفاتيح السرية بتتكتب هنا بس، مش في الشات ----
if [ ! -f .env ]; then
  echo
  echo "==> الصق كل مفتاح ودوس Enter (الكتابة مش هتظهر على الشاشة)"
  read -rsp "WhatsApp Access Token: " WA_TOKEN; echo
  read -rsp "Meta App Secret: " APP_SECRET; echo
  read -rsp "Anthropic API Key: " ANT_KEY; echo
  VERIFY="tatweer-$(head -c 6 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  cat > .env <<EOF
WHATSAPP_PHONE_NUMBER_ID=1372337485958827
WHATSAPP_ACCESS_TOKEN=$WA_TOKEN
WHATSAPP_VERIFY_TOKEN=$VERIFY
META_APP_SECRET=$APP_SECRET
GRAPH_API_VERSION=v21.0
ANTHROPIC_API_KEY=$ANT_KEY
CLAUDE_MODEL=claude-sonnet-5-5
COMPANY_NAME=تطوير للخدمات العقارية
COMPANY_PHONE=01064753335
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
EOF
  chmod 600 .env
fi

# ---- قراءة إعدادات Traefik من موقع تطوير الشغال ----
REF=static-sites-tatweer-1
LABELS=$(docker inspect "$REF" --format '{{json .Config.Labels}}' 2>/dev/null || echo '{}')
RESOLVER=$(echo "$LABELS" | grep -o 'certresolver":"[^"]*' | head -1 | cut -d'"' -f3)
# نستخدم دايمًا مدخل HTTPS (Meta بتطلب https)
ENTRY=$(echo "$LABELS" | grep -o 'entrypoints":"[^"]*' | cut -d'"' -f3 | tr ',' '\n' | grep -m1 -i secure || true)
NET=$(docker inspect n8n-traefik-1 --format '{{range $k,$v := .NetworkSettings.Networks}}{{$k}} {{end}}' | awk '{print $1}')
RESOLVER=${RESOLVER:-mytlschallenge}; ENTRY=${ENTRY:-websecure}
echo "==> Traefik: network=$NET entrypoint=$ENTRY certresolver=$RESOLVER"

echo "==> بناء وتشغيل البوت"
docker build -q -t tatweer-wa-bot . >/dev/null
docker rm -f tatweer-wa-bot >/dev/null 2>&1 || true
docker run -d --name tatweer-wa-bot --restart unless-stopped \
  --env-file .env -v "$APP_DIR/data:/data" --network "$NET" \
  -l traefik.enable=true \
  -l "traefik.docker.network=$NET" \
  -l "traefik.http.routers.wabot.rule=Host(\`$DOMAIN\`)" \
  -l "traefik.http.routers.wabot.entrypoints=$ENTRY" \
  -l traefik.http.routers.wabot.tls=true \
  -l "traefik.http.routers.wabot.tls.certresolver=$RESOLVER" \
  -l traefik.http.services.wabot.loadbalancer.server.port=8000 \
  tatweer-wa-bot >/dev/null

sleep 4
if docker exec tatweer-wa-bot python -c "import urllib.request;print(urllib.request.urlopen('http://127.0.0.1:8000/health').read().decode())"; then
  echo
  echo "✅ البوت شغال."
  echo "Callback URL:  https://$DOMAIN/webhook"
  echo "Verify token:  $(grep WHATSAPP_VERIFY_TOKEN .env | cut -d= -f2)"
else
  echo "❌ البوت ما اشتغلش — شوف اللوج:"; docker logs --tail 40 tatweer-wa-bot
fi
