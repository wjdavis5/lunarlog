// Applies the down build's rule to the invite page: when the browser
// version is down (LUNARLOG_WEB_APP_LIVE=false), no page may link to its
// address (check-web-app-down.mjs enforces that), and the invite page's
// web-app button is a plain href the Astro build cannot gate. This drops
// the button, its lead-in line, and the script lines that would rewrite its
// href. The custom-scheme button and the install steps stay: they are the
// page's primary path and work with the address down.
//
// Runs as the last step of `npm run build`, so every build that carries the
// down flag gets it, and no-ops otherwise. A miss (the page's markup moved)
// fails check-web-app-down.mjs right after, naming the page.
//
// Usage: node scripts/apply-web-app-down.mjs [dist-directory]

import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { WEB_APP_HOST } from "../src/lib/web-app.mjs";

const dist = path.resolve(process.argv[2] ?? "dist");

if (process.env.LUNARLOG_WEB_APP_LIVE !== "false") {
  process.exit(0);
}

const invitePath = path.join(dist, "invite.html");
const before = readFileSync(invitePath, "utf-8");
const after = before
  .replace(
    /<p>On a computer, you can accept the invitation in the web app instead \(issue #1255\):<\/p>\s*/,
    "",
  )
  .replace(/<p><a id="open-in-web-app"[^>]*>[^<]*<\/a><\/p>\s*/, "")
  .replace(
    /\r?\n\s*var webLink = document\.getElementById\('open-in-web-app'\);\r?\n\s*if \(webLink\) \{ webLink\.setAttribute\('href', '[^']*' \+ query\); \}/,
    "",
  );

if (after !== before) {
  writeFileSync(invitePath, after);
}

// The down variant's invariant: the page must not mention the address at
// all, links or script strings. Failing here names this script in the build
// log instead of the check's page list.
if (after.includes(WEB_APP_HOST)) {
  console.error(
    "apply-web-app-down: invite.html still mentions the web app after the transform",
  );
  process.exit(1);
}
