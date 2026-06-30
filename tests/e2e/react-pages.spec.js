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
// Demo stores render the storefront but CANNOT checkout (Add-to-Cart is replaced with a
// "this is a demo" banner). To exercise the checkout signing UI, point this at a REAL
// (non-demo) store slug that has an in-stock product. Unset -> the checkout test skips.
const CHECKOUT_STORE = process.env.TEST_CHECKOUT_STORE;
// A NO-VARIANT, in-stock product in that store, so Add-to-Cart is enabled immediately
// (variant products gate the button behind "Select a colour/size").
const CHECKOUT_PRODUCT = process.env.TEST_CHECKOUT_PRODUCT || 'Classic White T-Shirt';

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

test('storefront mounts and renders the store header', async ({ page }) => {
  const ready = await open(page, `/shop/?s=${STORE}`);
  test.skip(!ready, 'React/CDN unavailable in this environment');
  await expect(page.locator('#root')).not.toBeEmpty();
  // The storefront sets <h1> to the store's business name once its data loads.
  await expect(page.getByRole('heading', { level: 1 }).first()).toBeVisible({ timeout: 15000 });
});

// Best-effort checkout walk asserting the buyer signing UI. Demo stores cannot checkout,
// so this is OPT-IN: set TEST_CHECKOUT_STORE to a real store slug with an in-stock product.
// Does NOT submit an order (only verifies the signing field + gated button).
test('checkout shows place-of-signing and a gated Place Order button', async ({ page }) => {
  test.skip(!CHECKOUT_STORE, 'Set TEST_CHECKOUT_STORE to a real (non-demo) store slug with stock — demo stores cannot checkout');
  const ready = await open(page, `/shop/?s=${CHECKOUT_STORE}`);
  test.skip(!ready, 'React/CDN unavailable in this environment');

  // Open the specific no-variant product (Add to Cart lives inside the product modal).
  await page.getByRole('heading', { level: 1 }).first().waitFor({ timeout: 15000 });
  await page.getByText(CHECKOUT_PRODUCT, { exact: false }).first().click({ timeout: 15000 });
  await page.getByRole('button', { name: /Add to Cart/i }).click({ timeout: 10000 });

  // Close the product modal, open the cart (floating button has a .badge-cart), checkout.
  await page.keyboard.press('Escape').catch(() => {});
  await page.locator('button:has(.badge-cart)').first().click({ timeout: 10000 });
  await page.getByText('Proceed to Checkout').click({ timeout: 10000 });

  // The buyer signing field and gated submit must be present.
  await expect(page.getByText('Place of signing')).toBeVisible({ timeout: 10000 });
  await expect(page.getByText(/I confirm my name above is my electronic signature/i)).toBeVisible();
  await expect(page.getByRole('button', { name: /Place Order/i })).toBeDisabled();
});
