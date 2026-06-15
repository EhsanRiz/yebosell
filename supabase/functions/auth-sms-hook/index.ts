// Supabase Auth "Send SMS Hook" -> delivers the OTP via BulkSMS.
// Configure in Dashboard: Authentication -> Hooks -> Send SMS Hook -> this function URL:
//   https://nizrqwvfuxbuhertypva.supabase.co/functions/v1/auth-sms-hook
// Secrets required: SEND_SMS_HOOK_SECRET (the v1,whsec_... value Supabase generates for the hook),
//   plus BULKSMS_TOKEN_ID / BULKSMS_TOKEN_SECRET (already set).
// Deploy: supabase functions deploy auth-sms-hook --no-verify-jwt
import { Webhook } from "https://esm.sh/standardwebhooks@1.0.0";

Deno.serve(async (req: Request) => {
  try {
    const raw = await req.text();
    const secret = Deno.env.get("SEND_SMS_HOOK_SECRET") || "";
    let data: any;
    if (secret) {
      const wh = new Webhook(secret.replace("v1,whsec_", ""));
      const headers = Object.fromEntries(req.headers);
      data = wh.verify(raw, headers);
    } else {
      data = JSON.parse(raw);
    }

    const phoneRaw = data?.user?.phone || "";
    const otp = data?.sms?.otp || "";
    if (!phoneRaw || !otp) {
      return new Response(JSON.stringify({ error: { http_code: 400, message: "Missing phone or otp" } }), {
        status: 400, headers: { "Content-Type": "application/json" },
      });
    }
    const to = phoneRaw.startsWith("+") ? phoneRaw : "+" + phoneRaw;

    const id = Deno.env.get("BULKSMS_TOKEN_ID");
    const sec = Deno.env.get("BULKSMS_TOKEN_SECRET");
    if (!id || !sec) {
      return new Response(JSON.stringify({ error: { http_code: 500, message: "BulkSMS not configured" } }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    const smsRes = await fetch("https://api.bulksms.com/v1/messages", {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": "Basic " + btoa(`${id}:${sec}`) },
      body: JSON.stringify({ to, body: `Your YeboSell verification code is ${otp}. It expires in 10 minutes.` }),
    });
    if (!smsRes.ok) {
      const detail = await smsRes.text().catch(() => "");
      return new Response(JSON.stringify({ error: { http_code: 502, message: "SMS send failed", detail: detail.slice(0, 200) } }), {
        status: 200, headers: { "Content-Type": "application/json" },
      });
    }
    return new Response(JSON.stringify({}), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(JSON.stringify({ error: { http_code: 401, message: String(e) } }), {
      status: 401, headers: { "Content-Type": "application/json" },
    });
  }
});
