# YeboSell — Progress Log
**Updated:** 30 June 2026
**Live site:** https://yebosell.co.za
**GitHub:** https://github.com/EhsanRiz/yebosell (main)
**Supabase project:** `nizrqwvfuxbuhertypva`
**Cloudflare Worker:** `yebosell` (auto-deploys from GitHub `main` via Cloudflare Git integration)

---

## 🎯 PICK UP HERE (start of next session)

The product is **functionally complete and end-to-end tested** for a **Lesotho-first launch**. Remaining work is launch hygiene + optional deeper testing, not new features.

> ✅ **2026-06-30 — Stage 6: delivery ETA, store-coded orders, buyer cancellation, seller push+SMS, fee-policy v2 (first-10 trial), user agreements with e-signatures + signed PDFs, and a Playwright + CI harness.** A large pilot-prep cycle:
> - **Delivery ETA.** `products.lead_time_days` + `sellers.default_lead_time_days` (Settings) → `orders.eta_date` via `tg_set_order_eta`; storefront shows "Ready in ~N days", track shows an ETA banner. Seller revising the timeline auto-notifies the buyer (bell + message), and the **change reason is mandatory**. ⚠️ `sellers` uses **column-level grants** — adding a column to an anon `select` **breaks the whole anon query** until you `grant select (col) on sellers to anon` (this bit us; storefront went blank).
> - **Store-coded order numbers.** `make_order_code(name)` → per-seller code (e.g. `SS`), `tg_set_order_number` formats `CODE-YYMMDD-NN` with a per-day counter. Backfilled.
> - **Buyer order cancellation.** `buyer_cancel_order(token, reason)` — cancellable until out-for-delivery/delivered; restores variant-aware stock; posts a buyer message. The Cancel button **stays visible past the cut-off** with an explanatory message (doesn't disappear). Variant color/size now persisted on `order_items`.
> - **Seller-side Web Push + SMS.** `send-push` extended with a seller branch (`audience='seller'`, events `new_order`/`message`/`fee_warning`/`fee_suspended`); triggers `push_seller_new_order` / `push_seller_buyer_message`. New **`send-sms`** Edge Function (BulkSMS, custom-authed via `x-push-key`, `--no-verify-jwt`; trigger passes `Authorization: Bearer <anon>` because the dashboard deploy left `verify_jwt=true`). Fee warning + suspension fire push **and** SMS, once per crossing (`sellers.fee_warned_at`, cleared on settle).
> - **Fee policy v2.** Kept 5%/order but lowered the ceiling (sellers were selling thousands before any fee = default risk): **warn at M100 outstanding (~M2,000 sales), suspend at M125 (~M2,500 sales)** — `platform_config.warning_threshold`; `seller_account_status` returns `fee_state` (ok/warning/suspended). Warning is notify-only. **First-10-sellers trial:** the "first 10 paid orders free" now applies only to the **first 10 genuine sellers** (per-seller `fee_trial_eligible`, granted at registration while <10 slots taken; demo/internal excluded; backfilled HelpSell). Joiners 11+ pay from order 1. Verified via SQL: non-eligible charged 5% on order 1, eligible free within trial.
> - **User agreements + electronic signatures + signed PDFs.** Terms page expanded to **20 sections** (added Eligibility & Capacity, Electronic Acceptance & Signature, Cancellations & Refunds, Privacy & Data Protection; rewrote "WhatsApp Communication" → **Communications**: in-app chat + SMS + WhatsApp click-to-chat; binding buyer-payment language; support contact). **Sellers** sign once via a **blocking modal** (name + place of signing → `seller_accept_terms`; gated on `account.termsVersion !== TERMS_VERSION`), with a signed **PDF** (jsPDF) downloaded at signing and re-downloadable from Settings; an **× / "Don't agree" exit** returns them to the website (stays signed in). **Buyers** sign per order at checkout (name = signature + place; required checkbox; order stamped with `buyer_terms_version` + `buyer_signed_place`), with a signed PDF on the confirmation screen and re-download on `/track`. `TERMS_VERSION='2026-06-30'` (must match in dashboard + shop). Migrations: `20260630_user_agreements.sql`, `20260630_seller_terms_signature.sql`, `20260630_buyer_terms_signature.sql`, plus the fee ones. **Gotcha:** adding a defaulted trailing param to `create_storefront_order`/`seller_accept_terms` creates an **ambiguous overload** — drop the prior signature.
> - **Playwright + GitHub Actions CI.** E2E harness in `tests/` (local static server serving the repo root; auto-detects the env's pre-installed Chromium). Static-page tests (terms/landing/privacy) run **offline**; React-page tests (dashboard/shop/track + a non-mutating checkout-signing check) need network and **self-skip** when CDNs are blocked. `.github/workflows/e2e.yml` runs the full suite on push/PR (runners have open network, so React tests actually execute against a **demo store** — no real data). Sandbox run: **6 passed, 4 skipped**.
> - **Also this cycle:** multi-bank EFT (`bank_details.accounts[]`), Settings "Download YeboSell" install card + two-app split, mobile UX (keyboard dismiss on tap-away, Report-Payment / Add-Edit-Product / Create-Order / Discount as responsive popups, bell no longer falls off-screen), login footer matched to the website, low-stock alert no longer flags never-stocked (0-from-start) variants, "Saved" filter + seller like-counts (amber heart), Top-Rated sort TDZ fix. **YeboSell support/WA line: +266 5729 9369** (sellers + buyers); admin line 5630 0091.
> - **Network reality (unchanged):** this sandbox **403-blocks `yebosell.co.za`** and tunnels-blocks the CDNs, so live-site/UI verification must happen on-device or via CI. Backend was verified with SQL against prod throughout.

> ✅ **2026-06-24 (later) — Stage 5: unified order lifecycle, proof-of-payment, shared Documents hub, notify-on-upload, admin re-lock.** Built on the Stage 4 messaging/push base:
> - **Unified order lifecycle (one stage, buyer = seller).** Collapsed the split `status` + `delivery_status` into a single, delivery-method-aware progression shown identically on both sides: **New → Confirmed → Preparing → (Ready for Pickup | Out for Delivery) → Delivered** (+ Cancelled). Step 4 adapts to the order's method — pickup orders never show "Out for Delivery" and vice-versa. Payment stays its own badge. `config.js` `window.orderStages(method)` + `ORDER_STAGE_LABELS` are the single source of truth (cache bumped **v=11 → v=12** across shop/dashboard/admin/track). Dashboard dropped the separate Delivery column/dropdown; track timeline driven by `order.status`. Migration `20260624_unify_order_status_lifecycle.sql` widened the `status` CHECK and backfilled all 27 orders to the furthest-along stage. `delivery_status` column kept (vestigial; eventual cleanup).
> - **Proof of payment + shared Order Documents hub.** A per-order **Documents hub** both parties open anytime — proof of payment (buyer), receipts/invoices & delivery proof (seller). Private `payment-proofs` bucket; table `order_documents` (`doc_type`); buyer reaches storage only via token-validated Edge Functions (`upload-payment-proof` to write, `get-order-document` for a short-lived signed URL), seller via storage RLS + `createSignedUrl` and an owner INSERT policy. RPC `get_order_documents(token)`. Migrations `20260624_payment_proofs.sql` + `20260624_order_documents_hub.sql`. UI: `📁 Order Documents` card on `/track`, `Order Documents` section in the dashboard order modal. **Strengthens dispute protection** — one shared evidence trail (proofs + delivery proof) both sides and a future admin console can reference.
> - **Notify the seller on document upload.** A buyer proof upload now also posts a buyer `order_message`, so the seller's bell / live thread / unread badge light up (was previously silent).
> - **Security: re-locked admin RPC grants.** `admin_*` RPCs had drifted back to PUBLIC EXECUTE (a `create or replace function` resets grants to PUBLIC — recurring gotcha), so anon could call them again (they self-guard via `is_platform_admin()` but shouldn't be anon-reachable). Revoked PUBLIC/anon, kept `authenticated`; also stripped direct EXECUTE from trigger functions (`tg_*`). Verified seller-context order updates still fire triggers (EXECUTE is checked at `CREATE TRIGGER`, not at firing). Migration `20260624_relock_admin_rpc_grants.sql`. **Lesson: re-apply grants after any `create or replace` of a sensitive RPC; run `get_advisors` periodically.**
> - Edge functions: `upload-payment-proof`, `get-order-document` (both `verify_jwt:false`, token-authed). All migrations applied + functions deployed to prod; both React pages JSX-validated. *(Upload/view round-trips still want an on-device check — the sandbox can't reach `*.supabase.co/functions`.)*

> ✅ **2026-06-24 — Stage 4: two-sided order messaging + realtime + Web Push (built, deployed, real-device tested).** Closed the loop on in-app buyer↔seller communication. The seller dashboard already had a conversation thread, but the buyer side was a dead end — the buyer couldn't see or reply to seller messages. Now shipped end-to-end:
> - **Buyer chat on `/track`** — a "Messages" thread under the order timeline, via token-scoped SECURITY DEFINER RPCs (`get_order_thread` / `post_order_message` / `mark_thread_read_buyer`); anon buyers never touch the table directly.
> - **Notification bells, both sides.** Dashboard bell fixed (dropdown no longer overflows off-screen in the left sidebar — added an `align` prop) and made **persistent**: counts are DB-derived (buyer msg unread until seller opens the thread / new order until it leaves `new` status / age-out after 4 days), so they survive refresh instead of clearing on open. New **buyer cross-order bell** aggregates unread across every saved order via `buyer_unread_summary(tokens[])`.
> - **#1 Realtime (instant while app open).** Anon buyers can't hold Postgres-changes subscriptions, so a DB trigger broadcasts a content-free ping on the public topic `order-rt:<track_token>`; the buyer thread + bell subscribe and refetch instantly. Polling remains as fallback. **Verified live on a real Android device — message popped in with no refresh.**
> - **#2 Web Push (reaches a closed/locked phone — the real WhatsApp substitute).** `push_subscriptions` + `register_push_subscription` RPC; `send-push` Edge Function (web-push + VAPID) fanned out by a `push_on_message` trigger via `pg_net`; service-worker `push`/`notificationclick` handlers; "Enable notifications" prompt; dead endpoints auto-pruned (404/410). **Verified end-to-end on real Android — push landed on the lock screen; server returned `{sent:1,pruned:1}`.** VAPID private key + push shared secret live in the `private_config` table (out-of-band, **never committed**).
> - Migrations: `20260619_stage4a_internal_messaging.sql`, `20260624_stage4b_buyer_confirmation.sql`, `20260624_buyer_unread_summary.sql`, `20260624_broadcast_order_messages.sql`, `20260624_web_push_infrastructure.sql`. Edge function: `supabase/functions/send-push/`. Spec: `SPEC_internal_messaging.md` (Phase 1 + bell §7a + realtime §5 done; Phase 2 push done).
> - **Honest positioning (answers "why still WhatsApp?"):** in-app push only reaches buyers who **install/open the PWA and grant permission** (iOS needs PWA-install, 16.4+, and is flaky). WhatsApp stays the **delivery-guarantee backbone** for one-off buyers who don't opt in. The hybrid is deliberate; **gate any reduction of WhatsApp on measured push-adoption %.**
> - **Cloudflare/proxy gotcha noted:** this sandbox's egress policy **403-blocks `yebosell.co.za`**, so I cannot `curl`-verify the live site from here — deploy state must be confirmed from the Cloudflare dashboard or by the user. (Cost me a long false "deploy stuck" detour.) Cloudflare did deploy normally each time.

> ✅ **2026-06-17 — critical RLS gap found, fixed & DEPLOYED (Stage 3c).** Stage 3b did **not** cover everything: 10 tables (`sellers`, `platform_config`, `products`, `discount_codes`, `customers`, `deliveries`, `product_reviews`, `buyer_wishlists`, `seller_settlements`, `webhook_message_log`) still had `USING (true)` policies **and full DML granted to `anon`**. Verified live: with only the public anon key, anyone could update platform fees, overwrite any seller's row (incl. bank_details), read every seller's contact details, and forge settlements/discounts. **Migration `20260617_stage3c_rls_close_remaining_tables.sql` is now applied to prod** (writes → owner/admin; sensitive seller columns hidden via column grants; checkout's stock/discount writes moved server-side into `create_storefront_order`). Frontend (shop+admin) is live on `main`/Cloudflare. **Verified post-deploy:** anon can no longer UPDATE platform_config/sellers or read bank_details/email; storefront reads + anon checkout (with server-side stock decrement) still work; Supabase advisor `rls_policy_always_true` warnings dropped 11 → 1 (the remaining one is the intentional public review-submission INSERT). Backfill linked 2 existing sellers (Ehsan, MyShop); the rest self-link on next OTP login.

> ✅ **2026-06-17 — Stage 3d hardening (applied + deployed).** Follow-up defense-in-depth: revoked `anon` EXECUTE on all `admin_*` RPCs (still callable by the admin's authenticated session; they also self-guard via `is_platform_admin()`); pinned `search_path` on `generate_order_number`; and locked the `product-photos` storage bucket — its INSERT/UPDATE/DELETE were granted to **PUBLIC (anon)**, so anyone with the anon key could delete/overwrite/upload product images. Writes are now `authenticated`-only and the broad public-listing SELECT policy is dropped (bucket is public, so `getPublicUrl` display is unaffected). Also fixed 4 `wa.me` click-to-chat links (shop ×3 + track ×1) that used raw `phone.replace(/[^0-9]/g,'')` and dropped the country code — now via `window.waNumber()` (CLAUDE.md rule #5).

> 🗣️ **2026-06-17 — landing narrative repositioned (deployed).** Moved off the WhatsApp-centric story to: **"build your own online store in a few simple steps — for sellers on WhatsApp, Facebook & Instagram."** WhatsApp is now framed as one channel you share to + the one-tap buyer-update mechanism, not the platform. Removed the inaccurate "automatic WhatsApp notifications" / "no manual messaging" claims (hero, FAQ, testimonial) — notifications are one-tap click-to-chat from the seller's own number. Also forced Maloti for all visitors (stopped the SA geo M→R swap) and fixed a stray hardcoded "R" in the dashboard discounts tab. **TODO (manual):** regenerate `assets/og-image.png` by running `python3 scripts/og-image.py` on a machine with Pillow (the live share-card image still shows the old "WhatsApp-Powered Commerce" subtitle; the script is updated + now cross-platform).

> 🛠️ **2026-06-17 — Stage 3e: product actions fixed (deployed).** Real seller testing surfaced that the Stage 3b/3c lockdown broke product CRUD + photo upload for **PIN-only logins**: Phone+PIN (`seller_login`) verifies the PIN but creates **no Supabase session**, so writes went out as `anon` → "permission denied for table products" / "violates row-level security policy". Fixes: (1) dashboard now **requires an active Supabase session** for the dashboard — PIN login with no session triggers a one-time SMS-OTP "activate this device" step, and a stale `localStorage` seller no longer enters a write-disabled dashboard; (2) `product-photos` bucket now allows jpeg/png/webp/**avif**/gif and a **5MB** limit (matches the client; was 2MB + no avif → confusing upload failures); (3) `order_items.product_id` FK → **ON DELETE SET NULL** so a product that appears in past orders can be deleted (order history keeps its denormalised `product_name`). Migration `20260617_stage3e_smooth_product_actions.sql`. **Seller login reality: sellers must OTP once per device/session window; PIN is a device-unlock on top of a live session.**

**Do before onboarding real sellers:**
1. **Clean test/demo data** — decide whether to wipe the seed orders/sellers for clean launch metrics (the admin GMV currently reflects test data). Keep Naledi/Lineo as demo storefronts if desired.
2. **Enable leaked-password protection** — Supabase → Auth → Settings (relevant now that the admin uses a password).
3. **Confirm platform fee values** — currently 5% per order, seller auto-suspends at M500 outstanding.
4. **Rotate the GitHub PAT** that was used for pushes this cycle.

**Optional (untested corners):** seller Settings (pickup address/bank/bio), Discounts (create+apply), Payments tab, Templates, Forgot-PIN, buyer "My Orders" lookup, admin Fees settlement.

See `YeboSell_Launch_Readiness.md` and `YeboSell_E2E_Findings.md` (kept in the Cowork outputs folder, not in the repo) for detail.

---

## ⚠️ MAJOR PIVOT — WhatsApp-FREE model (supersedes all BSP/360Dialog plans)

The previous direction (WhatsApp Cloud API via a BSP — 360Dialog/Infobip — under the InnovaEarth entity) is **abandoned**. The prior WABA was permanently banned and re-registration was high-risk. YeboSell now needs **no WhatsApp Business API at all**:

- **Buyer notifications = click-to-chat.** The seller taps "Message" and their own WhatsApp opens with a pre-filled status message (EN + Sesotho templates). No API, no per-message cost, no WABA.
- **Order tracking = tokenized link + buyer PWA.** Each order gets a `track_token`; buyers open `/track/?t=…`, an installable PWA, to follow status. Also "My Orders" lookup by phone.
- **Seller auth OTP = BulkSMS** (not WhatsApp), via a Supabase Auth Send-SMS hook.

The dormant `whatsapp-notify` / `whatsapp-webhook` edge functions remain deployed but neutralized — safe to delete.

---

## CURRENT ARCHITECTURE

**Frontend:** single-file HTML pages (`index.html` landing, `dashboard/`, `shop/`, `admin/`, `track/`, `privacy/`, `terms/`). React 18 + in-browser Babel for the app pages; shared helpers on `window.*` in `assets/config.js`.

**CDN deps are PINNED** (a v8 Babel auto-update silently blanked every React page on 2026-06-16): React 18, supabase-js 2, **`@babel/standalone@7`**, **Tailwind `cdn.tailwindcss.com/3.4.16`**. Do not unpin. If a React page goes blank, check the Babel CDN version first.

**Backend:** Supabase Postgres. Public flows run through `SECURITY DEFINER` RPCs (checkout `create_storefront_order`, tracking `get_tracked_order`, seller auth `seller_login`/`seller_register`/`seller_reset_pin`, admin `admin_*`). Migrations recorded in `supabase/migrations/`.

**Auth & roles:**
- **Sellers** — Supabase phone-OTP session (BulkSMS) + bcrypt PIN device-unlock (`seller_secrets`). Register/forgot-PIN via OTP.
- **Admin** — a *pure admin* (not a seller). Identity in `public.admins`; `is_platform_admin()` checks that table. Admin logs in with **phone + password** (`signInWithPassword`); OTP only for set/forgot password. MyShop was retired.

**Security (Stage 3b + 3c):** RLS lockdown. Orders/order_items/payments/platform_fees/notification_log/login-events/admin tables are owner + `is_platform_admin()` only; secrets/OTP tables are deny-all (reached only via SECURITY DEFINER RPCs). **Stage 3c (2026-06-17)** then closed the remaining storefront/seller tables that Stage 3b had left wide open — see the Pick-Up-Here note. Net: anon can only read storefront-public data (active products, public seller columns, active discount codes, visible reviews) and write nothing directly; sellers write their own rows (`owns_seller`); admin via `is_platform_admin()`.

**Admin user-management:** seller drill-down (orders, GMV, products, fees, last login, login activity), reset PIN, suspend/deactivate/reactivate, Activity tab (login audit + admin-action audit), seller CSV export. All writes go through guarded RPCs and are logged to `admin_actions`.

**Currency:** Maloti (**M**) app-wide (`formatCurrency`); landing page is geo-aware (Maloti for Lesotho, ZAR for SA visitors).

---

## SESSION WORK (June 2026)

- **Stage 6 — pilot-prep cycle (2026-06-30)** — delivery ETA (lead times + `eta_date`, mandatory change-reason auto-notify); store-coded order numbers (`CODE-YYMMDD-NN`); buyer order cancellation (variant-aware stock restore, button stays past cut-off); seller-side Web Push + new `send-sms` (BulkSMS) for orders/messages/fee events; fee-policy v2 (warn M100/suspend M125 outstanding ≈ M2,000/M2,500 sales; **first-10-sellers** trial via `fee_trial_eligible`); **user agreements with electronic signatures + signed PDFs** (seller blocking modal w/ ×-decline; buyer per-order checkout signing; 20-section Terms incl. Communications/e-signature/cancellation/privacy clauses); multi-bank EFT; mobile UX popups + keyboard-dismiss; low-stock false-positive fix; **Playwright E2E + GitHub Actions CI**. See the Pick-Up-Here note.
- **Stage 5 — unified lifecycle + documents + hardening (2026-06-24)** — one method-aware order stage shown identically to buyer & seller (`window.orderStages`); proof-of-payment + shared `order_documents` hub (private bucket, token-validated buyer upload/view Edge Functions, seller upload via RLS); seller now notified on buyer upload; re-locked `admin_*`/`tg_*` grants that had drifted back to PUBLIC. See the Pick-Up-Here note.
- **Stage 4 — internal messaging + realtime + Web Push (2026-06-24)** — buyer↔seller order-scoped chat on `/track` (token-scoped RPCs), persistent + overflow-fixed dashboard bell, buyer cross-order bell (`buyer_unread_summary`), Supabase Realtime **Broadcast** for instant in-app updates (anon-safe `order-rt:<token>` topic), and **Web Push** (VAPID `send-push` Edge Function + `pg_net` trigger + service-worker handlers, secrets in `private_config`). **Real-device verified on Android: instant in-app + lock-screen push.** See the Pick-Up-Here note.
- **WhatsApp-free tracking** — `track_token` + `get_tracked_order` RPC, buyer PWA (manifest/service worker/icons), click-to-chat buyer templates (EN+Sesotho), phone-sync + "My Orders".
- **Hardened seller auth** — bcrypt PIN in `seller_secrets`, OTP register/login/forgot-PIN RPCs, rate limiting, optional email; real Supabase phone-OTP sessions + PIN unlock.
- **Stage 3b RLS lockdown** — closed orders/payments/fees/etc.; routed public flows through SECURITY DEFINER RPCs; verified with a true anon client. *(Did not cover all tables — see Stage 3c.)*
- **Stage 3c RLS lockdown (2026-06-17)** — closed the 10 tables Stage 3b missed (sellers/platform_config/products/discount_codes/customers/deliveries/product_reviews/buyer_wishlists/seller_settlements/webhook_message_log), each of which still allowed anon full DML. Writes scoped to owner/admin; sensitive seller columns (bank_details/email/auth_user_id) hidden via column-level grants; checkout stock + discount-usage writes moved server-side into `create_storefront_order`. Validated against prod in rolled-back transactions (anon blocked; owner/admin allowed; RPC decrements plain + variant stock correctly).
- **Pure-admin model** — `admins` table, `is_platform_admin()` repointed, `admin_session` RPC, MyShop retired, stale +27 admin row cleared.
- **Admin phone+password login** — OTP only for set/forgot (saves BulkSMS credits).
- **Admin user-management UI** — reset PIN, suspend/deactivate, drill-down, Activity audit, CSV; fixed Recent-Orders seller-name column; fixed fee settlement to record admin id.
- **Brand-tight redesign** — replaced emoji-as-icons with green/gold Lucide line icons (landing feature grid + demo steps, shop checkout/empty-states/status/badges); fixed inaccurate "automatic WhatsApp" copy → "Buyer Notifications".
- **CDN pinning** — Babel→@7, Tailwind→3.4.16 (fixed a site-wide blank-page outage).
- **Currency → Maloti (M)** across the app.
- **Critical bug fix** — notify-buyer WhatsApp link now uses the full international number via `window.waNumber()` (was sending local 8-digit with no country code).
- **First-login greeting** ("Welcome to YeboSell" vs "Welcome back") + **storefront setup nudge** (prompt for pickup address).
- **End-to-end tested** (buyer order→tracking, seller register→product→order→status→notify, admin actions→audit) — all core flows pass.

---

## OPEN FOLLOW-UPS

**Launch hygiene (do first):** clean test/demo data · **enable leaked-password protection** (Supabase Auth → still OFF per advisor) · confirm fee values · rotate GitHub PAT.

**Hardening / cleanup (low priority):** delete dormant `whatsapp-notify`/`whatsapp-webhook` edge functions · normalize buyer phone to E.164 on store in `create_storefront_order` · pin `search_path` on remaining non-definer functions · move the `pg_net` extension out of the `public` schema (minor advisor WARN) · drop the now-vestigial `orders.delivery_status` column (superseded by the unified `status`) · **re-apply RPC grants after any `create or replace` of a sensitive function** (it resets EXECUTE to PUBLIC — bit us twice on `admin_*`; run `get_advisors` periodically). *(Done 2026-06-24: re-locked `admin_*`/`tg_*` grants.)*

**Messaging / push / docs follow-ups:** **measure push-adoption %** (what fraction of buyers install the PWA + grant notifications) before reducing WhatsApp dependence — the data gate for the whole hybrid · iOS push needs PWA-install (16.4+) and is flaky — nudge install on iOS · localise auto status-update messages (EN/Sesotho) in the thread · admin **dispute-mediation console** (SPEC §7 Phase 3) — now higher-value with the shared `order_documents` evidence trail · optionally let the seller mark a payment proof "verified" / one-tap set `payment_status` → paid. *(Done 2026-06-24: targeted WhatsApp nudge for buyers without a push subscription.)*

**Engineering / safety:** *(2026-06-30: Playwright + GitHub Actions CI now in place — `tests/`, `.github/workflows/e2e.yml`.)* Still to deepen: the suite covers the Terms/static pages fully and React-page mounts + a non-mutating checkout-signing check, but the **authenticated seller flows** (agreement sign/decline, signed-PDF download, register→order→status→notify, admin drill-down) need a phone-OTP session and aren't automated yet — extend with a seeded/auth-bypass test seller. The single-file React+Babel pages remain large; lean on the JSX `@babel/standalone` gate + these E2E tests before pushes.

**Known minor (cosmetic):** admin action buttons use native `confirm()` dialogs · repo root `.md` files (this file, HANDOFF, SPECs) are web-served at yebosell.co.za/… — move out of web root if that matters.

**SA expansion (parked):** SA (+27) SMS OTP doesn't deliver (Sender-ID/WASPA rules). Don't onboard +27 sellers until resolved. Switch `formatCurrency` back to geo-aware or "R" when launching SA.

---

## CROSS-REPO REFERENCES

| What | Where |
|------|-------|
| YeboSell product code (this repo) | https://github.com/EhsanRiz/yebosell |
| Local YeboSell folder | `/Users/ehsanrizvi/Documents/Claude/Projects/YeboSell/` |
| InnovaEarth website (parent entity site) | https://github.com/EhsanRiz/innovaearth |
| Launch-readiness report | Cowork outputs: `YeboSell_Launch_Readiness.md` |
| E2E test findings | Cowork outputs: `YeboSell_E2E_Findings.md` |

> Note: the WhatsApp BSP / 360Dialog / InnovaEarth-WABA workstream from the April log is **superseded** by the WhatsApp-free model above.
