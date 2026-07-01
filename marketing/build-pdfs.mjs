// Render the branded one-pager HTML files to A4 PDFs using the pre-installed Chromium.
//   node marketing/build-pdfs.mjs
import { chromium } from '@playwright/test';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import fs from 'node:fs';

const dir = path.dirname(fileURLToPath(import.meta.url));

function findChromium() {
  const base = process.env.PLAYWRIGHT_BROWSERS_PATH;
  if (!base) return undefined;
  try {
    for (const d of fs.readdirSync(base).filter(d => /^chromium-\d+$/.test(d))) {
      const p = path.join(base, d, 'chrome-linux', 'chrome');
      if (fs.existsSync(p)) return p;
    }
  } catch (e) {}
  return undefined;
}

const pages = [
  { html: 'yebosell-onepager.html', pdf: 'YeboSell-One-Pager.pdf' },
  { html: 'seller-onboarding.html', pdf: 'YeboSell-Seller-Onboarding.pdf' },
];

const browser = await chromium.launch({ executablePath: findChromium() });
const page = await browser.newPage();
for (const { html, pdf } of pages) {
  await page.goto('file://' + path.join(dir, html), { waitUntil: 'load' });
  await page.pdf({ path: path.join(dir, pdf), format: 'A4', printBackground: true,
                   margin: { top: '0', bottom: '0', left: '0', right: '0' } });
  console.log('wrote', pdf);
}
await browser.close();
