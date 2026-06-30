// Static-page E2E — these pages have no external (CDN) dependencies, so they run
// fully offline in any environment. They lock in the Terms-of-Service structure and
// the user-agreement clauses we ship.
const { test, expect } = require('@playwright/test');

test.describe('Terms of Service', () => {
  test('loads with the expected title', async ({ page }) => {
    await page.goto('/terms/');
    await expect(page).toHaveTitle(/Terms of Service/i);
    await expect(page.locator('.header h1')).toHaveText(/Terms of Service/i);
  });

  test('has 20 sequentially-numbered sections', async ({ page }) => {
    await page.goto('/terms/');
    const headings = await page.locator('.card h2').allTextContents();
    expect(headings.length).toBe(20);
    headings.forEach((h, i) => {
      expect(h.trim()).toMatch(new RegExp('^' + (i + 1) + '\\. '));
    });
  });

  test('includes the user-agreement & signing clauses', async ({ page }) => {
    await page.goto('/terms/');
    const body = page.locator('.container');
    await expect(body).toContainText('Electronic Acceptance');
    await expect(body).toContainText('electronic signature');
    await expect(body).toContainText('Eligibility');
    await expect(body).toContainText('Cancellations');
    await expect(body).toContainText('Privacy');
  });

  test('describes the first-10-sellers launch offer and the 5% fee', async ({ page }) => {
    await page.goto('/terms/');
    const fees = page.locator('.card').filter({ has: page.locator('h2', { hasText: 'Platform Fees' }) });
    await expect(fees).toContainText('5%');
    await expect(fees).toContainText(/first 10 sellers/i);
  });

  test('Communications section covers in-app chat, SMS and WhatsApp click-to-chat', async ({ page }) => {
    await page.goto('/terms/');
    const comms = page.locator('.card').filter({ has: page.locator('h2', { hasText: 'Communications' }) });
    await expect(comms).toContainText('In-app chat');
    await expect(comms).toContainText('SMS');
    await expect(comms).toContainText(/click-to-chat/i);
  });
});

test.describe('Landing page', () => {
  test('renders the YeboSell brand', async ({ page }) => {
    await page.goto('/');
    await expect(page.locator('body')).toContainText(/YeboSell/i);
  });
});
