# YeboSell — Progress Log
**Updated:** 16 June 2026
**Live site:** https://yebosell.co.za
**GitHub:** https://github.com/EhsanRiz/yebosell (main)
**Supabase project:** `nizrqwvfuxbuhertypva`
**Cloudflare Worker:** `yebosell` (auto-deploys from GitHub `main` via Cloudflare Git integration)

---

## 🎯 PICK UP HERE (start of next session)

The product is **functionally complete and end-to-end tested** for a **Lesotho-first launch**. Remaining work is launch hygiene + optional deeper testing, not new features.

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

**Security (Stage 3b):** full RLS lockdown. Orders/order_items/payments/platform_fees/notification_log/login-events/admin tables are owner + `is_platform_admin()` only; secrets/OTP tables are deny-all (reached only via SECURITY DEFINER RPCs). Verified: anon clients read nothing sensitive; public checkout/tracking still work.

**Admin user-management:** seller drill-down (orders, GMV, products, fees, last login, login activity), reset PIN, suspend/deactivate/reactivate, Activity tab (login audit + admin-action audit), seller CSV export. All writes go through guarded RPCs and are logged to `admin_actions`.

**Currency:** Maloti (**M**) app-wide (`formatCurrency`); landing page is geo-aware (Maloti for Lesotho, ZAR for SA visitors).

---

## SESSION WORK (June 2026)

- **WhatsApp-free tracking** — `track_token` + `get_tracked_order` RPC, buyer PWA (manifest/service worker/icons), click-to-chat buyer templates (EN+Sesotho), phone-sync + "My Orders".
- **Hardened seller auth** — bcrypt PIN in `seller_secrets`, OTP register/login/forgot-PIN RPCs, rate limiting, optional email; real Supabase phone-OTP sessions + PIN unlock.
- **Stage 3b RLS lockdown** — closed all sensitive tables; routed public flows through SECURITY DEFINER RPCs; verified with a true anon client.
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

**Launch hygiene (do first):** clean test/demo data · enable leaked-password protection · confirm fee values · rotate GitHub PAT.

**Hardening / cleanup (low priority):** delete dormant `whatsapp-notify`/`whatsapp-webhook` edge functions · `REVOKE EXECUTE` on `admin_*` RPCs from `anon` (defense-in-depth; they already self-guard) · normalize buyer phone to E.164 on store in `create_storefront_order` · pin `search_path` on remaining non-definer functions.

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
