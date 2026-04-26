# Session Context — Resuming on Mac Mini

> Picking up the conversation that started in a Claude Code web session.
> Branch: `claude/revisit-whatsapp-seller-os-YY7Ma`
> Date paused: 2026-04-26

---

## Where we are

The project is the **WhatsApp Seller OS** (currently branded **Khotso Connect**), a static multi-page site deployed on Cloudflare Pages. Pages: `index.html` (landing), `dashboard/`, `shop/`, `admin/`, `track/`, `privacy/`, `terms/`, plus `assets/`. Recent commits on this branch covered KC rebrand, mobile responsiveness, landing polish, demo stores, geo-localization (Maloti/ZAR), and SVG flags.

We're now revisiting **strategic + UX issues** before more feature work.

---

## Open threads (in priority order)

### 1. Brand name — ✅ LOCKED: **YeboSell**

After comparing YeboSell vs. Sella vs. YeboShop/YeboTill, user settled on **YeboSell**.

**Why YeboSell won over Sella:**
- Sella has a major incumbent collision (Banca Sella — Italian bank with "Smart Business Sella" SME app, payments/POS vertical, EU trademark). `sella.africa` already taken by a marketplace.
- YeboSell exact mark is clean: no company, trademark, or social handle on the exact string.

**Known caveats to manage:**
- **Yebo Fresh** (yebofresh.co.za) — Smollan-acquired SA township ecom. Different sub-vertical (B2B distribution to spaza shops vs. our seller-tools-on-WhatsApp), but expect *some* "are you Yebo Fresh?" confusion. Differentiate hard in positioning.
- Other "Yebo" brands (Sales, Clothing, Biltong, Group, Electronics, South Africa, Fresh) are in unrelated verticals — low risk.

**Pre-launch to-dos around the name:**
- CIPC trademark search (class 35 advertising/business + class 42 software) before formal launch
- Grab domains: yebosell.com, yebosell.co.za, yebosell.africa
- Grab social handles: @yebosell on IG, X, TikTok, FB
- Update `BRAND_NAME` in `assets/config.js` and run a full rebrand sweep across all HTML pages (same surface as the prior Khotso Connect pass)

**Tagline carry-over question:** keep "Sell smarter. Reach further. Grow together." or change? Not yet decided.

### 2. WhatsApp BSP integration (PLAN STAGE)

User reported Meta direct WhatsApp Business onboarding isn't working out. Wants to switch to a BSP (Business Solution Provider). Has a **South African phone number** to start with.

**Shortlist offered:**
- **360dialog** — recommended: cheap, no markup on Meta convo fees, strong EMEA/Africa, no UI lock-in (which matters because we *are* the seller-facing UI).
- **Gupshup** — broad, SA-friendly, good template tooling.
- **Twilio** — polished SDK/docs but pricier per-conversation.
- **AiSensy / Wati** — skip; they ship competing UIs.

**Next step when name is locked:** draft an integration plan covering BSP auth, sending template messages, receiving inbound webhooks, storing the WhatsApp phone-number-id, and wiring it into the dashboard / shop / order flows.

### 3. Sign-out button placement on dashboard (FIX PENDING)

In `dashboard/index.html`, the Sign Out button sits as a top-level item in the left sidebar between the user info card (`Ehsan Rizvi / +27761080024`) and the "Developed by 4D Climate Solutions" footer. It's visually competing with the nav items.

**Proposed fix:** fold it into the user card — make the user info block a clickable element that opens a small dropdown with Sign Out (and possibly "Account"). Cleaner sidebar, follows standard SaaS pattern.

**Status:** awaiting user go-ahead. Should be implemented after the rebrand pass so we don't redo the sidebar twice.

### 4. Full QA + testing pass (LATER)

After name change and BSP wiring, do a click-through of landing → shop → dashboard → admin → track on desktop and mobile. Use a local dev server (`python3 -m http.server` from repo root works, or `wrangler pages dev .`).

---

## Working agreement

User's stated order:
1. ✅ **Lock the name** — YeboSell
2. **WhatsApp BSP setup** ← next
3. **Fix everything** (sign-out dropdown + full Khotso Connect → YeboSell rebrand sweep + any other UX issues found)
4. **Test** (click-through QA on all apps, desktop + mobile)

---

## Useful repo facts

- Brand strings live across multiple HTML files — last rebrand (Khotso Connect) touched: `index.html`, `dashboard/index.html`, `shop/index.html`, `admin/index.html`, `track/index.html`, `terms/index.html`, `privacy/index.html`, `assets/config.js`. A future rename will follow the same surface.
- Footer credit: **"Developed by 4D Climate Solutions"** — keep.
- Currency display: ZAR (R) for SA, Maloti (M) for Lesotho — geo-based, already implemented.
- Demo stores: 3 browse-only demo stores added on this branch.

---

## How to resume

In the new Claude Code session on Mac Mini, after `git checkout claude/revisit-whatsapp-seller-os-YY7Ma`, just say:

> "Read `.claude/session-context.md` and let's continue. Lock the name first."

Claude should pick up exactly where we paused.
