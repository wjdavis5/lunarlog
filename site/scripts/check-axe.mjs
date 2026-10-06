// Accessibility check with axe-core over the built site.
//
// Serves `site/dist` on an ephemeral local port, drives it with the system
// Chrome through puppeteer-core, injects axe-core, and fails on any
// violation. One process, start to finish -- no background server to leak.
//
// While each page is open it is also measured at two phone widths, and the
// check fails if the page itself scrolls sideways at either. axe does not
// look for that, and it is how the privacy policy's table went out 112 px
// wider than a 390 px screen.
//
// At the wider of the two it also measures every link and button that
// stands on its own (not one inside a sentence) and fails on any under
// 44 px tall: axe accepts 24 px, which a thumb does not.
//
//   node scripts/check-axe.mjs
//
// Set `CHROME_PATH` when Chrome is not in its usual location.

import http from "node:http";
import { existsSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath } from "node:url";
import puppeteer from "puppeteer-core";

const require = createRequire(import.meta.url);
const axePath = require.resolve("axe-core/axe.min.js");
const dist = path.resolve(
  fileURLToPath(new URL(".", import.meta.url)),
  "../dist",
);

const PAGES = [
  "/",
  "/privacy",
  "/delete-account/",
  "/support/",
  // Issue #1105 feature pages (built as dist/<path>/index.html).
  "/tracking/",
  "/family-sharing/",
  "/life-stage-modes/",
  "/import/",
  "/export/",
  "/privacy-security/",
  // The how-to guides (issue #1106).
  "/guides/",
  "/guides/getting-started/",
  "/guides/household-setup/",
  "/guides/inviting-someone/",
  "/guides/transferring-ownership/",
  "/guides/logging-a-day/",
  "/guides/reading-estimates/",
  "/guides/moving-your-data/",
  "/guides/browser-version/",
];

const MIME = {
  ".css": "text/css; charset=utf-8",
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".json": "application/json; charset=utf-8",
  ".png": "image/png",
  ".txt": "text/plain; charset=utf-8",
  ".woff": "font/woff",
  ".woff2": "font/woff2",
  ".xml": "application/xml; charset=utf-8",
};

function startServer() {
  return new Promise((resolve) => {
    const server = http.createServer(async (req, res) => {
      const url = new URL(req.url ?? "/", "http://localhost");
      let filePath = path.join(dist, decodeURIComponent(url.pathname));
      try {
        const info = await stat(filePath);
        if (info.isDirectory()) filePath = path.join(filePath, "index.html");
        const body = await readFile(filePath);
        res.writeHead(200, {
          "Content-Type": MIME[path.extname(filePath)] ?? "application/octet-stream",
        });
        res.end(body);
      } catch {
        try {
          const body = await readFile(path.join(dist, "404.html"));
          res.writeHead(404, { "Content-Type": "text/html; charset=utf-8" });
          res.end(body);
        } catch {
          res.writeHead(404);
          res.end("Not found");
        }
      }
    });
    server.listen(0, "127.0.0.1", () => resolve(server));
  });
}

function findChrome() {
  const candidates = [
    process.env.CHROME_PATH,
    "C:/Program Files/Google/Chrome/Application/chrome.exe",
    "C:/Program Files (x86)/Google/Chrome/Application/chrome.exe",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
  ].filter(Boolean);
  for (const candidate of candidates) {
    if (existsSync(candidate)) return candidate;
  }
  throw new Error("Chrome not found. Set CHROME_PATH to its executable.");
}

const server = await startServer();
const address = server.address();
const base = `http://127.0.0.1:${address.port}`;

const browser = await puppeteer.launch({
  executablePath: findChrome(),
  headless: true,
  args: ["--no-sandbox", "--disable-dev-shm-usage"],
});

// The widths a page must fit without scrolling sideways: a current phone
// and the narrowest one still in use. Each is restored to the desktop
// viewport before axe runs, so axe sees what it always saw.
const PHONE_WIDTHS = [390, 320];
const DESKTOP_VIEWPORT = { width: 800, height: 600 };

/** How far the page scrolls sideways at `width`, in CSS pixels. */
async function sidewaysOverflow(page, width) {
  await page.setViewport({ width, height: 844 });
  return await page.evaluate(() => {
    const root = document.documentElement;
    return root.scrollWidth - root.clientWidth;
  });
}

/** The least height, in CSS pixels, of a control a thumb has to hit. */
const MIN_TARGET = 44;

/**
 * Links and buttons under [MIN_TARGET] tall at the current viewport. A link
 * inside a sentence is `display: inline` and is left out: it is as tall as
 * its line. One the keyboard brings on screen (the skip link) is measured
 * where it sits.
 */
async function shortTargets(page) {
  return await page.evaluate((min) => {
    const found = [];
    for (const el of document.querySelectorAll("a, button, summary")) {
      const box = el.getBoundingClientRect();
      if (box.width === 0 || box.height === 0) continue;
      if (getComputedStyle(el).display === "inline") continue;
      if (box.height < min) {
        const label = (el.textContent ?? "").trim().slice(0, 30);
        found.push(`${label} (${Math.round(box.height)} px)`);
      }
    }
    return found;
  }, MIN_TARGET);
}

const violations = [];
const overflows = [];
const targets = [];
try {
  const page = await browser.newPage();
  for (const route of PAGES) {
    await page.goto(base + route, { waitUntil: "networkidle0" });
    for (const width of PHONE_WIDTHS) {
      const extra = await sidewaysOverflow(page, width);
      if (extra > 0) overflows.push({ route, width, extra });
      if (width === PHONE_WIDTHS[0]) {
        for (const target of await shortTargets(page)) {
          targets.push({ route, target });
        }
      }
    }
    await page.setViewport(DESKTOP_VIEWPORT);
    await page.addScriptTag({ path: axePath });
    const result = await page.evaluate(async () => {
      return await globalThis.axe.run(document);
    });
    for (const violation of result.violations) {
      violations.push({ route, ...violation });
    }
  }
} finally {
  await browser.close();
  server.close();
}

if (violations.length > 0) {
  console.error(`axe violations (${violations.length}):`);
  for (const violation of violations) {
    console.error(
      `  - ${violation.route} [${violation.impact}] ${violation.id}: ${violation.help}`,
    );
    for (const node of violation.nodes) {
      console.error(`      target: ${node.target.join(" ")}`);
    }
  }
}

if (overflows.length > 0) {
  console.error(`pages that scroll sideways (${overflows.length}):`);
  for (const { route, width, extra } of overflows) {
    console.error(`  - ${route} at ${width} px: ${extra} px too wide`);
  }
}

if (targets.length > 0) {
  console.error(
    `links and buttons under ${MIN_TARGET} px tall at ${PHONE_WIDTHS[0]} px ` +
      `(${targets.length}):`,
  );
  for (const { route, target } of targets) {
    console.error(`  - ${route}: ${target}`);
  }
}

if (violations.length + overflows.length + targets.length > 0) {
  process.exit(1);
}

console.log(
  `axe check passed (${PAGES.length} page(s), zero violations, ` +
    `none scrolls sideways at ${PHONE_WIDTHS.join(" or ")} px, ` +
    `no link or button under ${MIN_TARGET} px tall).`,
);
