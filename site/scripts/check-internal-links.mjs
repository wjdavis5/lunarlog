// Internal link check over the Astro build output (`site/dist`).
//
// Walks every built HTML file and every built CSS file, collects same-origin
// references, and fails when a referenced file is missing from `dist/`.
// Deliberately dependency-free: it is the CI guard for acceptance criterion 3
// (a broken internal link fails the site build), so it must not itself need
// network access or a browser.
//
//   node scripts/check-internal-links.mjs
//
// Exits non-zero and prints every broken reference when any is found.

import { readdir, readFile, stat } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";

const dist = path.resolve(
  fileURLToPath(new URL(".", import.meta.url)),
  "../dist",
);

/** Files under `dist` whose references should be checked. */
async function walk(dir) {
  const entries = await readdir(dir, { withFileTypes: true });
  const files = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      files.push(...(await walk(full)));
    } else if (entry.name.endsWith(".html") || entry.name.endsWith(".css")) {
      files.push(full);
    }
  }
  return files;
}

/** True when a reference is not a same-origin path we should resolve. */
function isResolvable(ref) {
  if (ref === "") return false;
  if (ref.startsWith("#")) return false;
  if (ref.startsWith("//")) return false;
  // Any scheme (https:, mailto:, tel:, data:, lunarlog:, ...) is out of scope.
  if (/^[a-z][a-z0-9+.-]*:/i.test(ref)) return false;
  return true;
}

async function exists(candidate) {
  try {
    await stat(candidate);
    return true;
  } catch {
    return false;
  }
}

/** Does a same-origin reference resolve to a file in `dist`? */
async function targetExists(resolved) {
  const candidates = [resolved];
  if (resolved.endsWith("/") || resolved.endsWith(path.sep)) {
    candidates.push(path.join(resolved, "index.html"));
  } else {
    candidates.push(`${resolved}.html`);
    candidates.push(path.join(resolved, "index.html"));
  }
  for (const candidate of candidates) {
    if (await exists(candidate)) return true;
  }
  return false;
}

const REFERENCE = /(?:href|src)\s*=\s*["']([^"']+)["']/gi;
const CSS_URL = /url\(\s*(['"]?)([^'")]+)\1\s*\)/gi;
// Resource-loading tags only: a plain `<a href>` to another origin is not a
// request, so it is deliberately not matched here. Acceptance criterion 4 is
// that loading a page makes zero requests off-origin.
const RESOURCE = /<(?:link|img|script|source|video|audio|iframe)\b[^>]*?(?:href|src)\s*=\s*["']([^"']+)["']/gi;
const OWN_HOSTS = new Set(["lunarlog.app", "www.lunarlog.app", "app.lunarlog.app"]);

function externalHost(ref) {
  const absolute = ref.startsWith("//") ? `https:${ref}` : ref;
  if (!/^[a-z][a-z0-9+.-]*:/i.test(absolute)) return null;
  let url;
  try {
    url = new URL(absolute);
  } catch {
    return null;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") return null;
  return OWN_HOSTS.has(url.hostname) ? null : url.hostname;
}

const errors = [];
const files = await walk(dist);

for (const file of files) {
  const content = await readFile(file, "utf8");
  const regex = file.endsWith(".css") ? CSS_URL : REFERENCE;

  for (const match of content.matchAll(regex)) {
    // The HTML regex captures the URL in group 1; the CSS regex in group 2.
    const ref = (match[2] ?? match[1] ?? "").trim();
    if (!isResolvable(ref)) continue;

    const clean = ref.split("#")[0].split("?")[0];
    if (clean === "") continue;

    const resolved = clean.startsWith("/")
      ? path.join(dist, clean)
      : path.resolve(path.dirname(file), clean);

    if (!resolved.startsWith(dist)) {
      errors.push(
        `${path.relative(dist, file)}: '${ref}' escapes the build output`,
      );
      continue;
    }
    if (!(await targetExists(resolved))) {
      errors.push(`${path.relative(dist, file)}: '${ref}' has no target`);
    }
  }

  // Off-origin resource references are banned outright (acceptance 4).
  if (!file.endsWith(".css")) {
    for (const match of content.matchAll(RESOURCE)) {
      const ref = match[1].trim();
      const host = externalHost(ref);
      if (host) {
        errors.push(`${path.relative(dist, file)}: '${ref}' loads from ${host}`);
      }
    }
  } else {
    for (const match of content.matchAll(CSS_URL)) {
      const ref = match[2].trim();
      const host = externalHost(ref);
      if (host) {
        errors.push(`${path.relative(dist, file)}: '${ref}' loads from ${host}`);
      }
    }
  }
}

if (errors.length > 0) {
  console.error(`Broken internal references (${errors.length}):`);
  for (const error of errors) console.error(`  - ${error}`);
  process.exit(1);
}

console.log(`Internal link check passed (${files.length} files scanned).`);
