// External (outbound) link check over the Astro build output (`site/dist`).
//
// Scans every built HTML file for absolute `http(s)://` links to another
// origin and checks each one responds. The weekly `site.yml` schedule runs
// this; `site.yml` files or refreshes a single rolling issue when it fails
// (the #707 pattern), rather than one issue per run.
//
// Until issue #1104 adds the outbound medical sources there are no external
// links, so this is a deliberate no-op that exits 0.
//
//   node scripts/check-external-links.mjs

import { readdir, readFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dist = path.resolve(
  fileURLToPath(new URL(".", import.meta.url)),
  "../dist",
);

const OWN_ORIGINS = new Set(["lunarlog.app", "www.lunarlog.app", "app.lunarlog.app"]);
const HTTP_LINK = /https?:\/\/[^\s"'<>()]+/gi;

async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(full)));
    } else if (entry.name.endsWith(".html")) {
      files.push(full);
    }
  }
  return files;
}

const files = await walk(dist);
const links = new Set();

for (const file of files) {
  const content = await readFile(file, "utf8");
  for (const match of content.matchAll(HTTP_LINK)) {
    let url;
    try {
      url = new URL(match[0]);
    } catch {
      continue;
    }
    if (OWN_ORIGINS.has(url.hostname)) continue;
    links.add(url.origin + url.pathname + url.search);
  }
}

if (links.size === 0) {
  console.log(
    "External link check: no outbound links yet (ok until issue #1104 adds the medical sources).",
  );
  process.exit(0);
}

const failures = [];

async function check(url) {
  for (const method of ["HEAD", "GET"]) {
    try {
      const response = await fetch(url, {
        method,
        redirect: "follow",
        signal: AbortSignal.timeout(20_000),
        headers: { "User-Agent": "lunarlog-site-link-check" },
      });
      // A server that rejects HEAD with 405 is fine; the GET retry settles it.
      if (response.status < 400 || response.status === 405) return;
      if (method === "GET") {
        failures.push(`${url}: HTTP ${response.status}`);
        return;
      }
    } catch (error) {
      if (method === "GET") {
        failures.push(`${url}: ${error.message}`);
        return;
      }
    }
  }
}

await Promise.all([...links].sort().map(check));

if (failures.length > 0) {
  console.error(`Broken external links (${failures.length}):`);
  for (const failure of failures) console.error(`  - ${failure}`);
  process.exit(1);
}

console.log(`External link check passed (${links.size} outbound links).`);
