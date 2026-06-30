# CLAUDE.md — YeboSell

Operating guide for working in this repo. Read `progress.md` for current status/roadmap and `SPEC_*.md` for deeper design.

## What this is
YeboSell is an order-management web app for informal sellers in **Lesotho & South Africa** (Lesotho-first). Sellers get a storefront, order management, and buyer notifications **without** the WhatsApp Business API.

**WhatsApp-FREE model (important):** there is NO WABA/Cloud API/BSP. Buyer notifications are **click-to-chat** — the seller taps "Message" and their own WhatsApp opens with a pre-filled message. Order tracking is a **tokenized link** (`/track/?t=…`, an installable PWA). Seller OTP is **SMS via BulkSMS**, not WhatsApp. Ignore any older 360Dialog/Meta references; that path is abandoned. The `whatsapp-notify`/`whatsapp-webhook` edge functions are dormant.

## Stack
- Single-file pages: `index.html` (landing, static), and React-18 + in-browser Babel pages `dashboard/`, `shop/`, `admin/`, `track/`, plus `privacy/`, `terms/`.
- Shared helpers live on `window.*` in `assets/config.js` (e.g. `formatCurrency`, `normalizePhone`, `waNumber`, `whatsappLink`, `notifyBuyer`, buyer templates). App pages alias them at the top of each Babel block.
- Backend: Supabase (project `nizrqwvfuxbuhertypva`). Postgres + RLS + `SECURITY DEFINER` RPCs + Edge Functions (Deno). Migrations in `supabase/migrations/`.

## 🚨 Critical rules — do not break
1. **Pin CDNs.** App pages MUST load `@babel/standalone@7` and `cdn.tailwindcss.com/3.4.16`. An unpinned Babel rolled to v8 and blanked every React page (inline `text/babel` defaulted to ES modules → "Cannot use import statement outside a module"). **If a React page renders blank, check the Babel CDN version first.**
2. **Bump the config cache version** when editing `assets/config.js`: change `config.js?v=N` in all pages that load it (shop/dashboard/admin/track), or browsers serve a stale copy.
3. **Public data access goes through SECURITY DEFINER RPCs**, never direct table reads. Sensitive tables (orders, payments, fees, secrets, OTPs, login events, admin tables) are RLS-locked to owner + `is_platform_admin()`; secrets/OTP tables are deny-all.
4. **Currency = Maloti (M)** via `formatCurrency` (Lesotho-first). Landing is geo-aware. Switch back toward "R"/geo only when launching SA.
5. **Phones:** always build WhatsApp links with `window.waNumber()` (routes through `normalizePhone` → full intl number). Never `phone.replace(/[^0-9]/g,'')` directly — that drops the country code.

## Auth & roles
- **Sellers:** Supabase phone-OTP session (BulkSMS) + bcrypt PIN device-unlock (`seller_secrets`). RPCs: `seller_register`, `seller_login`, `seller_reset_pin`, `seller_change_pin`, `link_current_seller` (ignores inactive sellers).
- **Admin:** a *pure admin*, NOT a seller. Identity in `public.admins`; `is_platform_admin()` checks it. Login = **phone + password** (`signInWithPassword`); OTP only for set/forgot password (`updateUser`). `admin_session` RPC returns the admin record.
- Admin user-mgmt RPCs (all guarded by `is_platform_admin()`): `admin_set_seller_status`, `admin_reset_seller_pin`, `admin_seller_detail`, `admin_login_audit`, `admin_actions_log`. Actions logged to `admin_actions`; logins to `seller_login_events`.

## Deploy workflow
- Push to `main` on `EhsanRiz/yebosell` → **Cloudflare auto-deploys** (~30–60s; Worker `yebosell`). No GitHub Actions.
- Cloudflare's build queue can lag/coalesce rapid pushes; if the last commit doesn't go live, push an empty commit to nudge, and verify by fetching the live asset with a cache-buster (`curl https://yebosell.co.za/assets/config.js?cb=$(date +%s)`).
- Validate React pages before pushing: extract the `text/babel` block and run it through `@babel/standalone` (`presets:['react']`) — catches JSX errors. `node --check assets/config.js` for the config.

## Testing
- Backend/RLS/RPCs: SQL via the Supabase MCP or `psql` (service role bypasses RLS — to test anon, use the anon key).
- Browser E2E: **Playwright is set up** (`npm test`; config + tests in `tests/`, see `tests/README.md`). A local static server serves the repo root. Static-page tests (terms/landing/privacy) run offline; React-page tests (dashboard/shop/track) need outbound network for the CDNs and self-skip when it's unavailable. The managed remote env has a pre-installed Chromium (auto-detected by `playwright.config.js`) — don't run `npx playwright install` there. Core flows still to cover: buyer storefront→checkout→track; seller register→add product→order→status→notify; admin drill-down→suspend/reset→audit.
- Demo stores block checkout (`is_demo=true`); flip a seller's `is_demo` to test real ordering, then restore.

## Conventions / gotchas
- Brand: green `#15803d` + gold `#a16207` line icons (Lucide style). No emoji-as-icons. Two-tone brand tiles only.
- Repo-root `.md` files are web-served (yebosell.co.za/progress.md etc.) — keep secrets out of them. Never commit tokens.
- SA (+27) SMS OTP doesn't deliver yet (parked) — don't onboard +27 sellers.

## Where to look
- `progress.md` — current status, "pick up here", roadmap.
- `SPEC_whatsapp_free_tracking.md`, `SPEC_supabase_auth_migration.md` — design specs.
- `supabase/migrations/` — schema history (track_token, harden_seller_auth, stage3b RLS, pure_admin_model, admin_user_management, …).
