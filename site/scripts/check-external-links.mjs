// External (outbound) link check over the Astro build output (`site/dist`).
//
// Scans every built HTML file for absolute `http(s)://` links to another
// origin and checks each one responds. The weekly `site.yml` schedule runs
// this; `site.yml` files or refreshes a single rolling issue when it fails
// (the #707 pattern), rather than one issue per run. A manual dispatch of
// `site.yml` runs it too (issue #1899), so a merged link fix can be verified
// on a runner without waiting for the next Monday.
//
// The first outbound links are the /learn article sources (issue #1811),
// rendered from the #1103 literacy export.
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
// doi.org and its legacy dx. host: checked at the DOI registration instead
// of through the redirect chain -- see `checkExternalLinks`.
const DOI_HOSTS = new Set(["doi.org", "dx.doi.org"]);
const CHECK_TIMEOUT_MS = 20_000;

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

// The DOI in a doi.org link, or null for anything else. Exported for the
// unit tests (`npm test` from site/).
export function doiFromUrl(url) {
  let parsed;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (!DOI_HOSTS.has(parsed.hostname)) return null;
  const doi = decodeURIComponent(parsed.pathname.replace(/^\//, ""));
  return doi.startsWith("10.") ? doi : null;
}

// The link check itself, with the fetch injected so the unit tests can drive
// every branch without a network. Returns the failure strings (empty = pass).
//
// A doi.org link is checked at Crossref, not at the publisher page it
// redirects to. The /learn article sources cite 10.1002/ijgo.12666 (Wiley)
// and 10.1056/NEJM199512073332301 (NEJM), and both publishers answer every
// non-browser client with HTTP 403 -- a browser UA included -- while the
// DOIs themselves are registered and resolve in a real browser. A 403 is an
// answer about the client, not about the reference; a dead reference is a
// 404. The stable, bot-friendly existence check for a DOI is its
// registration: the Crossref REST API answers 200 for a registered DOI and
// 404 for one that is not, from any IP (issue #1899). Everything else is
// checked by request as before: HEAD, then GET only when HEAD is
// inconclusive -- a server that rejects HEAD with 405 is fine.
export async function checkExternalLinks(
  links,
  { fetchImpl = fetch, timeoutMs = CHECK_TIMEOUT_MS } = {},
) {
  const failures = [];

  async function check(url) {
    const doi = doiFromUrl(url);
    if (doi !== null) {
      const endpoint = `https://api.crossref.org/works/${doi}`;
      let response;
      try {
        response = await fetchImpl(endpoint, {
          redirect: "follow",
          signal: AbortSignal.timeout(timeoutMs),
          headers: { "User-Agent": "lunarlog-site-link-check" },
        });
      } catch (error) {
        failures.push(`${url}: ${error.message}`);
        return;
      }
      if (response.status === 404) {
        failures.push(`${url}: DOI not found (Crossref 404)`);
      } else if (response.status >= 400) {
        failures.push(`${url}: Crossref HTTP ${response.status}`);
      }
      return;
    }

    for (const method of ["HEAD", "GET"]) {
      try {
        const response = await fetchImpl(url, {
          method,
          redirect: "follow",
          signal: AbortSignal.timeout(timeoutMs),
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
  return failures;
}

async function main() {
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
    return;
  }

  const failures = await checkExternalLinks(links);

  if (failures.length > 0) {
    console.error(`Broken external links (${failures.length}):`);
    for (const failure of failures) console.error(`  - ${failure}`);
    process.exit(1);
  }

  console.log(`External link check passed (${links.size} outbound links).`);
}

// Only run when executed directly, so the unit tests can import the helpers.
if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  await main();
}
