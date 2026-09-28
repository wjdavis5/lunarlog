// Accessibility check with axe-core over the built site.
//
// Serves `site/dist` on an ephemeral local port, drives it with the system
// Chrome through puppeteer-core, injects axe-core, and fails on any
// violation. One process, start to finish -- no background server to leak.
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

const violations = [];
try {
  const page = await browser.newPage();
  for (const route of PAGES) {
    await page.goto(base + route, { waitUntil: "networkidle0" });
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
  process.exit(1);
}

console.log(`axe check passed (${PAGES.length} page(s), zero violations).`);
