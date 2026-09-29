#!/usr/bin/env bash
# يقدّم Template المتابعة لميتا، ولو اتعتمد يشغّله في البوت. شغّله تاني في أي وقت عشان تشوف الحالة.
set -e
ENV=/opt/wa-bot/.env
RAW=https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/main/wa-bot
[ -f "$ENV" ] || { echo "❌ مفيش $ENV"; exit 1; }
export TOK=$(grep -m1 '^WHATSAPP_ACCESS_TOKEN=' "$ENV" | cut -d= -f2-)
export WABA=${WABA_ID:-2161026601120075}
export NAME=tatweer_followup

python3 - <<'PY' > /tmp/tpl_status
import json, os, urllib.request, urllib.error
tok, waba, name = os.environ["TOK"], os.environ["WABA"], os.environ["NAME"]
G = "https://graph.facebook.com/v21.0"
def call(url, data=None):
    req = urllib.request.Request(url, data=json.dumps(data).encode() if data else None,
                                 headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        return json.load(urllib.request.urlopen(req, timeout=30))
    except urllib.error.HTTPError as e:
        return json.load(e)
found = call(f"{G}/{waba}/message_templates?name={name}&fields=name,status,language,rejected_reason").get("data", [])
if not found:
    body = {
        "name": name, "language": "ar", "category": "MARKETING",
        "components": [
            {"type": "BODY",
             "text": "أهلًا {{1}} 👋 معاك فريق تطوير للخدمات العقارية. لسه بتدور على وحدة في مدينة الفردوس؟ لو حابب نكمل، رد علينا وهنبعتلك المتاح المناسب لطلبك.",
             "example": {"body_text": [["أحمد"]]}},
            {"type": "BUTTONS", "buttons": [
                {"type": "QUICK_REPLY", "text": "أيوه مهتم"},
                {"type": "QUICK_REPLY", "text": "مش مهتم دلوقتي"}]},
        ]}
    r = call(f"{G}/{waba}/message_templates", body)
    if "error" in r:
        print("ERROR", r["error"].get("error_user_msg") or r["error"].get("message"))
    else:
        print(r.get("status", "PENDING"))
else:
    t = found[0]
    print(t.get("status"), t.get("rejected_reason") or "")
PY
read -r STATUS REST < /tmp/tpl_status
case "$STATUS" in
  APPROVED)
    if grep -q "^FOLLOWUP_TEMPLATE=$NAME" "$ENV"; then
      echo "✅ الـ Template معتمد وشغال في البوت بالفعل."
    else
      sed -i '/^FOLLOWUP_TEMPLATE=/d' "$ENV"; echo "FOLLOWUP_TEMPLATE=$NAME" >> "$ENV"
      echo "✅ ميتا اعتمدت الـ Template — بشغّله في البوت دلوقتي..."
      curl -fsSL -o /root/install.sh "$RAW/install.sh" && bash /root/install.sh >/dev/null && \
        docker logs --tail 20 tatweer-wa-bot 2>&1 | grep "follow-up: on"
    fi ;;
  PENDING|IN_APPEAL) echo "⏳ الـ Template اتقدّم ومستني مراجعة ميتا (عادة من دقايق لساعات). شغّل نفس الأمر تاني بعدين." ;;
  REJECTED) echo "❌ ميتا رفضت الـ Template: $REST — ابعت الرسالة دي لـ Claude." ;;
  ERROR) echo "❌ خطأ من ميتا: $REST — ابعت الرسالة دي لـ Claude." ;;
  *) echo "الحالة: $STATUS $REST" ;;
esac
