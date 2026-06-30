// Playwright config for YeboSell E2E.
//
// Browser: in CI/dev where `npx playwright install` ran, Playwright finds its own
// browser. In the managed remote environment a Chromium is pre-installed under
// PLAYWRIGHT_BROWSERS_PATH but may be a different build number than this Playwright
// expects — so we auto-detect the pre-installed binary and point at it.
//
// Server: a tiny static server serves the repo root, so the app's absolute asset
// paths resolve as on the live site. NOTE: the React pages (dashboard/shop/track)
// load React, Babel, Tailwind and Supabase from CDNs — those tests need outbound
// network and (for data) the live Supabase project. The static-page tests
// (terms/landing/privacy) have no external dependencies and run fully offline.
const { defineConfig, devices } = require('@playwright/test');
const fs = require('fs');
const path = require('path');

function findPreinstalledChromium() {
  const base = process.env.PLAYWRIGHT_BROWSERS_PATH;
  if (!base) return undefined;
  try {
    const dirs = fs.readdirSync(base).filter(d => /^chromium-\d+$/.test(d));
    for (const d of dirs) {
      const p = path.join(base, d, 'chrome-linux', 'chrome');
      if (fs.existsSync(p)) return p;
    }
  } catch (e) { /* fall through to bundled browser */ }
  return undefined;
}

const executablePath = findPreinstalledChromium();
const PORT = Number(process.env.PORT || 4321);

module.exports = defineConfig({
  testDir: './tests/e2e',
  timeout: 30000,
  expect: { timeout: 10000 },
  fullyParallel: true,
  reporter: [['list']],
  use: {
    baseURL: process.env.BASE_URL || `http://127.0.0.1:${PORT}`,
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: {
        ...devices['Desktop Chrome'],
        launchOptions: executablePath ? { executablePath } : {},
      },
    },
  ],
  // Skip the local server when testing a remote BASE_URL (e.g. the live site).
  webServer: process.env.BASE_URL ? undefined : {
    command: `node tests/static-server.mjs`,
    url: `http://127.0.0.1:${PORT}/`,
    reuseExistingServer: true,
    timeout: 15000,
  },
});
