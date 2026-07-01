// Render the branded marketing HTML files to A4 PDFs using the pre-installed Chromium.
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

// Running header/footer for the multi-page training guide (page numbers included).
const HF = { color: '#94a3b8' };
const headerTemplate = `<div style="width:100%;font-size:8px;color:${HF.color};font-family:Arial,Helvetica,sans-serif;padding:0 14mm;display:flex;justify-content:space-between;">
  <span style="font-weight:bold;color:#166534;">YeboSell — Seller Training Guide</span>
  <span>Sell smarter. Reach further. Grow together.</span></div>`;
const footerTemplate = `<div style="width:100%;font-size:8px;color:${HF.color};font-family:Arial,Helvetica,sans-serif;padding:0 14mm;display:flex;justify-content:space-between;">
  <span>yebosell.co.za &nbsp;·&nbsp; Support +266 5729 9369</span>
  <span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span></div>`;

// Full-bleed one-pagers (CSS controls the page + margins).
const onePager = { format: 'A4', printBackground: true, preferCSSPageSize: true };
// Multi-page guide: uniform margins + running header/footer with page numbers.
const guide = {
  format: 'A4', printBackground: true, displayHeaderFooter: true,
  headerTemplate, footerTemplate,
  margin: { top: '20mm', bottom: '16mm', left: '14mm', right: '14mm' },
};

const pages = [
  { html: 'yebosell-onepager.html',       pdf: 'YeboSell-One-Pager.pdf',            opts: onePager },
  { html: 'seller-onboarding.html',       pdf: 'YeboSell-Seller-Onboarding.pdf',    opts: onePager },
  { html: 'seller-training-guide.html',   pdf: 'YeboSell-Seller-Training-Guide.pdf', opts: guide },
];

const browser = await chromium.launch({ executablePath: findChromium() });
const page = await browser.newPage();
for (const { html, pdf, opts } of pages) {
  await page.goto('file://' + path.join(dir, html), { waitUntil: 'load' });
  await page.pdf({ path: path.join(dir, pdf), ...opts });
  console.log('wrote', pdf);
}
await browser.close();
