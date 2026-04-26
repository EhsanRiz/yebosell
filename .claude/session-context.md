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

### 1. Brand name (DECISION PENDING)

User wants to revisit "Khotso Connect" because the rollout will cover **South Africa + Lesotho + other regional countries**, and "Khotso" (Sesotho for "peace") is too Lesotho-narrow for SA audiences.

**User preference so far:** likes **YeboSell** ("Yebo" = "yes" in Zulu — energetic, recognizable in SA).

**Web search findings on YeboSell:**
- Exact name "YeboSell" has **no existing company, trademark, social handle, or app** — clean.
- Domains `yebosell.com`, `.co.za`, `.africa` appear unused (whois lookups blocked, but no indexed presence).
- **BUT** the "Yebo" prefix is crowded in SA commerce:
  - **Yebo Fresh** (yebofresh.co.za) — major SA township ecommerce, recently acquired by Smollan. 🔴 Highest collision risk.
  - Yebo Sales (East London, civils/sanitation) — different industry, low risk.
  - Yebo South Africa (travel/culture), Yebo Group (packaging), Yebo Biltong, Yebo Clothing, Yebo Electronics — low risk.

**Alternatives offered if user wants to dodge Yebo Fresh shadow:**
- **YeboShop** — same energy, retail-explicit
- **YeboTill** — POS-flavored, distinctive
- **YeboCart**, **YeboTrade**

**Recommendation made:** YeboSell is legally defensible, but YeboTill or YeboShop give 90% of the energy with less Yebo Fresh confusion. User has not made a final call yet — **resume here by asking the user to lock the name.**

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
1. **Lock the name** ← stuck here
2. **WhatsApp BSP setup**
3. **Fix everything** (starting with sign-out, plus rebrand sweep)
4. **Test**

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
