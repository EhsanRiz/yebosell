// YeboSell — send-sms edge function (BulkSMS)
// Sends a transactional SMS. Custom-authed via x-push-key (the same shared secret
// as send-push, stored in public.private_config), so it can be invoked from DB
// triggers via pg_net. Deploy with --no-verify-jwt.
// Reuses the project BulkSMS secrets: BULKSMS_TOKEN_ID, BULKSMS_TOKEN_SECRET.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-push-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

function normalizePhone(raw: string): string {
  let p = (raw || "").replace(/[^\d+]/g, "");
  if (p.startsWith("+")) return p;
  if (p.startsWith("00")) return "+" + p.slice(2);
  if (p.startsWith("27")) return "+" + p;
  if (p.startsWith("266")) return "+" + p;
  if (p.startsWith("0")) return "+27" + p.slice(1);
  if (p.length === 8) return "+266" + p;
  return "+" + p;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const { data: cfg } = await admin.from("private_config").select("value").eq("key", "push_shared_secret").maybeSingle();
  const secret = cfg?.value;
  if (!secret || req.headers.get("x-push-key") !== secret) return json({ error: "unauthorized" }, 401);

  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* ignore */ }
  const to = normalizePhone(body.to || "");
  const msg = (body.body || "").trim();
  if (!to || to.length < 8 || !msg) return json({ error: "missing to/body" }, 400);

  const id = Deno.env.get("BULKSMS_TOKEN_ID");
  const sec = Deno.env.get("BULKSMS_TOKEN_SECRET");
  if (!id || !sec) return json({ error: "sms_not_configured" }, 500);

  const res = await fetch("https://api.bulksms.com/v1/messages", {
    method: "POST",
    headers: { "Content-Type": "application/json", "Authorization": "Basic " + btoa(`${id}:${sec}`) },
    body: JSON.stringify({ to, body: msg }),
  });
  if (!res.ok) {
    const detail = await res.text().catch(() => "");
    return json({ error: "sms_failed", status: res.status, detail: detail.slice(0, 200) }, 502);
  }
  return json({ ok: true, sent_to: to });
});
