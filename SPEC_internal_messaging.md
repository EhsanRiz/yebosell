# SPEC — Internal Messaging (buyer ↔ seller ↔ admin)

**Status:** Draft for review · **Author:** Claude Code session · **Date:** 2026-06-19
**Related:** `SPEC_whatsapp_free_tracking.md`, `SPEC_supabase_auth_migration.md`, `CLAUDE.md`

---

## 1. Goal & positioning

Add an **order-scoped messaging layer** inside YeboSell so buyers, sellers, and (for disputes) admins can communicate **without** relying on the seller's personal WhatsApp — while keeping WhatsApp click-to-chat as a **notification/nudge fallback**, not removing it.

**This is a hybrid, not a replacement.** The internal thread is the *system of record* (persisted, order-scoped, admin-visible). WhatsApp/SMS remain the *delivery guarantee* layer for buyers who haven't installed the PWA.

### Why (where it clearly wins)
- **Order-threaded context** — each conversation is tied to one order (items, status, total, track token). WhatsApp loses this.
- **Admin mediation** — admin can view a thread to resolve "not delivered" / "wrong item" disputes. Impossible with click-to-chat on personal numbers.
- **No personal-number exposure** — works even if the buyer has no WhatsApp; seller's private number stays private.
- **Cost & ownership** — ongoing conversation is ~free (vs per-SMS); history/analytics owned by YeboSell.
- **Builds on existing surfaces** — the `track/` buyer PWA, the seller dashboard, and Supabase Realtime already exist.

### The hard constraint (design around this)
YeboSell **buyers are mostly one-off, non-captive users** who live in WhatsApp (unlike a captive-user app such as Myskolo where everyone logs in regularly). An internal inbox is only as useful as its **notifications**. If a buyer isn't pinged, an internal message is *worse* than a WhatsApp message (which guarantees the notification). **Notification delivery is the make-or-break problem**, addressed in §6.

---

## 2. Identity model (the key architectural fact)

| Party | Auth today | Messaging access path |
|---|---|---|
| **Buyer** | **Unauthenticated.** Holds a per-order `track_token` (opens `/track/?t=…`). No Supabase session. | **SECURITY DEFINER RPCs keyed on `track_token`** (mirrors `get_tracked_order`). Never direct table access. |
| **Seller** | Supabase phone-OTP session; `owns_seller(seller_id)` / `auth.uid()`. | RLS on `messages` (owner) + authenticated Realtime. |
| **Admin** | Pure admin; `is_platform_admin()`. | RLS (read-all) for the dispute view; may post as `admin`. |

This asymmetry (anon buyer vs authenticated seller/admin) drives the RPC + Realtime design below. It mirrors the existing pattern: public/buyer flows go through `SECURITY DEFINER` RPCs (`get_tracked_order`, `create_storefront_order`), sensitive tables are RLS-locked to owner + admin.

---

## 3. Data model

```sql
create table public.order_messages (
  id            uuid primary key default gen_random_uuid(),
  order_id      uuid not null references public.orders(id) on delete cascade,
  seller_id     uuid not null references public.sellers(id) on delete cascade, -- denormalised for RLS/index speed
  sender        text not null check (sender in ('buyer','seller','admin')),
  body          text not null check (length(btrim(body)) between 1 and 2000),
  created_at    timestamptz not null default now(),
  read_by_buyer_at  timestamptz,
  read_by_seller_at timestamptz
  -- future: attachment_url text, reply_to uuid, is_hidden boolean (moderation)
);
create index on public.order_messages (order_id, created_at);
create index on public.order_messages (seller_id, created_at desc);
alter table public.order_messages enable row level security;
```

Unread counts are derived: buyer-unread = messages where `sender <> 'buyer'` and `read_by_buyer_at is null`; seller-unread symmetric.

---

## 4. Access control

### 4.1 RLS (sellers + admin only — buyers never touch the table directly)
```sql
-- Seller: their orders' threads. Admin: everything.
create policy om_select_owner on public.order_messages for select
  using ((select public.owns_seller(seller_id)) or (select public.is_platform_admin()));
create policy om_insert_owner on public.order_messages for insert
  with check (
    ((select public.owns_seller(seller_id)) and sender = 'seller')
    or ((select public.is_platform_admin()) and sender = 'admin')
  );
create policy om_update_read on public.order_messages for update   -- read receipts
  using ((select public.owns_seller(seller_id)) or (select public.is_platform_admin()))
  with check ((select public.owns_seller(seller_id)) or (select public.is_platform_admin()));
-- anon/authenticated have NO direct grants for buyer rows; buyers use RPCs (below).
```

### 4.2 Buyer RPCs (`SECURITY DEFINER`, keyed on the order's track token)
```sql
-- Read a thread (also marks seller/admin msgs as read-by-buyer)
create function public.get_order_thread(p_token text) returns jsonb ...   -- verifies token -> order, returns messages
-- Post as buyer (rate-limited; validates token, length)
create function public.post_order_message(p_token text, p_body text) returns jsonb ...
-- Mark read
create function public.mark_thread_read_buyer(p_token text) returns void ...
```
These resolve `order` from `track_token` exactly like `get_tracked_order`, insert with `sender='buyer'` and the order's `seller_id`, and enforce a per-token rate limit (reuse the `seller_login_attempts` pattern or a new `message_rate` table).

**Hardening:** `REVOKE EXECUTE` on these from `authenticated` is unnecessary (token-scoped), but keep them anon-callable only for what's needed. Validate `length(body)`, strip control chars, cap messages/minute per token.

---

## 5. Realtime delivery

Two different mechanisms because of the identity asymmetry:

- **Seller & admin (authenticated):** Supabase **Postgres Changes** subscription on `order_messages`, RLS-scoped (seller sees only owned rows). Drives live thread updates + unread badges in the dashboard / admin console.
- **Buyer (anon, token-only):** do **not** expose Postgres-changes to anon (can't safely RLS-scope an anon socket to one order). Instead use **Supabase Realtime *Broadcast*** on an ephemeral channel `order:<track_token>`:
  - When any message is posted (via RPC or seller insert), broadcast a lightweight `{ new_message: true }` ping to `order:<token>`.
  - The buyer's `/track` page subscribes to `order:<token>` and **refetches the thread via `get_order_thread(token)`** on ping. Broadcast carries no message content (no data leak); the DB+RPC remains the source of truth.
  - MVP fallback if broadcast is deferred: **poll** `get_order_thread` every ~5s while the thread is open + on tab focus.

---

## 6. Notifications (make-or-break)

Ranked by reliability; implement in this order:

1. **Seller → in-app** (easy): dashboard realtime + unread badge; seller is a recurring user, so this mostly "just works."
2. **Buyer Web Push** (Phase 2): if the buyer **installed the `track/` PWA**, register a push subscription (service worker already exists in `sw.js`). Send via a Supabase Edge Function with VAPID keys. Works well on Android/Chrome; iOS needs PWA install (16.4+) and is flakier. **This is the primary buyer channel.**
3. **WhatsApp/SMS fallback** for buyers who didn't install: keep the existing one-tap WhatsApp nudge ("New update on order *ORD-…* — open: /track/?t=…") for important messages; reserve **SMS** for critical/transactional only (cost). This preserves WhatsApp's delivery guarantee where push isn't available.

**Honest limitation:** for non-installed buyers, the internal thread is "check it when you open the track link." We mitigate with the WhatsApp nudge, but we should *not* market this as fully replacing WhatsApp until push adoption is proven.

---

## 7. UX surfaces

- **Buyer (`/track/?t=…`):** a "Messages" panel under the order timeline. Compose box, message list, unread indicator. Encourage **"Add to Home Screen"** to enable push (the PWA already prompts install).
- **Seller (dashboard → order detail):** a thread per order; global unread badge on the Orders nav; realtime. Quick replies / templates reuse the existing buyer-template system.
- **Admin (admin dash):** read-only thread viewer on the seller/order drill-down; ability to post as `admin` for mediation; flag/hide a message (moderation).

---

## 8. Moderation, privacy, retention
- **Moderation:** rate-limit posts (per token / per seller); `is_hidden` flag + admin hide; "report" action → admin queue.
- **Privacy/POPIA:** message content is personal data — RLS-locked to participants + admin; document retention (e.g., purge threads N months after order completion); include in privacy policy. No new PII beyond name/phone already stored on the order.
- **Abuse vectors:** buyers are anon-by-token — a leaked token exposes that one thread only (same blast radius as `get_tracked_order` today). Tokens are unguessable; consider expiring posting ability after the order is `delivered`/`cancelled` + grace period.

---

## 9. Phased rollout
- **Phase 0 — Spec sign-off** (this doc): confirm hybrid positioning + notification strategy.
- **Phase 1 — MVP:** `order_messages` table + RLS + buyer RPCs; thread UI on `/track` and seller order detail; seller realtime (Postgres changes) + buyer broadcast-or-poll; unread badges. **No push yet** — WhatsApp nudge covers buyer alerts. Test on the HelpSell test seller.
- **Phase 2 — Web Push:** PWA push subscription + Edge Function sender; buyer + seller push.
- **Phase 3 — Admin dispute console:** thread viewer, post-as-admin, hide/report, basic SLA view.
- **Phase 4 — polish:** attachments (reuse `product-photos`-style bucket with strict RLS), typing/read receipts, canned replies.

## 10. Open questions
1. Do we let buyers **start** a thread pre-order (product question), or only **after** an order exists (token-scoped)? Pre-order chat needs a different identity anchor (no order/token yet) — likely a Phase 4+ "store inbox" with its own design.
2. Push infra: self-host VAPID via Edge Function, or use a provider? (Cost vs. control.)
3. Retention window + whether admins can read *all* threads by default or only on dispute escalation (privacy trade-off).
4. Is reducing WhatsApp dependence a real goal, or is WhatsApp permanently the buyer-notification backbone? (Affects how much to invest in push.)

## 11. Recommendation
Build **Phase 1 MVP** behind the existing surfaces, keep WhatsApp as the nudge, and **gate further investment on measured push-adoption** (what % of buyers install the PWA and grant notifications). The admin-mediation value alone likely justifies the MVP; full WhatsApp replacement should be earned by data, not assumed.
