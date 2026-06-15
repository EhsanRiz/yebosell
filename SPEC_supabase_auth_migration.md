# YeboSell — Spec: Full Supabase Auth migration (phone OTP)

**Status:** In progress — Stage 1 shipped · **Date:** 2026-06-13
**Goal:** Replace the PIN-only, anon-role model with real Supabase Auth phone-OTP sessions so RLS can be scoped by `auth.uid()` — closing the data-layer hole (today anyone with the public anon key can read/write `orders`/`products` directly). OTP is delivered through the existing **BulkSMS** account via Supabase's Send SMS Hook.

---

## Why
Auth is currently PIN-based with no server session, so the seller dashboard queries the DB as the **anon** role — the same role as the public. RLS can't tell a seller apart from an attacker, so `orders`/`order_items`/`products` keep an open `ALL/public/true` policy. Login was hardened (bcrypt, server-side, rate-limited) but the **data layer is still open**. Real sessions fix this and set up clean multi-seller.

## Target model
- **Sign in / register:** phone → SMS OTP (via BulkSMS hook) → real Supabase session (JWT with `auth.uid()`).
- **PIN:** becomes a **device quick-unlock** (re-enter PIN to unlock a stored session on a trusted device), not the security boundary. OTP re-auth on a new device or after sign-out. *(Decision to confirm — see §Decisions.)*
- **RLS:** sellers can only touch their own rows (`auth.uid()`); public storefront/checkout/tracking keep the minimal anon access they need.

---

## Stage 1 — Foundation (DONE, additive, no user-facing change)
- `auth-sms-hook` edge function deployed — receives Supabase's signed Send-SMS payload (`user.phone` + `sms.otp`), verifies the `v1,whsec_` secret (standard-webhooks), sends via BulkSMS.
- `sellers.auth_user_id uuid references auth.users(id)` column added (nullable) + index.

### Dashboard config YOU must do to activate Stage 1 (I can't via tools)
1. **Authentication → Providers → Phone:** enable the Phone provider. (No native SMS provider needed — the hook handles sending.)
2. **Authentication → Hooks → Send SMS Hook:** enable it, type = HTTPS, URL =
   `https://nizrqwvfuxbuhertypva.supabase.co/functions/v1/auth-sms-hook`
   Supabase generates a **secret** (`v1,whsec_…`). Copy it.
3. **Edge Functions → Secrets:** add `SEND_SMS_HOOK_SECRET` = that `v1,whsec_…` value.
4. (Optional) Set OTP length/expiry under Auth settings.

Then we can test `supabase.auth.signInWithOtp({ phone })` → SMS arrives → `verifyOtp(...)` returns a session — **without touching the live login yet.**

---

## Stage 2 — Phone-OTP login alongside PIN (no breakage)
- Add an auth path in `dashboard/`: `signInWithOtp` → `verifyOtp` → session.
- On first successful auth, **link**: find the seller row by phone, set `auth_user_id = auth.uid()`; if none, create it. Existing PIN login keeps working during transition.
- Keep PIN as the device quick-unlock layer (verify against `seller_secrets` once session exists), or re-OTP. (Decision §.)
- Backfill: existing 4 sellers link on their next OTP sign-in (or we pre-create auth users for them).

## Stage 3 — RLS cutover (the careful part)
Rewrite policies, then drop the open `ALL/public/true` ones:
- **sellers:** SELECT public (storefront needs business profile) BUT restrict UPDATE/DELETE to `auth_user_id = auth.uid()`. Consider hiding sensitive columns from anon (bank_details) via a public view.
- **products:** anon SELECT only `is_active = true` (storefront); INSERT/UPDATE/DELETE only by owner (`seller_id` belongs to `auth.uid()`).
- **orders / order_items:** anon INSERT (buyer checkout) + anon SELECT removed (tracking already uses SECURITY DEFINER RPCs); seller SELECT/UPDATE scoped to owner.
- **payments / deliveries / discount_codes / platform_fees:** owner-scoped.
- Verify all four surfaces still work: storefront (anon), checkout (anon), tracking (anon RPC), dashboard (authed).

## Stage 4 — Cleanup
- Retire interim `seller_login` / `seller_register` / `seller_reset_pin` (or repurpose `seller_change_pin`/reset for the PIN-unlock layer).
- Decide final PIN role.

---

## Decisions to confirm
1. **PIN role:** keep as device quick-unlock (recommended — cheap, low-friction, no SMS per login) vs. drop PIN and OTP every login (more friction + SMS cost).
2. **Existing accounts:** link-on-next-OTP-login (simplest) vs. pre-create auth users now.
3. **SA delivery:** OTP via hook still goes through BulkSMS → SA needs the Sender ID fix (separate item) before SA sellers can verify.

## Risks
- RLS cutover can lock out the dashboard/storefront if a policy is wrong → do Stage 3 on a branch or in a low-traffic window with immediate rollback SQL ready.
- Send SMS Hook payload/response contract must match exactly — verified live in Stage 1 testing before relying on it.
