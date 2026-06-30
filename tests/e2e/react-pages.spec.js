// React-page E2E. These pages load React, Babel, Tailwind and Supabase from CDNs and
// talk to the live Supabase project, so they need outbound network. When the CDNs are
// unreachable (e.g. the locked-down remote sandbox), each test self-skips instead of
// failing — run them locally or against a network-open environment.
//
// Storefront tests target a DEMO store by default (TEST_STORE_SLUG), which renders the
// full storefront + checkout UI but blocks the final order server-side, so they never
// create real data.
const { test, expect } = require('@playwright/test');

const STORE = process.env.TEST_STORE_SLUG || 'naledi-boutique';

// Navigate without waiting on the (possibly blocked) CDN scripts, then wait for React to
// actually load. Returns true if the page's React runtime is available.
async function open(page, url) {
  // 'commit' returns as soon as navigation commits — we don't want to block on the
  // render-blocking CDN <script> tags (which hang when the network is locked down).
  // Then give the CDN bundles a moment and check once whether React actually loaded.
  await page.goto(url, { waitUntil: 'commit' }).catch(() => {});
  await page.waitForTimeout(5000);
  return page.evaluate(() => typeof window.React !== 'undefined').catch(() => false);
}

test('dashboard mounts and shows the seller login screen', async ({ page }) => {
  const ready = await open(page, '/dashboard/');
  test.skip(!ready, 'React/CDN unavailable in this environment');
  await expect(page.locator('#app')).not.toBeEmpty();
  await expect(page.locator('body')).toContainText(/YeboSell/i);
});

test('track page mounts and shows the order lookup', async ({ page }) => {
  const ready = await open(page, '/track/');
  test.skip(!ready, 'React/CDN unavailable in this environment');
  await expect(page.locator('#root')).not.toBeEmpty();
});

test('storefront mounts for the demo store', async ({ page }) => {
  const ready = await open(page, `/shop/?s=${STORE}`);
  test.skip(!ready, 'React/CDN unavailable in this environment');
  await expect(page.locator('#root')).not.toBeEmpty();
  await expect(page.getByText('Add to Cart').first()).toBeVisible({ timeout: 15000 });
});

// Best-effort: walks to checkout and asserts the buyer signing UI. Selectors match the
// current storefront; adjust if the checkout markup changes. Does NOT submit an order.
test('checkout shows place-of-signing and a gated Place Order button', async ({ page }) => {
  const ready = await open(page, `/shop/?s=${STORE}`);
  test.skip(!ready, 'React/CDN unavailable in this environment');

  await page.getByText('Add to Cart').first().click({ timeout: 15000 });

  // Open checkout (cart drawer -> Proceed to Checkout).
  const proceed = page.getByText('Proceed to Checkout');
  if (await proceed.isVisible().catch(() => false)) {
    await proceed.click();
  } else {
    await page.getByText(/Checkout/i).first().click().catch(() => {});
    await proceed.click().catch(() => {});
  }

  // The buyer signing field and gated submit must be present.
  await expect(page.getByText('Place of signing')).toBeVisible({ timeout: 10000 });
  await expect(page.getByText(/electronic signature/i)).toBeVisible();
  await expect(page.getByRole('button', { name: /Place Order/i })).toBeDisabled();
});
