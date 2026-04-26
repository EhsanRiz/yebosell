# YeboSell — Progress Log
**Date:** 26 April 2026 (updated late-session)
**Live site:** https://yebosell.co.za
**GitHub:** https://github.com/EhsanRiz/yebosell (main, latest `3bfeb9b`)
**Supabase project:** `nizrqwvfuxbuhertypva`
**Cloudflare Worker:** `yebosell`

---

## 🎯 PICK UP HERE (start of next session)

You're mid-flight on **WhatsApp BSP setup via 360Dialog**. The remaining steps before you can call the WhatsApp Cloud API from YeboSell:

### Immediate next action
**Finish deploying the InnovaEarth website**, because Meta's BSP / WABA verification needs a public, branded site that ties to InnovaEarth (Pty) Ltd. We built the site this session and pushed it to GitHub, but Cloudflare Pages needs to be wired up.

**Steps to resume:**
1. **Cloudflare Dashboard → Workers & Pages → Create application → Pages → Connect to Git → `EhsanRiz/innovaearth`**
   - Build settings: leave all blank (no build command, no output dir)
   - Production branch: `main`
   - Click **Save and Deploy** — first deploy in ~60s
2. **Custom domains → Add `innovaearth.com`** → Cloudflare auto-creates the CNAME
3. Smoke test the live site at https://innovaearth.com (8 pages)
4. **Then proceed to 360Dialog signup** at https://hub.360dialog.com/signup
   - Plan: **Regular ($59/month + Meta wholesale)** — includes BSP support layer, 80 msg/sec, 24/7 support
   - Use **InnovaEarth (Pty) Ltd** as the registered entity
   - Use the **fresh SA SIM** that's been confirmed never-used-on-WhatsApp
   - You'll need: CIPC registration cert, business proof of address, director ID
5. Once 360Dialog is live: WhatsApp Cloud API number → submit message templates for Meta approval (order confirmation, status updates, delivery notifications, OTP)
6. Update Supabase Edge Functions (`whatsapp-notify`, `whatsapp-webhook`) to use 360Dialog API instead of direct Meta Graph API

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
| Cloudflare Pages deployment | ⏳ Pending | Connect repo to Pages, bind `innovaearth.com` |

**InnovaEarth repo location (local):** `/Users/ehsanrizvi/Documents/Claude/Projects/InnovaEarth/`
**InnovaEarth Cloudflare account:** Same as YeboSell — `3ed4a36f8edbaa255c5d1bf30fd6169c`

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
1. **Deploy InnovaEarth site to Cloudflare Pages** + bind `innovaearth.com` custom domain ← *START HERE*
2. **Verify InnovaEarth email deliverability** — confirm DKIM is "Authenticated" in Google Admin Console; add the DMARC TXT record to Cloudflare DNS
3. **360Dialog signup** at hub.360dialog.com using InnovaEarth (Pty) Ltd, the fresh SA SIM, and InnovaEarth registration docs
4. **Submit WhatsApp message templates** through 360Dialog for Meta approval (order confirmation, status updates, delivery notifications, OTP)
5. **Update Supabase Edge Functions** (`whatsapp-notify`, `whatsapp-webhook`) to call the 360Dialog API instead of Meta Graph API directly
6. **End-to-end test:** place a test order on yebosell.co.za, verify WhatsApp confirmation reaches the buyer

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
