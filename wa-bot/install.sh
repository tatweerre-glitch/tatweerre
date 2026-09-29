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
import whatsapp  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("wa-bot")

VERIFY_TOKEN = os.getenv("WHATSAPP_VERIFY_TOKEN", "")

app = FastAPI(title="Tatweer WhatsApp Agents")

# Meta ممكن تبعت نفس الرسالة أكتر من مرة — نمنع الرد المكرر
_seen_ids: deque = deque(maxlen=2000)


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
    """آخر ١٠ رسائل لكل عميل — بتتقري وتتكتب في قاعدة البيانات."""
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


async def handle_message(phone: str, name: str, text: str, from_ad: bool = False) -> str:
    """نقطة الدخول: رسالة واحدة ← رد واحد."""
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
    if routing.get("needs_human"):
        await notify_team(phone, name, text, routing)
    return reply


async def notify_team(phone: str, name: str, text: str, routing: dict) -> None:
    """ينبّه الفريق على تليجرام لما عميل يحتاج موظف (بيستخدم البوت اللي عندك)."""
    token, chat_id = os.getenv("TELEGRAM_BOT_TOKEN"), os.getenv("TELEGRAM_CHAT_ID")
    if not (token and chat_id):
        return
    import httpx
    msg = (f"🔥 عميل محتاج متابعة ({routing.get('qualification')})\n"
           f"الاسم: {name or '-'}\nالرقم: +{phone}\nالنية: {routing.get('intent')}\nآخر رسالة: {text}")
    async with httpx.AsyncClient(timeout=10) as c:
        await c.post(f"https://api.telegram.org/bot{token}/sendMessage", json={"chat_id": chat_id, "text": msg})

__EOF_TATWEER__

cat > requirements.txt <<'__EOF_TATWEER__'
fastapi>=0.110
uvicorn[standard]>=0.29
httpx>=0.27
anthropic>=0.40
python-dotenv>=1.0

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
