// Checks the site as it is built when the browser version's address is
// down (LUNARLOG_WEB_APP_LIVE=false, see src/lib/web-app.mjs).
//
// Run after `LUNARLOG_WEB_APP_LIVE=false npm run build`. It reads dist/ and
// fails when any page still links to the address, when the home page still
// shows the button that leads there, or when a page that mentions the
// address no longer says it is unavailable. Without this the fallback is
// only ever exercised during an outage, which is the wrong time to find
// out that a new page linked straight to the address.
//
// Usage: node scripts/check-web-app-down.mjs [dist-directory]

import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";

import { WEB_APP_HOST, WEB_APP_URL } from "../src/lib/web-app.mjs";

const dist = path.resolve(process.argv[2] ?? "dist");

/** Every .html file under [directory]. */
function htmlFiles(directory) {
  const found = [];
  for (const name of readdirSync(directory)) {
    const full = path.join(directory, name);
    if (statSync(full).isDirectory()) found.push(...htmlFiles(full));
    else if (name.endsWith(".html")) found.push(full);
  }
  return found;
}

const problems = [];
const pages = htmlFiles(dist);
if (pages.length === 0) problems.push(`no HTML found under ${dist}`);

let mentions = 0;
for (const file of pages) {
  const html = readFileSync(file, "utf-8");
  const page = path.relative(dist, file);
  // No link of any kind to the address: not the button, not an in-text
  // link, not a canonical or a preload.
  if (new RegExp(`(href|src|action)="${WEB_APP_URL}`).test(html)) {
    problems.push(`${page}: still links to ${WEB_APP_URL}`);
  }
  if (html.includes(WEB_APP_HOST)) mentions += 1;
}

const home = readFileSync(path.join(dist, "index.html"), "utf-8").replace(/\s+/g, " ");
if (home.includes("Use lunarlog in your browser")) {
  problems.push("index.html: the button that leads to the address is still there");
}
if (!home.includes("The browser version is not available right now.")) {
  problems.push("index.html: the hero does not say the browser version is unavailable");
}
if (!/<a class="button" href="\/guides\/">/.test(home)) {
  problems.push("index.html: the hero offers nothing to do in place of the button");
}

for (const page of [
  "delete-account/index.html",
  "guides/browser-version/index.html",
  "guides/getting-started/index.html",
]) {
  const html = readFileSync(path.join(dist, page), "utf-8").replace(/\s+/g, " ");
  if (!html.includes(`${WEB_APP_HOST} (not available right now)`)) {
    problems.push(`${page}: names the address without saying it is unavailable`);
  }
}

if (problems.length > 0) {
  console.error("Web-app-down check FAILED:");
  for (const problem of problems) console.error(`  - ${problem}`);
  process.exit(1);
}
console.log(
  `Web-app-down check passed (${pages.length} pages, none links to ${WEB_APP_HOST}; ` +
    `${mentions} mention it).`,
);
