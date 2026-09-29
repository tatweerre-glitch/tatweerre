# بوت واتساب — وكلاء تطوير للخدمات العقارية

يستقبل رسايل العملاء على واتساب، ويحللها بـ `planner-router`، ويرد بـ `real-estate-agent`،
ويسجل العميل بـ `crm-publisher` في `leads.json`، وينبّهك على تليجرام لو العميل "سخن" أو طلب يكلم حد.

## الملفات
| الملف | وظيفته |
|---|---|
| `main.py` | الـ Webhook نفسه (استقبال + تحقق من Meta) |
| `whatsapp.py` | التعامل مع WhatsApp Cloud API (توقيع، إرسال، علامة قراءة) |
| `agents.py` | الوكلاء والـ prompts وتسجيل العملاء |
| `.env.example` | الإعدادات — انسخه باسم `.env` |

## ١) تجهيز حساب Meta (مرة واحدة)
1. ادخل **developers.facebook.com** ← My Apps ← Create App ← نوع **Business**.
2. ضيف منتج **WhatsApp** للتطبيق، واربطه بحساب Business بتاع تطوير.
3. من **WhatsApp ← API Setup**: ضيف رقم الشركة، وخد **Phone Number ID**.
4. من **Business Settings ← System Users**: اعمل System User، وطلّع **توكن دائم**
   بصلاحيات `whatsapp_business_messaging` و`whatsapp_business_management`.
5. من **App Settings ← Basic**: خد **App Secret**.
6. ⚠️ **قبل ١ أكتوبر:** Business Settings ← Billing & payments ← ضيف وسيلة دفع على حساب واتساب.

## ٢) التشغيل على سيرفر Hetzner (Ubuntu)
```bash
sudo apt update && sudo apt install -y python3-pip python3-venv caddy
mkdir ~/wa-bot && cd ~/wa-bot        # ارفع الملفات هنا
python3 -m venv venv && source venv/bin/activate
pip install -r requirements.txt
cp .env.example .env && nano .env    # املا القيم
```

**HTTPS (مطلوب من Meta)** — اربط دومين أو ساب دومين (مثال `bot.tatweer.com`) بـ IP السيرفر، وبعدين:
```bash
echo 'bot.tatweer.com {
  reverse_proxy localhost:8000
}' | sudo tee /etc/caddy/Caddyfile
sudo systemctl restart caddy
```

**تشغيل دائم 24/7:**
```bash
sudo tee /etc/systemd/system/wa-bot.service > /dev/null <<EOF
[Unit]
Description=Tatweer WhatsApp Bot
After=network.target
[Service]
WorkingDirectory=$HOME/wa-bot
ExecStart=$HOME/wa-bot/venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
Restart=always
User=$USER
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now wa-bot
```
اختبر: `https://bot.tatweer.com/health` لازم يرجع `{"ok":true}`.

## ٣) تسجيل الـ Webhook في Meta
WhatsApp ← Configuration ← Webhook ← Edit:
- **Callback URL:** `https://bot.tatweer.com/webhook`
- **Verify token:** نفس قيمة `WHATSAPP_VERIFY_TOKEN` في `.env`
- بعد التأكيد، اشترك في حقل **messages**.

ابعت رسالة من موبايلك لرقم الشركة، والمفروض البوت يرد خلال ثواني.
اللوج: `journalctl -u wa-bot -f`

## ملاحظات مهمة
- **نافذة ٢٤ ساعة:** البوت يقدر يرد بحرية لحد ٢٤ ساعة من آخر رسالة من العميل.
  بعدها أي رسالة متابعة لازم تكون **Template** معتمد من Meta (هنضيفه في مرحلة "المتابعة التلقائية").
- العملاء الجايين من إعلانات Click-to-WhatsApp بيتعلّموا `from_ad: true` في `leads.json`.
- ذاكرة المحادثة حاليًا في الرام — بتتمسح لو السيرفر عمل restart. الخطوة الجاية: قاعدة بيانات.
- البوت ممنوع يذكر أرقام عمارات حقيقية، وبيستخدم كود الوحدة (MAF-…).

## المتابعة التلقائية (followup.py)
- **متابعة ١**: العميل ساكت من ١٨ ساعة وآخر رسالة كانت من البوت ← البوت يبعت رسالة قصيرة تكمّل الكلام (جوه نافذة الـ ٢٤ ساعة).
- **متابعة ٢**: بعد ٣ أيام ← Template معتمد لو `FOLLOWUP_TEMPLATE` متظبط في `.env`، وإلا تنبيه تليجرام للفريق.
- مفيش متابعة لعميل طلب موظف، أو قال "مش مهتم"، أو كان بيسلّم بس. ومفيش رسايل من ١٠ بالليل لـ ٩ الصبح (القاهرة).
- الحالة: `curl -fsSL https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/main/wa-bot/followups.sh | bash`
- إعدادات اختيارية في `.env`: `FOLLOWUP_ENABLED=0` للإيقاف، `FOLLOWUP1_HOURS`، `FOLLOWUP2_HOURS`، `FOLLOWUP_TEMPLATE`، `FOLLOWUP_TEMPLATE_LANG` (الافتراضي ar).

## لوحة العملاء (dashboard.py)
- الرابط: https://bot.tatweereg.tech/dashboard — المستخدم `tatweer` والباسورد `DASHBOARD_PASSWORD` في `.env`.
- تغيير الباسورد: `curl -fsSL -o p.sh https://raw.githubusercontent.com/tatweerre-glitch/tatweerre/main/wa-bot/set-dashboard-password.sh && bash p.sh`
- فيها: كل العملاء وحالتهم، فلاتر (محتاج موظف / ساخن / عليهم متابعة)، المحادثة كاملة، زرار واتساب واتصال، "تم التواصل"، إيقاف المتابعة، وتنزيل Excel.
