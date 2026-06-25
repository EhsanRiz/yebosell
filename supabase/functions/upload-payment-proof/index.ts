// YeboSell — upload-payment-proof edge function
// Buyers are anonymous (track_token only), so they can't write to storage
// directly. This validates the token -> order, then uploads the file into the
// PRIVATE payment-proofs bucket (service role) and records metadata. Deploy
// with --no-verify-jwt (anon-callable; token is the auth).
//
// POST { token, file_base64, content_type, file_name }
// SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY are auto-injected by Supabase.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  { auth: { persistSession: false } },
);

const EXT: Record<string, string> = {
  "image/jpeg": "jpg", "image/png": "png", "image/webp": "webp", "application/pdf": "pdf",
};
const MAX_BYTES = 5 * 1024 * 1024;

function b64ToBytes(b64: string): Uint8Array {
  const clean = b64.includes(",") ? b64.slice(b64.indexOf(",") + 1) : b64; // strip data: prefix
  const bin = atob(clean);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad_json" }, 400); }
  const { token, file_base64, content_type, file_name } = body || {};

  if (!token || typeof token !== "string") return json({ error: "badtoken", message: "Missing tracking token" }, 400);
  if (!EXT[content_type]) return json({ error: "badtype", message: "Only JPG, PNG, WebP or PDF files are allowed." }, 400);
  if (!file_base64 || typeof file_base64 !== "string") return json({ error: "nofile", message: "No file provided" }, 400);

  // token -> order
  const { data: order, error: oErr } = await admin
    .from("orders").select("id, seller_id").eq("track_token", token).maybeSingle();
  if (oErr || !order) return json({ error: "badtoken", message: "Order not found" }, 404);

  let bytes: Uint8Array;
  try { bytes = b64ToBytes(file_base64); } catch { return json({ error: "decode", message: "Could not read the file" }, 400); }
  if (bytes.length === 0) return json({ error: "empty", message: "The file is empty" }, 400);
  if (bytes.length > MAX_BYTES) return json({ error: "toobig", message: "File is too large (max 5MB)." }, 400);

  const path = `${order.id}/${crypto.randomUUID()}.${EXT[content_type]}`;
  const up = await admin.storage.from("payment-proofs").upload(path, bytes, { contentType: content_type, upsert: false });
  if (up.error) return json({ error: "upload", message: up.error.message }, 500);

  const { data: row, error: iErr } = await admin.from("order_documents").insert({
    order_id: order.id, seller_id: order.seller_id, storage_path: path, doc_type: "payment_proof",
    content_type, file_name: (typeof file_name === "string" ? file_name.slice(0, 200) : null), source: "buyer",
  }).select("id").single();
  if (iErr) {
    // best-effort cleanup so we don't leave an orphan object
    try { await admin.storage.from("payment-proofs").remove([path]); } catch (_) {}
    return json({ error: "record", message: iErr.message }, 500);
  }

  // Surface it to the seller: post a buyer message so their bell, order thread
  // and unread badge all light up. sender='buyer' on purpose — that's what the
  // seller's bell counts, and it avoids push-notifying the buyer about their
  // own upload (the push trigger only fires for non-buyer messages).
  try {
    await admin.from("order_messages").insert({
      order_id: order.id, seller_id: order.seller_id, sender: "buyer", kind: "message",
      body: "📎 Uploaded proof of payment" + (typeof file_name === "string" ? ": " + file_name.slice(0, 120) : ""),
      meta: { proof: true, proof_id: row.id, file_name: (typeof file_name === "string" ? file_name.slice(0, 200) : null) },
    });
  } catch (_) { /* non-fatal: the proof is saved regardless */ }

  return json({ ok: true, id: row.id });
});
