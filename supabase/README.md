# YeboSell — Supabase backend

Project ref: `nizrqwvfuxbuhertypva`

This folder version-controls the Supabase backend that powers the WhatsApp-API-free
tracking + phone-sync. These were applied live via the Supabase MCP; the files here are
the source of record.

## Edge functions
- **`functions/send-otp/`** — sends a 6-digit SMS code via BulkSMS (server-side).
  - Requires secrets `BULKSMS_TOKEN_ID` and `BULKSMS_TOKEN_SECRET` (set in
    Supabase → Edge Functions → Secrets). `SUPABASE_URL` / `SUPABASE_SERVICE_ROLE_KEY`
    are auto-injected.
  - Deploy: `supabase functions deploy send-otp --no-verify-jwt`
- **`whatsapp-notify` / `whatsapp-webhook`** — RETIRED (tombstoned to return 410).
  The product no longer uses the WhatsApp Cloud API. Safe to delete in the dashboard.
- **`data-deletion`** — vestigial Meta data-deletion endpoint (service-role; harmless).

## Migrations
- **`migrations/20260612_yebosell_whatsapp_free.sql`** — track_token column,
  `get_tracked_order`, `get_orders_by_otp`, `get_orders_by_phone`, and the Phase 3
  RLS hardening (lock down `buyer_otps`, enable RLS on `data_deletion_requests`).

## Known follow-up
`orders` / `order_items` / `products` still have an open `ALL/public/true` RLS policy
because auth is PIN-based (the seller dashboard queries as the anon role). Tightening
this safely needs an auth/RPC refactor — see the note at the bottom of the migration file.
