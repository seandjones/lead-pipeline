'use strict';
const express = require('express');
const puppeteer = require('puppeteer');

const app = express();
app.use(express.json());

const PORT = parseInt(process.env.PORT || '3001', 10);
const TIMEOUT = parseInt(process.env.SCRAPER_TIMEOUT_MS || '25000', 10);

// POST /scrape { url }  →  { html, finalUrl, error }
app.post('/scrape', async (req, res) => {
  const { url } = req.body || {};
  if (!url) {
    return res.status(400).json({ html: null, finalUrl: null, error: 'Missing url param' });
  }

  let browser;
  try {
    browser = await puppeteer.launch({
      headless: 'new',
      args: [
        '--no-sandbox',
        '--disable-setuid-sandbox',
        '--disable-dev-shm-usage',
        '--disable-accelerated-2d-canvas',
        '--no-first-run',
        '--no-zygote',
        '--single-process',
        '--disable-gpu',
        '--disable-extensions',
      ],
    });

    const page = await browser.newPage();

    // Block images, fonts, media, and stylesheets to reduce RAM and load time
    await page.setRequestInterception(true);
    page.on('request', (r) => {
      if (['image', 'font', 'media', 'stylesheet'].includes(r.resourceType())) {
        r.abort();
      } else {
        r.continue();
      }
    });

    await page.setUserAgent(
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36'
    );

    await page.goto(url, { waitUntil: 'networkidle2', timeout: TIMEOUT });

    // Brief pause for any deferred JS to finish rendering
    await new Promise((r) => setTimeout(r, 1500));

    const html = await page.content();
    const finalUrl = page.url();

    res.json({ html, finalUrl, error: null });
  } catch (err) {
    res.status(500).json({ html: null, finalUrl: null, error: err.message });
  } finally {
    if (browser) await browser.close().catch(() => {});
  }
});

app.get('/health', (_req, res) => res.json({ ok: true }));

app.listen(PORT, '0.0.0.0', () => {
  console.log(`Scraper listening on :${PORT}`);
});
