# YeboSell E2E tests (Playwright)

Browser end-to-end tests. A tiny static server (`tests/static-server.mjs`) serves the
repo root so the app's absolute asset paths resolve exactly as on the live site.

## Run

```bash
npm install                 # first time (installs @playwright/test)
npm test                    # run everything
npm run test:static         # only the offline static-page tests
npm run test:ui             # Playwright UI mode
BASE_URL=https://yebosell.co.za npx playwright test   # run against the live site
```

By default tests run against the local static server + the **live Supabase** project.
Set `TEST_STORE_SLUG` to point the storefront tests at a different store (default:
`naledi-boutique`, a demo store — demo stores render the full checkout UI but block the
final order server-side, so these tests never create real data).

## Two kinds of tests

- **`static-pages.spec.js`** — `index.html`, `/terms/`, `/privacy/` have **no external
  (CDN) dependencies**, so they run fully offline in any environment. They lock in the
  Terms-of-Service structure and the user-agreement / signing clauses.

- **`react-pages.spec.js`** — `dashboard`, `shop`, `track` load React, Babel, Tailwind
  and Supabase from CDNs and talk to the live backend. They need **outbound network**.
  When the CDNs are unreachable (e.g. a locked-down sandbox), each test **self-skips**
  instead of failing. Run them locally or in a network-open environment.

## Environment notes

- The managed remote environment ships a pre-installed Chromium under
  `PLAYWRIGHT_BROWSERS_PATH`. `playwright.config.js` auto-detects that binary, so do
  **not** run `npx playwright install` there. Locally, run it once to fetch the browser.
- Coverage is intentionally split: backend/RPC behaviour (fees, signing, order creation)
  is best tested with SQL against Supabase; these Playwright tests cover the rendered UI.

## What's covered / TODO

Covered: Terms page structure + clauses; landing brand; React pages mount; storefront
renders; checkout exposes the buyer place-of-signing field with a gated Place Order.

Not yet automated (needs an authenticated seller session — phone OTP): the seller
agreement modal sign/decline flow and the signed-PDF download. These are documented as
manual pilot checks in the app for now.
