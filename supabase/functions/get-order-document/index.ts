// YeboSell — get-order-document edge function
// Anon buyers (track_token only) can't read the private payment-proofs bucket
// directly. This validates that the requested document belongs to the order
// behind the token, then returns a short-lived signed URL. Deploy with
// --no-verify-jwt (anon-callable; the token + document ownership are the auth).
//
// POST { token, document_id }  ->  { url }
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method" }, 405);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad_json" }, 400); }
  const { token, document_id } = body || {};
  if (!token || !document_id) return json({ error: "bad_request", message: "Missing token or document" }, 400);

  // The document must belong to the order behind this token.
  const { data: doc, error } = await admin
    .from("order_documents")
    .select("storage_path, orders!inner(track_token)")
    .eq("id", document_id)
    .eq("orders.track_token", token)
    .maybeSingle();
  if (error || !doc) return json({ error: "notfound", message: "Document not found" }, 404);

  const signed = await admin.storage.from("payment-proofs").createSignedUrl(doc.storage_path, 3600);
  if (signed.error || !signed.data) return json({ error: "sign", message: "Could not open the file" }, 500);

  return json({ url: signed.data.signedUrl });
});
