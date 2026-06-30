// YeboSell — send-push edge function (Web Push)
// buyer (default): notify devices subscribed to the order's track_token.
// seller (audience='seller'): notify the store's own devices. event in
//   {new_order, message(default), fee_warning, fee_suspended}.
// Custom-authed via x-push-key (no JWT) -> --no-verify-jwt.
// Secrets in public.private_config: vapid_*, push_shared_secret. SUPABASE_* auto-injected.
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

// deno-lint-ignore no-explicit-any
async function fanout(subs: any[] | null, payload: string) {
  let sent = 0;
  const dead: string[] = [];
  await Promise.all((subs || []).map(async (s) => {
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
  return { sent, pruned: dead.length };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  const cfg = await config();
  if (!cfg.push_shared_secret || req.headers.get("x-push-key") !== cfg.push_shared_secret) {
    return json({ error: "unauthorized" }, 401);
  }
  if (!cfg.vapid_private_key || !cfg.vapid_public_key) return json({ error: "no_vapid" }, 500);

  // deno-lint-ignore no-explicit-any
  let body: any = {};
  try { body = await req.json(); } catch { /* ignore */ }
  if (!body.order_id) return json({ error: "no_order" }, 400);

  webpush.setVapidDetails(cfg.vapid_subject || "mailto:support@yebosell.co.za", cfg.vapid_public_key, cfg.vapid_private_key);
  const preview = (body.preview || "").trim();

  // ----- Seller audience: notify the store's own devices -----
  if (body.audience === "seller") {
    const { data: ord } = await admin
      .from("orders").select("seller_id, order_number").eq("id", body.order_id).maybeSingle();
    if (!ord || !ord.seller_id) return json({ error: "no_seller" }, 200);
    const num = ord.order_number || "Order";
    const { data: subs } = await admin
      .from("push_subscriptions").select("endpoint, keys").eq("seller_id", ord.seller_id);
    if (!subs || !subs.length) return json({ sent: 0 });
    let title: string, text: string, tag = `seller-${body.order_id}`;
    if (body.event === "new_order") {
      title = "New order received";
      text = `${preview || "A buyer"} placed order ${num}`;
    } else if (body.event === "fee_warning") {
      title = "Platform fees due";
      text = preview || "Settle your YeboSell fees to keep your store open.";
      tag = `fee-${ord.seller_id}`;
    } else if (body.event === "fee_suspended") {
      title = "Store paused — fees overdue";
      text = preview || "Settle your YeboSell fees to reactivate your store.";
      tag = `fee-${ord.seller_id}`;
    } else {
      title = `New message · ${num}`;
      text = preview || "New message from the buyer";
    }
    const payload = JSON.stringify({ title, body: text, url: "/dashboard/", tag });
    return json(await fanout(subs, payload));
  }

  // ----- Buyer audience (default): notify devices subscribed to this order -----
  const { data: ord } = await admin
    .from("orders").select("track_token, order_number, sellers(business_name)").eq("id", body.order_id).maybeSingle();
  if (!ord || !ord.track_token) return json({ error: "no_token" }, 200);

  const token = ord.track_token as string;
  // deno-lint-ignore no-explicit-any
  const sellerName = ((ord as any).sellers?.business_name as string) || "Seller";
  const title = (ord.order_number as string) || "Your order";
  const text =
    body.kind === "status" ? (preview || "Order status updated")
    : body.sender === "admin" ? `YeboSell Support: ${preview}`
    : `${sellerName}: ${preview || "New message"}`;

  const { data: subs } = await admin
    .from("push_subscriptions").select("endpoint, keys").contains("tokens", [token]);
  if (!subs || !subs.length) return json({ sent: 0 });

  const payload = JSON.stringify({ title, body: text, url: `/track/?t=${token}`, tag: `order-${token}` });
  return json(await fanout(subs, payload));
});
