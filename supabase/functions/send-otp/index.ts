// YeboSell — send-otp edge function
// Sends a 6-digit verification code by SMS via BulkSMS (server-side; no WhatsApp API).
// Secrets required (set in Supabase → Edge Functions → Secrets):
//   BULKSMS_TOKEN_ID, BULKSMS_TOKEN_SECRET
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected by Supabase.
// Deploy: supabase functions deploy send-otp --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PROJECT_REF = "nizrqwvfuxbuhertypva";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

function b64urlDecode(s: string): string {
  s = s.replace(/-/g, "+").replace(/_/g, "/");
  while (s.length % 4) s += "=";
  return atob(s);
}

// Accept any valid JWT issued for THIS project (anon key etc.), regardless of
// which specific key string the function env happens to hold.
function tokenForThisProject(authz: string): boolean {
  try {
    const tok = authz.replace(/^Bearer\s+/i, "").trim();
    const parts = tok.split(".");
    if (parts.length < 2) return false;
    const payload = JSON.parse(b64urlDecode(parts[1]));
    return payload && payload.ref === PROJECT_REF;
  } catch (_e) {
    return false;
  }
}

function normalizePhone(raw: string): string {
  let p = (raw || "").replace(/[^\d+]/g, "");
  if (p.startsWith("+")) return p;
  if (p.startsWith("00")) return "+" + p.slice(2);
  if (p.startsWith("27")) return "+" + p;
  if (p.startsWith("266")) return "+" + p;
  if (p.startsWith("0")) return "+27" + p.slice(1); // SA local 0XXXXXXXXX
  if (p.length === 8) return "+266" + p; // Lesotho local
  return "+" + p;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  try {
    const authz = req.headers.get("Authorization") || "";
    if (!tokenForThisProject(authz)) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const phone = (body as { phone?: string }).phone;
    if (!phone) return json({ error: "phone required" }, 400);
    const to = normalizePhone(phone);

    const supa = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Rate limit: 45s cooldown + max 5 per hour per number
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { data: recent } = await supa
      .from("buyer_otps")
      .select("created_at")
      .eq("phone", to)
      .gte("created_at", since)
      .order("created_at", { ascending: false });
    if (recent && recent.length) {
      const last = new Date(recent[0].created_at).getTime();
      if (Date.now() - last < 45000) return json({ error: "Please wait a few seconds before requesting another code." }, 429);
      if (recent.length >= 5) return json({ error: "Too many code requests. Please try again later." }, 429);
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expires = new Date(Date.now() + 10 * 60 * 1000).toISOString();
    const { error: insErr } = await supa.from("buyer_otps").insert({ phone: to, otp_code: code, expires_at: expires });
    if (insErr) return json({ error: "Could not create code" }, 500);

    const id = Deno.env.get("BULKSMS_TOKEN_ID");
    const secret = Deno.env.get("BULKSMS_TOKEN_SECRET");
    if (!id || !secret) return json({ error: "SMS not configured (missing BulkSMS secrets)" }, 500);

    const smsRes = await fetch("https://api.bulksms.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Basic " + btoa(`${id}:${secret}`),
      },
      body: JSON.stringify({ to, body: `Your YeboSell verification code is ${code}. It expires in 10 minutes.` }),
    });
    if (!smsRes.ok) {
      const detail = await smsRes.text().catch(() => "");
      return json({ error: "Failed to send SMS", status: smsRes.status, detail: detail.slice(0, 300) }, 502);
    }
    return json({ ok: true, sent_to: to });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
