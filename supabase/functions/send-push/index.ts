// YeboSell — send-push edge function (Web Push / Phase 2)
// Invoked by the push_on_message DB trigger (pg_net) on every non-buyer order
// message. Fans out a web-push notification to every device subscribed to that
// order's track_token. Custom-authed via the x-push-key header (no Supabase
// JWT), so deploy with --no-verify-jwt.
//
// Secrets live in public.private_config (service-role only), NOT in env:
//   vapid_private_key, vapid_public_key, vapid_subject, push_shared_secret
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected by Supabase.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

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

async function config(): Promise<Record<string, string>> {
  const { data } = await admin.from("private_config").select("key,value");
  const out: Record<string, string> = {};
  (data || []).forEach((r: { key: string; value: string }) => { out[r.key] = r.value; });
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const cfg = await config();

  // Custom auth: shared secret from the trigger.
  if (!cfg.push_shared_secret || req.headers.get("x-push-key") !== cfg.push_shared_secret) {
    return json({ error: "unauthorized" }, 401);
  }
  if (!cfg.vapid_private_key || !cfg.vapid_public_key) return json({ error: "no_vapid" }, 500);

  let body: { order_id?: string; sender?: string; kind?: string; preview?: string; audience?: string; event?: string } = {};
  try { body = await req.json(); } catch { /* ignore */ }
  if (!body.order_id) return json({ error: "no_order" }, 400);

  // Resolve order → token, order number, seller.
  const { data: ord } = await admin
    .from("orders")
    .select("track_token, order_number, seller_id, customer_name, sellers(business_name)")
    .eq("id", body.order_id)
    .maybeSingle();
  if (!ord) return json({ error: "no_order_row" }, 200);

  const token = ord.track_token as string;
  // deno-lint-ignore no-explicit-any
  const sellerName = ((ord as any).sellers?.business_name as string) || "Seller";
  const preview = (body.preview || "").trim();
  const toSeller = body.audience === "seller";

  // Pick recipients + payload by audience.
  let subs: Array<{ endpoint: string; keys: { p256dh: string; auth: string } }> | null = null;
  let payload: string;

  if (toSeller) {
    if (!ord.seller_id) return json({ sent: 0 });
    const { data } = await admin
      .from("push_subscriptions")
      .select("endpoint, keys")
      .eq("seller_id", ord.seller_id);
    subs = data as typeof subs;
    const title = body.event === "new_order" ? "New order received" : (ord.order_number || "New message");
    const text = body.event === "new_order"
      ? `${preview || "A buyer"} placed order ${ord.order_number || ""}`.trim()
      : `${preview || "New message"}`;
    payload = JSON.stringify({ title, body: text, url: "/dashboard/", tag: `seller-${body.order_id}` });
  } else {
    if (!token) return json({ error: "no_token" }, 200);
    const { data } = await admin
      .from("push_subscriptions")
      .select("endpoint, keys")
      .contains("tokens", [token]);
    subs = data as typeof subs;
    const title = ord.order_number || "Your order";
    const text =
      body.kind === "status" ? (preview || "Order status updated")
      : body.sender === "admin" ? `YeboSell Support: ${preview}`
      : `${sellerName}: ${preview || "New message"}`;
    payload = JSON.stringify({ title, body: text, url: `/track/?t=${token}`, tag: `order-${token}` });
  }

  if (!subs || !subs.length) return json({ sent: 0 });

  webpush.setVapidDetails(cfg.vapid_subject || "mailto:support@yebosell.co.za", cfg.vapid_public_key, cfg.vapid_private_key);
  let sent = 0;
  const dead: string[] = [];
  await Promise.all((subs as Array<{ endpoint: string; keys: { p256dh: string; auth: string } }>).map(async (s) => {
    try {
      await webpush.sendNotification({ endpoint: s.endpoint, keys: s.keys }, payload);
      sent++;
    } catch (e) {
      // deno-lint-ignore no-explicit-any
      const code = (e as any)?.statusCode;
      if (code === 404 || code === 410) dead.push(s.endpoint);
    }
  }));
  if (dead.length) await admin.from("push_subscriptions").delete().in("endpoint", dead);

  return json({ sent, pruned: dead.length });
});
