# YeboSell — Progress Log
**Date:** 26 April 2026 (updated late-late-session — 360Dialog live + templates submitted)
**Live site:** https://yebosell.co.za
**GitHub:** https://github.com/EhsanRiz/yebosell (main, latest `3bfeb9b`)
**Supabase project:** `nizrqwvfuxbuhertypva`
**Cloudflare Worker:** `yebosell`
**WhatsApp WABA:** `1260080010524740` (number `+27 72 521 7745`, display name `YeboSell`)
**360Dialog:** Regular plan, channel ID `GvevVDCH`

---

## 🎯 PICK UP HERE (start of next session)

**🔴 InnovaEarth WABA is BANNED** — confirmed via Meta WhatsApp Manager. Phone number `+27 72 521 7745` shows **Banned** status. Account status: **Disabled — does not meet policy guidelines**. Cited: **WhatsApp Business Commerce Policy** violation (almost certainly anti-evasion linking to the previously banned 4D Climate Solutions WABA).

**Action: WAIT.** Request Review has been filed with Meta. Do NOT touch the WABA, do NOT try to create another, do NOT retry templates — any action looks like evasion to Meta's automation and escalates the situation.

### Current state of artefacts

| Item | Status |
|---|---|
| WABA `1260080010524740` | 🔴 Banned |
| Number `+27 72 521 7745` | 🔴 Banned (was "Connected" briefly during the window before propagation) |
| Display name `YeboSell` | Was Meta-approved before the ban — irrelevant now |
| Template `order_confirmation` | ⏳ "In review" but will likely auto-reject when Meta processes it |
| Template `order_status_update` | ⏳ Same as above |
| Templates 3 + 4 | ❌ Blocked — "WhatsApp business account restricted from creating a new template" |
| Meta Request Review | ✅ Filed (24–48h response window) |
| Business Verification | 🔴 **Unverified** — this is the critical missing piece |

### Realistic appeal odds: 20–30%

Lower than initially estimated. Strong link signals (same FB personal account + same Meta Business Manager as the prior 4D Climate Solutions ban) + Commerce Policy citation + Unverified business = Meta's anti-evasion fingerprint. Plan for denial.

### Immediate next actions (in order)

1. **🟢 START Business Verification on InnovaEarth NOW** ← **DO THIS FIRST, regardless of appeal outcome**
   - Meta Business Suite → Business Settings → Business Info → Business Verification → "Start verification"
   - Need: CIPC registration certificate, proof of address (utility bill / bank letter ≤90 days), director ID
   - Takes 1–3 business days
   - Why it matters: a *verified* InnovaEarth helps the appeal AND is mandatory groundwork for the clean-room rebuild if appeal fails. Going clean-room on an unverified business gets banned again immediately.

2. **Wait for Meta Request Review response** (24–48h typical)
   - Check email at `hello@innovaearth.com`
   - Check Meta Business Support Home for status updates

3. **DO NOT:**
   - Create another WABA / Business Manager / Facebook account today
   - Retry template submission
   - Add another phone number
   - Open another Request Review (one is enough; multiple = looks suspicious)

### Three possible outcomes — and what each means

#### Outcome A: Appeal succeeds, WABA reinstated (~25% probability)
- Submit remaining 2 templates (`delivery_notification`, `otp_verification`) — specs in last session's chat
- Wait for all 4 templates to be Approved
- Rotate the leaked 360Dialog API key
- Update Supabase Edge Functions to use 360Dialog API (`https://waba-v2.360dialog.io`, auth header `D360-API-KEY`)
- Set webhook URL in 360Dialog → `https://nizrqwvfuxbuhertypva.supabase.co/functions/v1/whatsapp-webhook`
- End-to-end test on yebosell.co.za

#### Outcome B: Appeal denied — clean-room rebuild required (~75% probability)
**Prerequisites BEFORE attempting another WABA:**
- ✅ InnovaEarth Business Verification complete (the #1 priority above)
- A **different** Facebook personal account does the embedded signup (co-founder/partner — someone with no admin role on the prior banned 4D Climate Solutions WABA or its Business Manager)
- A **brand-new Meta Business Manager** under that fresh FB account (don't reuse the existing InnovaEarth BM `1280250267552755` — it's now flagged)
- Different device + IP for setup if practical
- InnovaEarth entity, website, email, SIM all stay the same
- 360Dialog account: cancel current `vOaWldPA` partnership, sign up fresh under the new BM (or transfer if 360Dialog supports it)

**Cost of clean-room:** another ~$59 month-1 on 360Dialog, possibly small CIPC re-pull fees, ~1 week elapsed time

#### Outcome C: Appeal pending past 72h
- Ping 360Dialog support (chat widget in their hub) and ask them to escalate via partner channel
- Their direct Meta partner relationship can sometimes unblock cases that go silent

### Productive work during the wait (doesn't touch Meta)

- Prep Supabase Edge Function code for 360Dialog (will work for whichever outcome)
- Smoke test yebosell.co.za across all pages — find any rebrand leftovers
- Style "How It Works" URL as browser-bar mockup (Open follow-up #7)
- Rename internal CSS prefix `kc-` → `ys-` (Open follow-up #12)
- Document the WhatsApp template specs as comments in YeboSell code so they're not lost

### Reference: 360Dialog & WABA identifiers (for support escalation)

- 360Dialog partner ID: `vOaWldPA`
- 360Dialog channel ID: `GvevVDCH`
- WABA External ID: `1260080010524740`
- Meta Business Manager ID: `1280250267552755`
- WhatsApp account ID (per Business Support Home): `3954025628064622`
- Number: `+27 72 521 7745`

### Why we still believe 360Dialog was the right BSP choice

The ban is a Meta-side decision and would have happened on Infobip, Twilio, or any BSP — Meta acts before the BSP layer. 360Dialog's partner relationship may actually help the appeal (escalation channel). Don't switch BSPs over this.

---

## InnovaEarth (parent / principal entity) — current status

InnovaEarth (Pty) Ltd is the registered SA company that **owns** YeboSell. To run WhatsApp via 360Dialog under the InnovaEarth entity, we built out InnovaEarth's public infrastructure this session.

| Item | Status | Notes |
|------|--------|-------|
| Domain `innovaearth.com` | ✅ Active on Cloudflare | DNS managed, 2 nameservers swapped at registrar |
| Google Workspace email | ✅ Live | `hello@innovaearth.com` sending and receiving |
| DKIM authentication | ⚠️ Verify | Confirm in Google Admin Console → Apps → Gmail → Authenticate email → status should be "Authenticated" |
| DMARC TXT record | ⚠️ Add manually | Cloudflare DNS → TXT, name `_dmarc`, content `v=DMARC1; p=none; rua=mailto:hello@innovaearth.com` |
| InnovaEarth website (8 pages) | ✅ Built + pushed | Repo: github.com/EhsanRiz/innovaearth, latest commit `866642a` |
| Cloudflare Pages deployment | ✅ Live | innovaearth.com serving correctly; cache purge resolved logo size discrepancy between `.pages.dev` and `.com` |

**InnovaEarth repo location (local):** `/Users/ehsanrizvi/Documents/Claude/Projects/InnovaEarth/`
**InnovaEarth Cloudflare account:** Same as YeboSell — `3ed4a36f8edbaa255c5d1bf30fd6169c`

---

## SESSION WORK (26 April 2026 — late-late session, 360Dialog WABA live + templates)

### InnovaEarth deployment confirmed live
- `innovaearth.pages.dev` and `innovaearth.com` both serve correctly
- Logo size discrepancy traced to Cloudflare edge cache; resolved by Cache → Purge Everything in CF Dashboard

### 360Dialog signup completed (Embedded Signup via Meta)
- Account: **InnovaEarth** on `app.360dialog.io` / `wabamanagement.360dialog.io` (channel ID `GvevVDCH`, partner ID `vOaWldPA`)
- Plan: **Regular ($59/mo + Meta wholesale)**
- Number: **+27 72 521 7745** (fresh SA SIM, never on WhatsApp before — confirmed)
- WhatsApp **Display Name: YeboSell** ✅ Meta-approved (caught at the Meta verification screen — initial 360Dialog UI label "InnovaEarth" was just the partner-side account label, not the public WABA display name)
- WABA External ID: **`1260080010524740`**
- Hosting: **Cloud API hosted by Meta** (modern, recommended)
- Data storage region: United States (POPIA note — should be flagged in Privacy page)
- Business Messaging Limit: 250 users/24h (Tier 1, auto-tiers up with quality)

### Meta WABA disabled — confirmed real ban (NOT UI lag, as initially hoped)
- **Initial signal:** template submission via 360Dialog returned `"WhatsApp business account does not have permission to perform this action"`
- **First read:** Meta Business Support Home showed "Account Disabled" but template submission via Meta WhatsApp Manager directly worked twice (`order_confirmation`, `order_status_update` both went to "In review"). Initially interpreted as UI lag.
- **Confirmation:** When attempting Template 3, hit hard error **"WhatsApp business account restricted from creating a new template"**. Returning to Phone Numbers showed status: **🔴 Banned**. Settings → WhatsApp accounts showed: 🔴 Disabled, "This account doesn't meet our policy guidelines", **Business verification: Unverified**, cited Commerce Policy violation.
- **Action taken:** filed Request Review via Meta Business Support Home with full InnovaEarth business case (CIPC reg, public website, opt-in policy). 24–48h response window.
- **Diagnostic data:**
  - Previously banned WABA was under **4D Climate Solutions** (different legal entity from InnovaEarth)
  - Same FB personal account used for embedded signup ⚠️ strong link signal
  - Same Meta Business Manager (`1280250267552755`) ⚠️ strong link signal
  - Different email (`hello@innovaearth.com`) ✅ helps slightly
  - InnovaEarth Business Verification: NOT done before WABA creation — this is now identified as the critical missing piece
- **Realistic appeal odds:** 20–30%. Plan for denial.
- **Clean-room fallback** documented in PICK UP HERE section: requires verified InnovaEarth business + new FB account + new Business Manager. Same legal entity, website, email, SIM can carry over.

### WhatsApp message templates — drafted + 2 of 4 submitted
All bodies end with `— YeboSell` sign-off (avoids Meta's "ends with placeholder" warning).

| Name | Category | Variables | Body summary | Status |
|---|---|---|---|---|
| `order_confirmation` | Utility | 4 | name, order#, total, track URL | ⏳ In review |
| `order_status_update` | Utility | 4 | name, order#, full status sentence, track URL | ⏳ In review |
| `delivery_notification` | Utility | 5 | name, order#, method, ETA, track URL | ❌ Not yet submitted |
| `otp_verification` | Authentication | 1 | OTP code | ❌ Not yet submitted |

**Lesson learned:** Meta enforces ~15–20 chars of static text per variable. `order_status_update` initially had 5 vars and failed validation; fixed by merging the status label and contextual sentence into one variable (`{{3}}`). `delivery_notification` may hit the same warning and need similar restructuring.

### API key & security
- 360Dialog API key was generated AND mistakenly pasted in chat → flagged for immediate rotation
- API base URL: `https://waba-v2.360dialog.io`
- Webhook URL field in 360Dialog: leave blank for now; set to `https://nizrqwvfuxbuhertypva.supabase.co/functions/v1/whatsapp-webhook` once Edge Function is deployed
- Future: API key lives ONLY in Supabase → Project Settings → Edge Functions → Secrets as `D360_API_KEY`. Never in code, commits, screenshots, or chat.

---

## SESSION WORK (26 April 2026 — late session, after rebrand)

### WhatsApp BSP analysis & decision
- Compared 360Dialog ($59/mo) vs Infobip (~$15-20/mo) vs Meta Cloud API direct (~$13/mo) at YeboSell's volume
- Decision: **360Dialog Regular plan** for account stability + faster template approvals after the prior WABA ban
- Confirmed prerequisites: SA SIM activated, number never on WhatsApp, InnovaEarth docs ready

### InnovaEarth domain + email
- Added `innovaearth.com` to Cloudflare via "Connect a domain" flow
- Set up Google Workspace via OAuth-managed DNS (verification TXT + 5 MX records auto-written by Google into Cloudflare)
- `hello@innovaearth.com` confirmed sending and receiving

### InnovaEarth website built (8 pages)
- Complete site at `/Users/ehsanrizvi/Documents/Claude/Projects/InnovaEarth/`, pushed to github.com/EhsanRiz/innovaearth
- Stack: pure static HTML + CSS + tiny vanilla JS, no build step, deploys to Cloudflare Pages
- Pages: Home, About, Services, Solutions, AI & Innovation, Who We Serve, Insights, Contact
- Brand: deep navy `#163A5C` + teal `#3FBFB4`, Fraunces serif headings + Inter body, custom inline-SVG globe motif on hero
- Logo cropped from 1000×1000 → 603×413 to remove whitespace; CSS heights bumped (header 56-64px, footer 72px)
- Contact form uses `mailto:` to `hello@innovaearth.com` (swap to a real backend later)

### Strategic deliverable produced
- Full website strategy & copy document (brand strategy, sitemap, navigation, messaging framework, page-by-page copy, CTA set, SEO metadata, design direction, component library, future expansion). Lives in this conversation; can be saved as a markdown file in the InnovaEarth folder if needed.

---

## EARLIER SESSION WORK (26 April 2026 — rebrand)

### Rebrand: Khotso Connect → YeboSell
- 9 files updated: `wrangler.toml`, `assets/config.js`, `index.html`, `dashboard/`, `shop/`, `admin/`, `track/`, `privacy/`, `terms/`
- New brand: **YeboSell** — "Yebo" green + "Sell" gold split-color wordmark
- Domain: `khotsoconnect.com` → `yebosell.co.za` everywhere (SITE_URL fallback, OG meta, contact links)
- `BRAND_NAME = 'YeboSell'` in `assets/config.js`
- Privacy & Terms attribute YeboSell as "a product of InnovaEarth (Pty) Ltd, operated by 4D Climate Solutions (Lesotho)"
- Footer credit blocks reflect "A product of InnovaEarth · Developed by 4D Climate Solutions"
- WhatsApp order-history signature → "_Sent from YeboSell_"
- New CSS class `.brand-green` / `.kc-green` for the green half of the wordmark

### Infrastructure
- GitHub repo renamed: `EhsanRiz/whatsapp-seller-os` → `EhsanRiz/yebosell` (old URL auto-redirects)
- Cloudflare Worker renamed: `whatsapp-seller-os` → `yebosell`
- `wrangler.toml` `name` field synced to `yebosell` (resolves Cloudflare's mismatch warning)
- Cloudflare Git binding reconnected to the renamed repo
- `.gitignore` now excludes `.claude/` to keep per-user Claude Code settings out of the repo

### OG image regenerated
- New `assets/og-image.png` (1200×630): green gradient, "Yebo" white + "Sell" gold wordmark, tagline, InnovaEarth × 4D attribution
- Generator script committed at `scripts/og-image.py` for future tweaks
- Note: WhatsApp/Facebook cache OG images — use [FB Sharing Debugger](https://developers.facebook.com/tools/debug/) → "Scrape Again" to refresh

### Landing page footer fixes
- "A product of 4D Climate Solutions" → "Developed by 4D Climate Solutions" (4D is the developer; InnovaEarth is the principal)
- Removed incorrect link from "InnovaEarth" (was pointing at 4dcs.co.za)
- Wrapped Yebo|Sell spans in a parent span in mobile drawer + footer so the `.logo` flex `gap` stops separating them

### Commits this session (in order)
```
3bfeb9b Add progress.md to repo
cf7fa91 Regenerate OG image for YeboSell + landing footer fixes
6c4f417 Rename worker in wrangler.toml: whatsapp-seller-os → yebosell
ccf8a49 Rebrand: Khotso Connect → YeboSell
```

---

## PREVIOUS SESSION WORK (12 April 2026 — Khotso Connect era, now superseded)

### Geo-based localization
- Cloudflare `/cdn-cgi/trace` detects visitor country
- Lesotho default: Maloti (M), +266 phone, Lesotho flag SVG
- South Africa: ZAR (R), +27 phone, SA flag SVG
- All currency references wrapped in `.geo-currency` class

### Demo stores (browse-only)
- `is_demo` boolean on `sellers` table
- 3 demo sellers seeded: Naledi's Boutique (`naledi-boutique`), Tech Zone Jozi (`tech-zone-jozi`), Lineo's Crafts (`lineo-crafts`)
- 6 products each, with photos in `assets/demo-products/`
- `addToCart()` returns early if `isDemo`; cart stays empty; "Open your own free store →" CTA replaces Add to Cart

### Landing page polish
- Mobile sidebar drawer, login overlap fix, bottom nav scroll
- Realistic phone mockup, CSS dashboard mockup, testimonials, FAQ
- Open Graph + Twitter Card meta tags
- Featured stores section linking to demo stores
- Mobile demo slideshow nav (prev/next + dot indicators + swipe)
- Track Order in landing nav

### Other earlier features
- Admin panel + platform fees + seller status gate
- Delivery management system (delivery_method, delivery_status, addresses, courier/pickup/taxi/bus)
- Clickable detail panels in admin
- Discount codes management, low stock alerts, checkout discounts
- Order tracking timeline matched to seller dashboard statuses
- Repeat order, buy again, track from My Orders
- Send Order History to WhatsApp button

---

## OPEN FOLLOW-UPS

### Immediate / next (in order)
1. **Submit `delivery_notification` and `otp_verification` templates** ← *START HERE* (via Meta WhatsApp Manager → Manage templates, since that worked first try)
2. **Wait for all 4 templates to be Approved by Meta** (1–24h)
3. **🔒 Rotate the 360Dialog API key** (old one was leaked in chat)
4. **Verify InnovaEarth email deliverability** — confirm DKIM is "Authenticated" in Google Admin Console; add the DMARC TXT record to Cloudflare DNS
5. **Update Supabase Edge Functions** (`whatsapp-notify`, `whatsapp-webhook`) to call the 360Dialog API instead of Meta Graph API directly
6. **Set 360Dialog webhook URL** to deployed Supabase Edge Function endpoint
7. **End-to-end test:** place a test order on yebosell.co.za, verify WhatsApp confirmation reaches the buyer

### Lower priority
7. Style the raw URL in How It Works as a browser-bar mockup
8. Smoke test live yebosell.co.za across all pages post-deploy
9. Register YeboSell / InnovaEarth as a tax/VAT entity if applicable
10. Consider SMS fallback for order notifications (if needed later)
11. Transition demo stores to real featured stores once real sellers sign up
12. Rename internal CSS prefix `kc-` to `ys-` (cosmetic; not user-visible)
13. Swap InnovaEarth contact form `mailto:` backend for a real endpoint (Cloudflare Worker / Formspree) once inquiry volume justifies it

### Done
- ✅ Brand identity finalized: YeboSell on yebosell.co.za
- ✅ Repo renamed and Cloudflare reconnected
- ✅ Worker renamed and wrangler.toml synced
- ✅ OG image regenerated with new branding
- ✅ Privacy/Terms attribution updated to InnovaEarth × 4D Climate Solutions
- ✅ progress.md tracked in repo and updated each session
- ✅ BSP decision made (360Dialog Regular plan)
- ✅ InnovaEarth domain on Cloudflare + Google Workspace email live
- ✅ InnovaEarth full website built and pushed to GitHub
- ✅ InnovaEarth Cloudflare Pages deployment live at innovaearth.com
- ✅ 360Dialog account created on Regular plan
- ✅ WABA `1260080010524740` provisioned (now banned, but signup process is documented and reusable)
- ✅ WhatsApp display name "YeboSell" Meta-approved
- ✅ 2 of 4 message templates drafted + submitted to Meta (will likely auto-reject given WABA ban)
- ✅ Meta Request Review filed (24–48h response window)
- ✅ Diagnostic data captured for potential clean-room rebuild
- ✅ Identified Business Verification as the critical missing prerequisite for next attempt

---

## CROSS-REPO REFERENCES

| What | Where |
|------|-------|
| YeboSell product code (this repo) | https://github.com/EhsanRiz/yebosell |
| InnovaEarth website code | https://github.com/EhsanRiz/innovaearth |
| Local YeboSell main worktree | `/Users/ehsanrizvi/Documents/Claude/Projects/WhatsApp Seller OS/` |
| Local InnovaEarth folder | `/Users/ehsanrizvi/Documents/Claude/Projects/InnovaEarth/` |
| InnovaEarth source materials (PDF, logo, contracts) | `/Users/ehsanrizvi/Library/CloudStorage/OneDrive-4DClimateSolutions/Projects/InnovaEarth/` |
| YeboSell HANDOFF.md (local-only, contains GitHub PAT) | `/Users/ehsanrizvi/Documents/Claude/Projects/WhatsApp Seller OS/HANDOFF.md` |
