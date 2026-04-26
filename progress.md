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

**360Dialog is LIVE.** WABA `1260080010524740` provisioned, number `+27 72 521 7745` is **Connected**, display name **YeboSell** approved by Meta. 2 of 4 message templates submitted and showing **In review**:

| Template | Category | Status |
|---|---|---|
| `order_confirmation` | Utility | ⏳ In review |
| `order_status_update` | Utility | ⏳ In review |
| `delivery_notification` | Utility | ❌ Not submitted yet |
| `otp_verification` | Authentication | ❌ Not submitted yet |

### Immediate next actions (in order)

1. **Submit `delivery_notification` and `otp_verification`** — easiest path: Meta WhatsApp Manager → Manage templates → Create template (works directly, bypasses 360Dialog UI). Template specs are documented in this session's chat.
2. **Wait for Meta approvals** — Utility usually 1–3h, Authentication up to 24h. Watch Templates list for "In review" → "Approved" / "Rejected".
3. **🔒 ROTATE THE 360Dialog API KEY** — old key was leaked in chat during this session. Go to 360Dialog hub → Channel → API Keys → Revoke + Generate new. Store ONLY in 1Password as `D360_API_KEY`. Never paste into chat, commits, or frontend code.
4. **Update Supabase Edge Functions** (`whatsapp-notify`, `whatsapp-webhook`):
   - API base: `https://waba-v2.360dialog.io`
   - Auth header: `D360-API-KEY: $D360_API_KEY` (from Supabase secrets, NOT in code)
   - Send endpoint: `POST /messages`
   - Switch from Meta Graph API direct calls to 360Dialog's compatible API surface
5. **Set the webhook URL in 360Dialog** to `https://nizrqwvfuxbuhertypva.supabase.co/functions/v1/whatsapp-webhook` once the function is deployed
6. **End-to-end test** — place a test order on yebosell.co.za, verify the WhatsApp template message lands on a real buyer's phone

### Open Meta concern (likely benign — track but don't panic)

Earlier in the session, Meta Business Support Home showed the InnovaEarth WABA as **"Account Disabled"** and a Request Review was filed. But within minutes both templates submitted successfully via Meta WhatsApp Manager directly, and the number shows **Connected**. The "Account Disabled" badge was likely Meta UI lag or a feature-specific limitation that auto-resolved.

If templates approve cleanly → ignore the appeal, move on. If anything gets blocked → escalate via 360Dialog support (chat widget in their hub) AND keep the Request Review filed.

**Anti-evasion linking risk** to previously-banned 4D Climate Solutions WABA: same FB personal account + same Business Manager were used. Different legal entity (InnovaEarth) and different email (`hello@innovaearth.com`) help, but if Meta does eventually disable, the clean-room rebuild plan is in this session's chat.

### Why 360Dialog over Infobip
At YeboSell's current volume (~1.5k msgs/mo), Infobip would be ~$45/mo cheaper. We chose 360Dialog anyway because:
- Previous WABA was permanently banned — account stability is the #1 risk now, and 360Dialog has the closest active Meta relationship
- Faster template approval queue (WhatsApp-only specialist)
- Embedded Signup gets you live in under an hour vs Infobip's sales-led onboarding
- BSP can be switched later without losing the WABA (the WABA stays with Meta; only routing changes)

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

### Meta WABA "Account Disabled" scare → likely benign
- First attempt to submit a template via 360Dialog returned `"WhatsApp business account does not have permission to perform this action"`
- Meta Business Support Home showed WABA status: **"Account Disabled"** (ID `3954025628064622`, business ID `1280250267552755`)
- Filed a **Request Review** via Meta Business Support Home with full InnovaEarth business case
- Within minutes, templates began submitting successfully via **Meta WhatsApp Manager → Manage templates** (bypassing 360Dialog UI). WhatsApp Manager shows number as **Connected**
- Conclusion: "Account Disabled" badge was Meta UI lag or a feature-specific limitation, NOT a full ban. Likely safe to ignore the appeal IF templates approve cleanly
- Diagnostic data (preserved for clean-room rebuild if needed):
  - Previously banned WABA was under **4D Climate Solutions** (different legal entity from InnovaEarth ✅ helps the case)
  - Same FB personal account used for embedded signup ⚠️ strong link signal
  - Same Meta Business Manager ⚠️ strong link signal
  - Different email (`hello@innovaearth.com`) ✅ helps
- Clean-room fallback if Meta does eventually disable: would require co-founder/partner FB account + brand-new Business Manager (InnovaEarth entity, website, SIM, email all stay the same)

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
- ✅ WABA `1260080010524740` provisioned, number `+27 72 521 7745` Connected
- ✅ WhatsApp display name "YeboSell" Meta-approved
- ✅ 2 of 4 message templates submitted to Meta (`order_confirmation`, `order_status_update`) — In review
- ✅ Meta Request Review filed for the "Account Disabled" badge (likely benign)

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
