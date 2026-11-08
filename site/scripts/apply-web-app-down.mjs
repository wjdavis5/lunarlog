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
// `--check` (issue #1930) asserts the transform's postcondition on an
// already-built page instead of rewriting it: the page no longer mentions
// the address or carries the web-app paragraph/button, and the
// custom-scheme button and the install steps survived. site.yml's "Verify
// the public/ files were copied verbatim" step calls this on a down build,
// where the byte-identity cmp against public/invite.html can never pass
// because this script has just legitimately rewritten the page (every
// Dependabot/fork run is a down run — secrets read as empty there; #1655
// fixed the same contradiction for the browser figure, and the live build
// keeps the verbatim cmp, which the invite Worker's hash-pinned CSP makes
// load-bearing). Unlike the apply mode, --check ignores LUNARLOG_WEB_APP_LIVE:
// it answers "is this page in the down state?" and fails loudly on a live
// page, and its caller (the workflow's down branch) already knows the mode.
//
// Usage: node scripts/apply-web-app-down.mjs [dist-directory] [--check]

import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

import { WEB_APP_HOST } from "../src/lib/web-app.mjs";

const args = process.argv.slice(2);
const check = args.includes("--check");
const dist = path.resolve(args.find((arg) => !arg.startsWith("--")) ?? "dist");

// The apply mode is gated on the env var (see the header for why --check
// is not).
if (!check && process.env.LUNARLOG_WEB_APP_LIVE !== "false") {
  process.exit(0);
}

/** The down transform: drop the web-app paragraph, button, and script lines. */
function applyDownTransform(html) {
  return html
    .replace(
      /<p>On a computer, you can accept the invitation in the web app instead \(issue #1255\):<\/p>\s*/,
      "",
    )
    .replace(/<p><a id="open-in-web-app"[^>]*>[^<]*<\/a><\/p>\s*/, "")
    .replace(
      /\r?\n\s*var webLink = document\.getElementById\('open-in-web-app'\);\r?\n\s*if \(webLink\) \{ webLink\.setAttribute\('href', '[^']*' \+ query\); \}/,
      "",
    );
}

const invitePath = path.join(dist, "invite.html");
const before = readFileSync(invitePath, "utf-8");
const after = applyDownTransform(before);

if (check) {
  // Issue #1930: the down-mode stand-in for site.yml's verbatim cmp, using
  // the transform's own regexes. The transform must find nothing left to
  // remove (after === before), and the page as it stands — `before`, not
  // the re-transformed `after` — must not mention the address at all and
  // must still carry its primary path.
  const problems = [];
  if (after !== before) {
    problems.push(
      "the down transform still matches — the page was not built in down mode, or the markup moved",
    );
  }
  if (before.includes(WEB_APP_HOST)) {
    problems.push(`still mentions ${WEB_APP_HOST}`);
  }
  if (!/id="open-in-app"/.test(before)) {
    problems.push('the custom-scheme button (id="open-in-app") is gone');
  }
  if (!/href="lunarlog:\/\/invite"/.test(before)) {
    problems.push("the custom-scheme href (lunarlog://invite) is gone");
  }
  if (!/Install lunarlog on your device\./.test(before)) {
    problems.push("the install steps are gone");
  }
  if (problems.length > 0) {
    console.error("apply-web-app-down --check FAILED for invite.html:");
    for (const problem of problems) console.error(`  - ${problem}`);
    process.exit(1);
  }
  console.log(
    "apply-web-app-down --check passed: invite.html is in the down state " +
      `(no ${WEB_APP_HOST} mention; the custom-scheme button and the install steps survived).`,
  );
  process.exit(0);
}

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
