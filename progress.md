# YeboSell — Progress Log
**Date:** 26 April 2026
**Live site:** https://yebosell.co.za
**GitHub:** https://github.com/EhsanRiz/yebosell (main, latest `cf7fa91`)
**Supabase project:** `nizrqwvfuxbuhertypva`
**Cloudflare Worker:** `yebosell`

---

## CURRENT STATE

The codebase is fully rebranded to YeboSell. The live site is up and serving the new branding. WhatsApp messaging is on hold pending a fresh WABA via a BSP (the previous WABA was permanently banned by Meta on 11 April 2026).

---

## RECENT SESSION WORK (26 April 2026)

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

### Immediate / next
1. **Set up new WABA via BSP** with **InnovaEarth (Pty) Ltd** as the registered entity. Need a fresh SA SIM. Top BSP candidates: 360dialog (€49/mo) or Infobip (Africa coverage).
2. **Update Edge Functions** (`whatsapp-notify`, `whatsapp-webhook`) to use BSP API instead of direct Meta Graph API once the BSP is live.
3. **Submit message templates** for Meta approval through the new BSP: order confirmation, status updates, delivery notifications.

### Lower priority
4. Style the raw URL in How It Works as a browser-bar mockup
5. Smoke test live yebosell.co.za across all pages post-deploy
6. Register YeboSell / InnovaEarth as a tax/VAT entity if applicable
7. Consider SMS fallback for order notifications (if using Infobip)
8. Transition demo stores to real featured stores once real sellers sign up
9. Rename internal CSS prefix `kc-` to `ys-` (cosmetic; not user-visible)

### Done in this and previous sessions
- ✅ Brand identity finalized: YeboSell on yebosell.co.za
- ✅ Repo renamed and Cloudflare reconnected
- ✅ Worker renamed and wrangler.toml synced
- ✅ OG image regenerated with new branding
- ✅ Privacy/Terms attribution updated to InnovaEarth × 4D Climate Solutions
- ✅ HANDOFF.md and progress.md refreshed
